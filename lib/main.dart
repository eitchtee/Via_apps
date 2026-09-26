import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';

import 'src/config.dart';
import 'src/desktop.dart';
import 'src/history.dart';
import 'src/live.dart';
import 'src/notify.dart';
import 'src/receiver.dart';
import 'ui/home.dart';
import 'ui/onboarding.dart';
import 'ui/share_popup.dart';

const _seed = Color(0xFF0E7C66);

ThemeData _theme(Brightness brightness) => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
  useMaterial3: true,
);

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Desktop.instance.init(args);
  await Notify.init(onTap: _openItem);
  if (Platform.isAndroid) await Workmanager().initialize(callbackDispatcher);
  runApp(const ViaApp());
}

/// Android share target (ShareActivity).
@pragma('vm:entry-point')
void shareMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      title: 'Via',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      color: Colors.transparent,
      home: const SharePopup(),
    ),
  );
}

/// Headless sync after an FCM wake-up (WakeWorker).
@pragma('vm:entry-point')
Future<void> wakeMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Notify.init();
    await AndroidBackground.registerPush();
    await Receiver.sync();
  } finally {
    await const MethodChannel('via/wake').invokeMethod('done');
  }
}

/// Periodic fallback sync (WorkManager).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    await Notify.init();
    await AndroidBackground.registerPush();
    await Receiver.sync();
    return true;
  });
}

Future<void> _openItem(String id) async {
  final entry = await History.get(id);
  if (entry != null) await Receiver.activate(entry);
}

class ViaApp extends StatefulWidget {
  const ViaApp({super.key});

  @override
  State<ViaApp> createState() => _ViaAppState();
}

class _ViaAppState extends State<ViaApp> with WidgetsBindingObserver {
  Account? _account;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Receiver.onSignedOut = () {
      if (mounted) setState(() => _account = null);
    };
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _init() async {
    final account = await Account.load();
    setState(() {
      _account = account;
      _loaded = true;
    });
    if (account != null) await _startReceiving();
    final launchedBy = await Notify.launchPayload();
    if (launchedBy != null) await _openItem(launchedBy);
  }

  Future<void> _startReceiving() async {
    Receiver.foreground = true;
    LiveUpdates.start();
    unawaited(Receiver.sync());
    await Notify.requestPermission();
    await AndroidBackground.schedule();
    await AndroidBackground.registerPush();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On Windows the app keeps running in the tray, so only Android reacts.
    if (!Platform.isAndroid || _account == null) return;
    if (state == AppLifecycleState.resumed) {
      Receiver.foreground = true;
      LiveUpdates.start();
      unawaited(Receiver.sync());
    } else if (state == AppLifecycleState.paused) {
      Receiver.foreground = false;
      LiveUpdates.stop();
    }
  }

  void _onAccountChanged(Account? account) {
    final signedIn = _account == null && account != null;
    setState(() => _account = account);
    if (signedIn) _startReceiving();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Via',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: !_loaded
          ? const Scaffold()
          : _account == null
          ? OnboardingPage(onDone: _onAccountChanged)
          : HomePage(
              key: ValueKey(_account!.deviceId),
              account: _account!,
              onAccountChanged: _onAccountChanged,
            ),
    );
  }
}
