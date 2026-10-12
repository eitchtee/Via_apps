import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:via_native/via_native.dart';

import 'api.dart';
import 'command.dart';
import 'config.dart';
import 'sender.dart';

/// The Tasker plugin (Android only): the "Via Command" event fires when a command arrives,
/// the "Send Via Command" action sends one, and the "Send with Via" action sends text, a
/// link or files.
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

  /// Runs a Tasker action, given the values it was configured with (variables replaced).
  /// Returns an error message, or null when sent.
  static Future<String?> send(Map<String, dynamic> job) async {
    final values = job.map((k, v) => MapEntry(k, '${v ?? ''}'));
    final account = await Account.load();
    if (account == null) return 'Via is not connected to a server';
    final to = [for (final id in values['to']?.split(',') ?? const <String>[]) if (id.isNotEmpty) id];
    if (to.isEmpty) return 'No devices to send to';
    try {
      switch (values['type']) {
        case 'item':
          return await _sendItem(account, to, values);
        default: // command, also what 1.1.0 saved without a type
          final count = int.tryParse(values['param_count'] ?? '') ?? 0;
          final command = ViaCommand(values['command']?.trim() ?? '', [
            for (var i = 0; i < count; i++) values['param$i'] ?? '',
          ]);
          await Sender.send(account, SendKind.text, to, text: command.encode());
          return null;
      }
    } on ArgumentError catch (e) {
      return '${e.message}: ${e.invalidValue}';
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not send: $e';
    }
  }

  static Future<String?> _sendItem(Account account, List<String> to, Map<String, String> values) async {
    final content = values['content'] ?? '';
    final title = values['title']?.trim();
    switch (values['kind']) {
      case 'link':
        if (content.trim().isEmpty) return 'No link to send';
        await Sender.send(account, SendKind.link, to, text: content.trim(), title: title?.nullIfEmpty);
      case 'file':
        final paths = filePaths(content);
        if (paths.isEmpty) return 'No file to send';
        final files = <OutgoingFile>[];
        for (final path in paths) {
          final file = File(path);
          try {
            // Opening, not just exists(): without access a file can be seen but not read.
            await (await file.open()).close();
          } on FileSystemException catch (e) {
            if (!await file.exists()) return 'File not found: $path';
            return await ViaNative.hasAllFilesAccess()
                ? 'Cannot read $path: ${e.osError?.message ?? e.message}'
                : 'Cannot read $path: allow Via to access all files (open the action in Tasker)';
          }
          files.add(OutgoingFile(path, p.basename(path), await file.length()));
        }
        await Sender.send(account, SendKind.file, to, files: files);
      default:
        if (content.isEmpty) return 'No text to send';
        await Sender.send(account, SendKind.text, to, text: content, title: title?.nullIfEmpty);
    }
    return null;
  }

  /// The files in a "Send with Via" action: one path, or several separated by commas (how
  /// Tasker joins an array like `%files()`) or new lines. A path that exists as a whole
  /// wins, so a name with a comma still works on its own.
  static List<String> filePaths(String value) {
    final whole = value.trim();
    if (whole.isEmpty) return const [];
    if (File(whole).existsSync()) return [whole];
    return [
      for (final part in whole.split(RegExp(r'[,\n]'))) if (part.trim().isNotEmpty) part.trim(),
    ];
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

/// The channel between a Tasker plugin activity and its Flutter UI (`taskerEditMain`).
class TaskerEditChannel {
  static const _channel = MethodChannel('via/tasker_edit');

  /// `event`, `command` or `item`, and the values saved last time (empty when new).
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
