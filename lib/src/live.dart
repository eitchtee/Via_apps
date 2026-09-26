import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';

import 'api.dart';
import 'config.dart';
import 'receiver.dart';

/// Keeps `GET /v1/inbox/events` open while running and syncs on `ready` and `push`.
/// Reconnects with backoff, and treats 60 s of silence (pings come every ~25 s) as a
/// dead connection.
class LiveUpdates {
  static http.Client? _client;
  static bool _running = false;
  static int _generation = 0;

  static bool get running => _running;

  static void start() {
    if (_running) return;
    _running = true;
    unawaited(_run(++_generation));
  }

  static void stop() {
    _running = false;
    _generation++;
    _client?.close();
    _client = null;
  }

  static void restart() {
    stop();
    start();
  }

  static Future<void> _run(int generation) async {
    var backoff = 1;
    final random = Random();
    while (_running && generation == _generation) {
      final account = await Account.load();
      if (account == null) {
        _running = false;
        return;
      }
      final connectedAt = DateTime.now();
      try {
        await _listen(account, generation);
      } on ApiException catch (e) {
        if (e.isUnauthorized) {
          await Receiver.signedOut();
          _running = false;
          return;
        }
      } catch (_) {}
      if (!_running || generation != _generation) return;
      // A connection that lasted a while resets the backoff.
      if (DateTime.now().difference(connectedAt) > const Duration(minutes: 1)) backoff = 1;
      final delay = backoff * 1000 + random.nextInt(1000);
      backoff = min(backoff * 2, 60);
      await Future<void>.delayed(Duration(milliseconds: delay));
    }
  }

  static Future<void> _listen(Account account, int generation) async {
    final client = _client = http.Client();
    final api = ViaApi(account.server, token: account.token, client: client);
    final response = await api.events(client);
    String? event;
    final data = StringBuffer();
    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .timeout(const Duration(seconds: 60))) {
      if (generation != _generation) break;
      if (line.isEmpty) {
        await _dispatch(event ?? 'message', data.toString());
        event = null;
        data.clear();
      } else if (line.startsWith(':')) {
        continue; // ping
      } else if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        if (data.isNotEmpty) data.write('\n');
        data.write(line.substring(5).trimLeft());
      }
    }
    client.close();
  }

  static Future<void> _dispatch(String event, String data) async {
    switch (event) {
      case 'ready':
      case 'push':
        unawaited(Receiver.sync());
      case 'revoked':
        await Receiver.signedOut();
        stop();
      // 'recalled': nothing to do; the item simply won't be in the inbox.
    }
  }
}

/// Android background delivery: FCM wake-ups when the app was built with Firebase, plus
/// a periodic sync as the fallback.
class AndroidBackground {
  static const _fcm = MethodChannel('via/fcm');
  static const periodicTask = 'via-periodic-sync';

  static Future<void> schedule() async {
    if (!Platform.isAndroid) return;
    await Workmanager().registerPeriodicTask(
      periodicTask,
      periodicTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  static Future<void> cancel() async {
    if (Platform.isAndroid) await Workmanager().cancelAll();
  }

  /// Registers the FCM token with the server when it changed. No-op without Firebase or
  /// when the server has no relay configured.
  static Future<void> registerPush({bool force = false}) async {
    if (!Platform.isAndroid) return;
    final account = await Account.load();
    if (account == null) return;
    String? token;
    try {
      token = await _fcm.invokeMethod<String>('getToken');
    } catch (_) {
      token = null;
    }
    if (token == null) return;
    final key = '${account.deviceId}:$token';
    if (!force && await Prefs.getString('push_registration') == key) return;
    final api = account.api();
    try {
      final info = await api.info();
      if (!info.features.contains('fcm_relay')) return;
      await api.setPushProvider('fcm_relay', token: token);
      await Prefs.setString('push_registration', key);
    } catch (_) {
      // Retried on the next start or wake-up.
    } finally {
      api.close();
    }
  }
}
