import 'package:via_native/via_native.dart';

import 'command.dart';
import 'config.dart';

/// The Tasker plugin (Android only): the "Via Command" event fires when a command arrives.
class Tasker {
  /// The event's edit activity, which names the event when asking Tasker to query it.
  static const _eventActivity = 'com.kamofa.via.tasker.CommandEventEditActivity';

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
}
