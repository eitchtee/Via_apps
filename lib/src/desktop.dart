import 'dart:io';

import 'package:flutter/widgets.dart' show Size;
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Windows: lives in the tray so it keeps receiving when the window is closed, and can
/// start with Windows (hidden, with `--minimized`).
class Desktop with TrayListener, WindowListener {
  Desktop._();
  static final instance = Desktop._();

  static bool get supported => Platform.isWindows;

  Future<void> init(List<String> args) async {
    if (!supported) return;
    await windowManager.ensureInitialized();
    final hidden = args.contains('--minimized');
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(size: Size(460, 720), minimumSize: Size(380, 520), title: 'Via', center: true),
      () async {
        if (!hidden) {
          await windowManager.show();
          await windowManager.focus();
        }
      },
    );
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    await trayManager.setIcon('assets/icon/tray.ico');
    await trayManager.setToolTip('Via');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Open Via'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit'),
        ],
      ),
    );
    trayManager.addListener(this);

    launchAtStartup.setup(appName: 'Via', appPath: Platform.resolvedExecutable, args: ['--minimized']);
  }

  Future<void> show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<bool> startsWithWindows() => launchAtStartup.isEnabled();

  Future<void> setStartsWithWindows(bool on) => on ? launchAtStartup.enable() : launchAtStartup.disable();

  @override
  void onWindowClose() => windowManager.hide();

  @override
  void onTrayIconMouseDown() => show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        await show();
      case 'quit':
        await trayManager.destroy();
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
        exit(0);
    }
  }
}
