import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;

import 'history.dart';

/// Notifications for received items. Tapping one runs [onTap] with the item id.
class Notify {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init({void Function(String itemId)? onTap}) async {
    if (_ready) return;
    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('ic_notification'),
        windows: WindowsInitializationSettings(
          appName: 'Via',
          appUserModelId: 'Via.Desktop.Client',
          guid: '6b1f2a4e-3c9d-4e8a-9f1b-2d7c5a0e8b31',
          iconPath: Platform.isWindows
              ? p.join(p.dirname(Platform.resolvedExecutable), 'data', 'flutter_assets', 'assets', 'icon', 'app-icon-256.png')
              : null,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final id = response.payload;
        if (id != null && id.isNotEmpty) onTap?.call(id);
      },
    );
    _ready = true;
  }

  /// The item id of the notification that launched the app, if any.
  static Future<String?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return details!.notificationResponse?.payload;
  }

  static Future<void> requestPermission() async {
    if (!Platform.isAndroid) return;
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> item(HistoryEntry e, {required String action}) async {
    final (title, body) = switch (e.kind) {
      'link' => (e.title ?? 'Link', e.url ?? ''),
      'note' => (e.title ?? 'Text', e.body ?? ''),
      _ => (e.fileName ?? 'File', e.status == 'ok' ? 'Saved to Downloads' : (e.error ?? 'Download failed')),
    };
    await _show(
      e.id.hashCode & 0x7fffffff,
      title,
      [body, 'From ${e.from} · $action'].where((s) => s.isNotEmpty).join('\n'),
      e.id,
    );
  }

  static Future<void> message(String title, String body) =>
      _show(title.hashCode & 0x7fffffff, title, body, null);

  static Future<void> _show(int id, String title, String body, String? payload) async {
    if (!_ready) await init();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      payload: payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'pushes',
          'Received items',
          channelDescription: 'Links, text and files sent to this device',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body),
        ),
        windows: const WindowsNotificationDetails(),
      ),
    );
  }
}
