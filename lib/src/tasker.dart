import 'package:flutter/services.dart';
import 'package:via_native/via_native.dart';

import 'api.dart';
import 'command.dart';
import 'config.dart';
import 'sender.dart';

/// The Tasker plugin (Android only): the "Via Command" event fires when a command arrives,
/// and the "Send Via Command" action sends one.
class Tasker {
  /// The event's edit activity, which names the event when asking Tasker to query it.
  static const _eventActivity = 'com.kamofa.via.tasker.CommandEventEditActivity';

  /// Commands go to Tasker only when this is on; otherwise they're plain text.
  static Future<bool> commandsEnabled() => Prefs.getBool('tasker_commands');
  static Future<void> setCommandsEnabled(bool v) => Prefs.setBool('tasker_commands', v);

  /// Accepting commands from contacts is opt-in: they would run your Tasker tasks.
  static Future<bool> acceptsFromContacts() => Prefs.getBool('commands_from_contacts');
  static Future<void> setAcceptsFromContacts(bool v) => Prefs.setBool('commands_from_contacts', v);

  /// Hands a received command to Tasker, which then queries every "Via Command" event.
  static Future<void> commandReceived(ViaCommand command, {required String from, required String raw}) =>
      ViaNative.requestTaskerQuery(_eventActivity, {
        'command': command.name,
        'params': command.params,
        'from': from,
        'raw': raw,
      });

  /// Runs a "Send Via Command" action. Returns an error message, or null when sent.
  static Future<String?> send(Map<String, dynamic> job) async {
    final account = await Account.load();
    if (account == null) return 'Via is not connected to a server';
    final to = [for (final id in job['to'] as List? ?? const []) '$id'];
    if (to.isEmpty) return 'No devices to send to';
    final String text;
    try {
      text = ViaCommand('${job['command'] ?? ''}', [
        for (final p in job['params'] as List? ?? const []) '$p',
      ]).encode();
    } on ArgumentError catch (e) {
      return '${e.message}: ${e.invalidValue}';
    }
    try {
      await Sender.send(account, SendKind.text, to, text: text);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not send: $e';
    }
  }
}

/// The channel between a Tasker plugin activity and its Flutter UI (`taskerEditMain`).
class TaskerEditChannel {
  static const _channel = MethodChannel('via/tasker_edit');

  /// `event` or `action`, and the values saved last time (empty when new).
  static Future<(String, Map<String, String>)> config() async {
    final raw = (await _channel.invokeMapMethod<String, dynamic>('config'))!;
    final values = Map<String, dynamic>.from(raw['values'] as Map? ?? const {});
    return (raw['mode'] as String, values.map((k, v) => MapEntry(k, '$v')));
  }

  /// Returns the configuration to Tasker and closes. [blurb] is what Tasker shows for it.
  static Future<void> save(Map<String, String> values, String blurb) =>
      _channel.invokeMethod('save', {'values': values, 'blurb': blurb});

  static Future<void> cancel() => _channel.invokeMethod('cancel');
}
