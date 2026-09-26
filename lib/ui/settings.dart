import 'package:flutter/material.dart';

import '../src/api.dart';
import '../src/config.dart';
import '../src/desktop.dart';
import '../src/history.dart';
import '../src/live.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.account, required this.onAccountChanged});

  final Account account;
  final void Function(Account? account) onAccountChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Account _account = widget.account;
  bool _autoOpen = true;
  bool _autoCopy = true;
  bool? _startup;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final autoOpen = await Prefs.getBool('auto_open_links', fallback: true);
    final autoCopy = await Prefs.getBool('auto_copy_text', fallback: true);
    final startup = Desktop.supported ? await Desktop.instance.startsWithWindows() : null;
    if (mounted) {
      setState(() {
        _autoOpen = autoOpen;
        _autoCopy = autoCopy;
        _startup = startup;
      });
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _rename() async {
    final controller = TextEditingController(text: _account.deviceName)
      ..selection = TextSelection(baseOffset: 0, extentOffset: _account.deviceName.length);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename this device'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 64,
          decoration: const InputDecoration(labelText: 'Device name'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Rename')),
        ],
      ),
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == _account.deviceName) return;
    final api = _account.api();
    try {
      final device = await api.renameMe(trimmed);
      final updated = _account.withName(device.name);
      await updated.save();
      setState(() => _account = updated);
      widget.onAccountChanged(updated);
      _snack('Renamed to ${device.name}');
    } on ApiException catch (e) {
      _snack(e.status == 405 ? 'This server is too old to rename devices from the app.' : e.message);
    } catch (e) {
      _snack('Could not rename: $e');
    } finally {
      api.close();
    }
  }

  /// Removing a device needs the account password (a device token can't delete itself).
  Future<void> _signOut() async {
    final password = TextEditingController();
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your password to remove this device from your account. '
              'Items waiting for it will be dropped.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, 'local'),
            child: const Text('Only on this device'),
          ),
          FilledButton(onPressed: () => Navigator.pop(context, 'remove'), child: const Text('Remove device')),
        ],
      ),
    );
    if (choice == null) return;
    if (choice == 'remove') {
      final api = _account.api();
      try {
        final me = await api.me();
        final username = await _usernameFor();
        if (username == null) return;
        final session = await api.login(username, password.text);
        try {
          await api.deleteDevice(session, me.id);
        } finally {
          await api.logout(session);
        }
      } on ApiException catch (e) {
        _snack(e.code == 'invalid_credentials' ? 'Wrong password.' : e.message);
        return;
      } catch (e) {
        _snack('Could not remove the device: $e');
        return;
      } finally {
        api.close();
      }
    }
    LiveUpdates.stop();
    await AndroidBackground.cancel();
    await Account.clear();
    await History.wipe();
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    widget.onAccountChanged(null);
  }

  Future<String?> _usernameFor() async {
    final saved = await Prefs.getString('username');
    if (saved != null && saved.isNotEmpty) return saved;
    final controller = TextEditingController();
    if (!mounted) return null;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Username'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Username'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return name == null || name.isEmpty ? null : name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          header('This device'),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Device name'),
            subtitle: Text(_account.deviceName),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _rename,
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Server'),
            subtitle: Text(_account.server),
          ),
          header('When something arrives'),
          SwitchListTile(
            secondary: const Icon(Icons.open_in_browser),
            title: const Text('Open links automatically'),
            subtitle: const Text('Only https links from your own devices'),
            value: _autoOpen,
            onChanged: (v) {
              setState(() => _autoOpen = v);
              Prefs.setBool('auto_open_links', v);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.content_paste),
            title: const Text('Copy text to the clipboard'),
            subtitle: const Text('Only text from your own devices'),
            value: _autoCopy,
            onChanged: (v) {
              setState(() => _autoCopy = v);
              Prefs.setBool('auto_copy_text', v);
            },
          ),
          if (_startup != null) ...[
            header('Windows'),
            SwitchListTile(
              secondary: const Icon(Icons.power_settings_new),
              title: const Text('Start with Windows'),
              subtitle: const Text('Runs in the tray so it can receive'),
              value: _startup!,
              onChanged: (v) async {
                await Desktop.instance.setStartsWithWindows(v);
                setState(() => _startup = v);
              },
            ),
          ],
          header('Account'),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text('Sign out', style: TextStyle(color: theme.colorScheme.error)),
            onTap: _signOut,
          ),
        ],
      ),
    );
  }
}
