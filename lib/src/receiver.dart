import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'config.dart';
import 'history.dart';
import 'models.dart';
import 'notify.dart';
import 'platform.dart';

/// Fetches the inbox and handles each item: links are opened, text is copied, files are
/// saved to Downloads. An item is acked only once handled (see the server's clients.md).
class Receiver {
  /// Whether the app is visible. On Android, links can't be opened from the background,
  /// so they wait for a tap on the notification.
  static bool foreground = !Platform.isAndroid;

  /// Called when the server says this device no longer exists.
  static void Function()? onSignedOut;

  static Future<void>? _running;
  static bool _again = false;
  static final _failures = <String, int>{};

  /// Syncs now. Calls during a sync make it run once more afterwards.
  static Future<void> sync() {
    if (_running != null) {
      _again = true;
      return _running!;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  static Future<void> _loop() async {
    do {
      _again = false;
      final account = await Account.load();
      if (account == null) return;
      try {
        await _syncOnce(account);
      } on ApiException catch (e) {
        if (e.isUnauthorized) {
          await signedOut();
          return;
        }
      } catch (_) {
        // Network trouble: the next wake-up, reconnect or poll retries.
      }
    } while (_again);
  }

  static Future<void> signedOut() async {
    await Account.clear();
    await Notify.message('Via: signed out', 'This device was removed from your Via account.');
    onSignedOut?.call();
  }

  static Future<void> _syncOnce(Account account) async {
    final api = account.api();
    Map<String, String>? names;
    String? cursor;
    try {
      while (true) {
        final page = await api.inbox(after: cursor);
        if (page.items.isEmpty) break;
        for (final item in page.items) {
          if (await History.isHandled(item.id)) {
            await api.ack(item.id); // the earlier ack got lost
            continue;
          }
          if ((_failures[item.id] ?? 0) >= 3) continue; // wait for a manual retry
          names ??= await _deviceNames(api);
          if (await _handle(api, item, _from(item, names))) {
            _failures.remove(item.id);
            await api.ack(item.id);
          } else {
            _failures[item.id] = (_failures[item.id] ?? 0) + 1;
          }
        }
        cursor = page.cursor;
        if (cursor == null) break;
      }
    } finally {
      api.close();
    }
  }

  /// Lets a failed download be tried again on the next sync.
  static Future<void> retry(String id) {
    _failures.remove(id);
    return sync();
  }

  static Future<Map<String, String>> _deviceNames(ViaApi api) async {
    try {
      return {for (final d in await api.devices()) d.id: d.name};
    } catch (_) {
      return {};
    }
  }

  static String _from(InboxItem item, Map<String, String> names) {
    if (item.sender != null) return '@${item.sender}';
    if (item.sourceDeviceId == null) return 'Via';
    return names[item.sourceDeviceId] ?? 'another device';
  }

  /// Returns true when the item may be acked.
  static Future<bool> _handle(ViaApi api, InboxItem item, String from) async {
    final fromContact = item.sender != null;
    HistoryEntry base(String status, {String? location, String? error}) => HistoryEntry(
      id: item.id,
      kind: item.kind,
      receivedAt: DateTime.now(),
      from: from,
      fromContact: fromContact,
      title: item.title,
      body: item.body,
      url: item.url,
      fileName: item.file?.name,
      fileMime: item.file?.mime,
      fileSize: item.file?.size,
      location: location,
      status: status,
      error: error,
    );

    switch (item.kind) {
      case 'link':
        final url = item.url ?? '';
        // Only open https links from our own devices without asking (clients.md).
        final auto =
            foreground &&
            !fromContact &&
            url.startsWith('https://') &&
            await Prefs.getBool('auto_open_links', fallback: true);
        final opened = auto && await LocalActions.openUrl(url);
        final entry = base('ok');
        await History.put(entry, handled: true);
        await Notify.item(entry, action: opened ? 'Opened in your browser' : 'Tap to open');
        return true;

      case 'note':
        final text = item.body ?? item.title ?? '';
        final auto = !fromContact && await Prefs.getBool('auto_copy_text', fallback: true);
        var copied = false;
        if (auto) {
          try {
            await LocalActions.copyText(text);
            copied = true;
          } catch (_) {}
        }
        final entry = base('ok');
        await History.put(entry, handled: true);
        await Notify.item(entry, action: copied ? 'Copied to clipboard' : 'Tap to copy');
        return true;

      case 'file':
        final file = item.file;
        if (file == null || !file.available) {
          final entry = base('gone', error: 'The file is no longer available');
          await History.put(entry, handled: true);
          await Notify.item(entry, action: 'Not downloaded');
          return true;
        }
        try {
          final location = await _download(api, item.id, file);
          if (location == null) {
            final entry = base('gone', error: 'The file is no longer available');
            await History.put(entry, handled: true);
            return true;
          }
          final entry = base('ok', location: location);
          await History.put(entry, handled: true);
          await Notify.item(entry, action: 'Tap to open');
          return true;
        } on ApiException catch (e) {
          if (e.isUnauthorized) rethrow;
          await History.put(base('failed', error: e.message), handled: false);
          return false;
        } catch (e) {
          final entry = base('failed', error: 'Download failed: $e');
          await History.put(entry, handled: false);
          if ((_failures[item.id] ?? 0) >= 2) await Notify.item(entry, action: 'Retry from the history');
          return false;
        }
    }
    // Unknown kind from a newer server: keep it out of the way.
    await History.put(base('ok'), handled: true);
    return true;
  }

  /// Resumable, verified download. Returns where the file was saved, or null if the
  /// server no longer has it.
  static Future<String?> _download(ViaApi api, String id, InboxFile file) async {
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'via-downloads'));
    await dir.create(recursive: true);
    final part = File(p.join(dir.path, '$id.part'));
    if (!await api.downloadFile(id, part)) {
      if (await part.exists()) await part.delete();
      return null;
    }
    final digest = await sha256.bind(part.openRead()).first;
    if (file.sha256.isNotEmpty && digest.toString() != file.sha256.toLowerCase()) {
      await part.delete();
      throw const FileSystemException('checksum mismatch');
    }
    return LocalActions.saveDownload(part, file.name, file.mime);
  }

  /// What tapping a received item does: open the link or file, or copy the text.
  static Future<String?> activate(HistoryEntry e) async {
    switch (e.kind) {
      case 'link':
        return await LocalActions.openUrl(e.url ?? '') ? null : 'Could not open the link';
      case 'note':
        await LocalActions.copyText(e.body ?? e.title ?? '');
        return 'Copied to clipboard';
      case 'file':
        if (e.status == 'failed') {
          await retry(e.id);
          return 'Retrying…';
        }
        if (e.location == null) return 'The file was not downloaded';
        return await LocalActions.openFile(e.location!, e.fileMime) ? null : 'Could not open the file';
    }
    return null;
  }
}
