import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../src/command.dart';
import '../src/config.dart';
import '../src/history.dart';
import '../src/platform.dart';
import '../src/receiver.dart';
import '../src/sender.dart';
import 'compose.dart';
import 'settings.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.account, required this.onAccountChanged});

  final Account account;
  final void Function(Account? account) onAccountChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  var _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Via' : 'History'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    SettingsPage(account: widget.account, onAccountChanged: widget.onAccountChanged),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: [
            SendTab(account: widget.account),
            const HistoryTab(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.send_outlined),
            selectedIcon: Icon(Icons.send),
            label: 'Send',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
        ],
      ),
    );
  }
}

class SendTab extends StatelessWidget {
  const SendTab({super.key, required this.account});

  final Account account;

  Future<void> _open(BuildContext context, SendKind kind) async {
    var files = <OutgoingFile>[];
    if (kind == SendKind.file) {
      final result = await FilePicker.pickFiles(allowMultiple: true);
      if (result == null) return;
      files = [
        for (final f in result.files)
          if (f.path != null) OutgoingFile(f.path!, f.name, f.size),
      ];
      if (files.isEmpty) return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ComposePage(account: account, kind: kind, files: files),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget option(SendKind kind, String title, String subtitle) => Card.filled(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context, kind),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                child: Icon(iconForKind(kind), size: 26),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                option(SendKind.link, 'Send link', 'Opens in the browser on the other device'),
                option(SendKind.file, 'Send file', 'Saved to Downloads on the other device'),
                option(SendKind.text, 'Send text', 'Copied to the clipboard on the other device'),
                const SizedBox(height: 8),
                Text(
                  'This device: ${account.deviceName}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> with WidgetsBindingObserver {
  List<HistoryEntry>? _entries;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = History.changes.listen((_) => _reload());
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  // Background isolates (Android wake-ups) write the history too.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _reload() async {
    final entries = await History.entries();
    if (mounted) setState(() => _entries = entries);
  }

  Future<void> _refresh() async {
    await Receiver.sync();
    await _reload();
  }

  void _snack(String? message) {
    if (message != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _openLink(String url) async {
    if (!await LocalActions.openUrl(url)) _snack('Could not open the link');
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    if (entries == null) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: entries.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 120),
                Icon(Icons.inbox_outlined, size: 56, color: theme.colorScheme.outline),
                const SizedBox(height: 12),
                Text(
                  'Nothing received yet',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            )
          : ListView.builder(
              itemCount: entries.length + 1,
              itemBuilder: (context, i) {
                if (i == entries.length) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: TextButton.icon(
                        onPressed: () async {
                          final ok = await _confirm(
                            context,
                            'Clear history?',
                            'Received files stay in Downloads.',
                          );
                          if (ok) await History.clear();
                        },
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: const Text('Clear history'),
                      ),
                    ),
                  );
                }
                final e = entries[i];
                return _HistoryTile(
                  entry: e,
                  onTap: () async => _snack(await Receiver.activate(e)),
                  onOpenLink: _openLink,
                  onAction: (action) async {
                    switch (action) {
                      case 'copy':
                        await LocalActions.copyText(e.url ?? e.body ?? e.title ?? '');
                        _snack('Copied to clipboard');
                      case 'open':
                        await _openLink(singleLink(e.body ?? e.title ?? '')!);
                      case 'folder':
                        if (!await LocalActions.showInFolder(e.location!)) {
                          _snack('Could not open the folder');
                        }
                      case 'retry':
                        await Receiver.retry(e.id);
                      case 'delete':
                        await History.remove(e.id);
                    }
                  },
                );
              },
            ),
    );
  }
}

Future<bool> _confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    ) ??
    false;

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.entry,
    required this.onTap,
    required this.onOpenLink,
    required this.onAction,
  });

  final HistoryEntry entry;
  final VoidCallback onTap;
  final void Function(String url) onOpenLink;
  final void Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = entry;
    final (icon, title, detail) = switch (e.kind) {
      'link' => (Icons.link, e.title ?? e.url ?? '', e.title != null ? e.url : null),
      'note' => (Icons.notes, e.title ?? e.body ?? '', e.title != null ? e.body : null),
      'file' => (
        Icons.insert_drive_file_outlined,
        e.fileName ?? 'File',
        switch (e.status) {
          'ok' => e.fileSize == null ? null : formatSize(e.fileSize!),
          'gone' => 'No longer available',
          _ => e.error ?? 'Download failed',
        },
      ),
      'command' => _command(e),
      _ => (Icons.help_outline, e.kind, null),
    };
    final failed = e.status != 'ok';
    final note = e.kind == 'note';
    final hasDetail = detail != null && detail.isNotEmpty;
    final meta = '${e.from} · ${_when(e.receivedAt)}';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: failed ? theme.colorScheme.errorContainer : theme.colorScheme.secondaryContainer,
        foregroundColor: failed ? theme.colorScheme.onErrorContainer : theme.colorScheme.onSecondaryContainer,
        child: Icon(icon),
      ),
      // Links in received text are tappable; tapping elsewhere still copies the text.
      title: note && e.title == null
          ? _LinkText(title, onOpen: onOpenLink, maxLines: 2)
          : Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: note && hasDetail
          ? _LinkText(detail, suffix: '\n$meta', onOpen: onOpenLink, maxLines: 3)
          : Text([if (hasDetail) detail, meta].join('\n'), maxLines: 3, overflow: TextOverflow.ellipsis),
      isThreeLine: hasDetail,
      onTap: onTap,
      trailing: PopupMenuButton<String>(
        onSelected: onAction,
        itemBuilder: (_) => [
          if (e.kind != 'file') const PopupMenuItem(value: 'copy', child: Text('Copy')),
          if (note && singleLink(e.body ?? e.title ?? '') != null)
            const PopupMenuItem(value: 'open', child: Text('Open link')),
          if (e.kind == 'file' && e.status == 'failed')
            const PopupMenuItem(value: 'retry', child: Text('Retry')),
          if (e.kind == 'file' && e.location != null && (Platform.isWindows || Platform.isAndroid))
            const PopupMenuItem(value: 'folder', child: Text('Show in folder')),
          const PopupMenuItem(value: 'delete', child: Text('Remove from history')),
        ],
      ),
    );
  }

  static (IconData, String, String?) _command(HistoryEntry e) {
    final command = ViaCommand.parse(e.body ?? '');
    if (command == null) return (Icons.bolt, e.body ?? '', e.error);
    final detail = e.status == 'ok' ? command.params.join(' · ') : e.error;
    return (Icons.bolt, command.name, detail);
  }

  static String _when(DateTime t) {
    final local = t.toLocal();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final time = '${two(local.hour)}:${two(local.minute)}';
    if (local.year == now.year && local.month == now.month && local.day == now.day) return time;
    return '${local.year}-${two(local.month)}-${two(local.day)} $time';
  }
}

/// Text with its http(s) URLs as tappable links, then an optional plain [suffix].
class _LinkText extends StatefulWidget {
  const _LinkText(this.text, {this.suffix, required this.onOpen, this.maxLines});

  final String text;
  final String? suffix;
  final void Function(String url) onOpen;
  final int? maxLines;

  @override
  State<_LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<_LinkText> {
  final _recognizers = <TapGestureRecognizer>[];

  void _clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final colors = Theme.of(context).colorScheme;
    final text = widget.text;
    final spans = <InlineSpan>[];
    var at = 0;
    for (final link in findLinks(text)) {
      spans.add(TextSpan(text: text.substring(at, link.start)));
      final recognizer = TapGestureRecognizer()..onTap = () => widget.onOpen(link.url);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: link.url,
          style: TextStyle(
            color: colors.primary,
            decoration: TextDecoration.underline,
            decorationColor: colors.primary,
          ),
          recognizer: recognizer,
        ),
      );
      at = link.end;
    }
    spans.add(TextSpan(text: text.substring(at) + (widget.suffix ?? '')));
    return Text.rich(
      TextSpan(children: spans),
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
