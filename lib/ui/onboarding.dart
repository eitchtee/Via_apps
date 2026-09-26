import 'dart:io';

import 'package:flutter/material.dart';
import 'package:via_native/via_native.dart';

import '../src/api.dart';
import '../src/config.dart';

/// Connect to a self-hosted server, sign in, and register this device under a name.
/// Only the device token is kept; the session is logged out right away.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.onDone});

  final void Function(Account account) onDone;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

enum _Step { server, signIn }

class _OnboardingPageState extends State<OnboardingPage> {
  var _step = _Step.server;
  final _server = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _deviceName = TextEditingController(text: _defaultDeviceName());
  String? _serverUrl;
  String? _error;
  bool _busy = false;

  static String _defaultDeviceName() {
    if (Platform.isWindows) {
      final host = Platform.localHostname;
      return host.isEmpty ? 'Windows PC' : host;
    }
    return 'Android phone';
  }

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      ViaNative.deviceName().then((name) {
        if (name != null && name.isNotEmpty && mounted) _deviceName.text = name;
      }, onError: (_) {});
    }
    Account.lastServer().then((s) {
      if (s != null && _server.text.isEmpty && mounted) _server.text = s;
    });
  }

  @override
  void dispose() {
    for (final c in [_server, _username, _password, _deviceName]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _connect() async {
    final input = _server.text.trim();
    if (input.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final url = normalizeServerUrl(input);
    final api = ViaApi(url);
    try {
      final info = await api.info();
      if (info.apiVersion != 1) {
        throw ApiException(
          0,
          'unsupported',
          'This server speaks API version ${info.apiVersion}, this app needs 1.',
        );
      }
      setState(() {
        _serverUrl = url;
        _step = _Step.signIn;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = "Couldn't reach a Via server at $url.\n$e");
    } finally {
      api.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    final name = _deviceName.text.trim();
    if (_username.text.trim().isEmpty || _password.text.isEmpty || name.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ViaApi(_serverUrl!);
    try {
      final session = await api.login(_username.text.trim(), _password.text);
      try {
        final (device, token) = await api.registerDevice(
          session,
          name,
          Platform.isAndroid ? 'android' : 'desktop',
        );
        final account = Account(
          server: _serverUrl!,
          deviceId: device.id,
          deviceName: device.name,
          token: token,
        );
        await account.save();
        await Prefs.setString('username', _username.text.trim());
        widget.onDone(account);
      } finally {
        await api.logout(session);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.code == 'invalid_credentials' ? 'Wrong username or password.' : e.message);
    } catch (e) {
      setState(() => _error = 'Sign in failed: $e');
    } finally {
      api.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: Image.asset('assets/icon/app-icon-256.png', width: 72, height: 72)),
                    const SizedBox(height: 16),
                    Text('Via', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    Text(
                      _step == _Step.server
                          ? 'Send links, text and files between your devices, through your own server.'
                          : 'Sign in to ${Uri.parse(_serverUrl!).host} and name this device.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 32),
                    ...switch (_step) {
                      _Step.server => _serverStep(),
                      _Step.signIn => _signInStep(),
                    },
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _serverStep() => [
    TextField(
      controller: _server,
      enabled: !_busy,
      keyboardType: TextInputType.url,
      autocorrect: false,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'Server address',
        hintText: 'via.example.com',
        prefixIcon: Icon(Icons.dns_outlined),
        border: OutlineInputBorder(),
      ),
      onSubmitted: (_) => _connect(),
    ),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: _busy ? null : _connect,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      child: _busy ? const _Spinner() : const Text('Continue'),
    ),
  ];

  List<Widget> _signInStep() => [
    TextField(
      controller: _username,
      enabled: !_busy,
      autocorrect: false,
      autofocus: true,
      autofillHints: const [AutofillHints.username],
      decoration: const InputDecoration(
        labelText: 'Username',
        prefixIcon: Icon(Icons.person_outline),
        border: OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _password,
      enabled: !_busy,
      obscureText: true,
      autofillHints: const [AutofillHints.password],
      decoration: const InputDecoration(
        labelText: 'Password',
        prefixIcon: Icon(Icons.lock_outline),
        border: OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 24),
    TextField(
      controller: _deviceName,
      enabled: !_busy,
      maxLength: 64,
      decoration: InputDecoration(
        labelText: 'Name for this device',
        helperText: 'How it shows up on your other devices',
        prefixIcon: Icon(Platform.isAndroid ? Icons.phone_android : Icons.computer),
        border: const OutlineInputBorder(),
      ),
      onSubmitted: (_) => _signIn(),
    ),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: _busy ? null : _signIn,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      child: _busy ? const _Spinner() : const Text('Sign in'),
    ),
    const SizedBox(height: 8),
    TextButton(
      onPressed: _busy
          ? null
          : () => setState(() {
              _step = _Step.server;
              _error = null;
            }),
      child: const Text('Change server'),
    ),
    const SizedBox(height: 8),
    Text(
      'Your password is only used to register this device. Via keeps a device token, not your password.',
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  ];
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) =>
      const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2));
}
