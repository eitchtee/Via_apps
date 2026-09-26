import 'dart:io';

import 'package:flutter/material.dart';

import '../src/api.dart';
import '../src/config.dart';
import '../src/models.dart';
import '../src/sender.dart';

IconData iconForType(String type) => switch (type) {
  'android' => Icons.phone_android,
  'ios' => Icons.phone_iphone,
  'desktop' => Icons.computer,
  'browser' => Icons.public,
  'cli' => Icons.terminal,
  'contact' => Icons.person_outline,
  _ => Icons.devices_other,
};

IconData iconForKind(SendKind kind) => switch (kind) {
  SendKind.link => Icons.link,
  SendKind.file => Icons.attach_file,
  SendKind.text => Icons.notes,
};

String titleForKind(SendKind kind, int files) => switch (kind) {
  SendKind.link => 'Send link',
  SendKind.text => 'Send text',
  SendKind.file => files == 1 ? 'Send file' : 'Send $files files',
};

/// The shared "what + to whom" form: used by the Send pages and by the Android share
/// popup ([popup] = true, more compact).
class ComposeForm extends StatefulWidget {
  const ComposeForm({
    super.key,
    required this.account,
    required this.kind,
    this.initialText,
    this.title,
    this.files = const [],
    this.popup = false,
    required this.onSent,
  });

  final Account account;
  final SendKind kind;
  final String? initialText;
  final String? title;
  final List<OutgoingFile> files;
  final bool popup;
  final void Function(String message) onSent;

  @override
  State<ComposeForm> createState() => _ComposeFormState();
}

class _ComposeFormState extends State<ComposeForm> {
  late final _text = TextEditingController(text: widget.initialText ?? '');
  late List<OutgoingFile> _files = [...widget.files];
  List<Target>? _targets;
  final _selected = <String>{};
  String? _loadError;
  String? _sendError;
  bool _sending = false;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final targets = await Sender.targets(widget.account);
      final last = await Sender.lastTargets();
      if (!mounted) return;
      setState(() {
        _targets = targets;
        _selected
          ..clear()
          ..addAll(last.where((id) => targets.any((t) => t.id == id)));
        // With a single other device, there's nothing to choose.
        if (_selected.isEmpty && targets.length == 1) _selected.add(targets.single.id);
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = '$e');
    }
  }

  bool get _hasContent => switch (widget.kind) {
    SendKind.file => _files.isNotEmpty,
    _ => _text.text.trim().isNotEmpty,
  };

  Future<void> _send() async {
    if (_selected.isEmpty || !_hasContent || _sending) return;
    final to = [
      for (final t in _targets!)
        if (_selected.contains(t.id)) t.id,
    ];
    setState(() {
      _sending = true;
      _sendError = null;
      _progress = widget.kind == SendKind.file ? 0 : null;
    });
    try {
      await Sender.send(
        widget.account,
        widget.kind,
        to,
        text: _text.text,
        title: widget.title,
        files: _files,
        onProgress: (p, _) {
          if (mounted) setState(() => _progress = p);
        },
      );
      await Sender.rememberTargets(to);
      final names = _targets!.where((t) => _selected.contains(t.id)).map((t) => t.label).join(', ');
      widget.onSent('Sent to $names');
    } on ApiException catch (e) {
      setState(() => _sendError = e.message);
    } catch (e) {
      setState(() => _sendError = 'Could not send: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _content(theme),
        SizedBox(height: widget.popup ? 16 : 24),
        Text(
          'Send to',
          style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        _targetPicker(theme),
        if (_sendError != null) ...[
          const SizedBox(height: 12),
          Text(_sendError!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        SizedBox(height: widget.popup ? 16 : 24),
        if (_sending && _progress != null) ...[
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 12),
        ],
        FilledButton.icon(
          onPressed: _selected.isEmpty || !_hasContent || _sending ? null : _send,
          icon: _sending
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send),
          label: Text(_sending ? 'Sending…' : 'Send'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ],
    );
  }

  Widget _content(ThemeData theme) {
    switch (widget.kind) {
      case SendKind.link:
        return TextField(
          controller: _text,
          autofocus: !widget.popup && _text.text.isEmpty,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Link',
            hintText: 'https://…',
            prefixIcon: Icon(Icons.link),
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _send(),
        );
      case SendKind.text:
        return TextField(
          controller: _text,
          autofocus: !widget.popup && _text.text.isEmpty,
          minLines: widget.popup ? 2 : 5,
          maxLines: widget.popup ? 6 : 12,
          decoration: const InputDecoration(
            labelText: 'Text',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        );
      case SendKind.file:
        return Card.outlined(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (final f in _files)
                ListTile(
                  dense: widget.popup,
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(formatSize(f.size)),
                  trailing: widget.popup || _sending
                      ? null
                      : IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _files = [..._files]..remove(f)),
                        ),
                ),
              if (_files.isEmpty) const ListTile(title: Text('No files selected')),
            ],
          ),
        );
    }
  }

  Widget _targetPicker(ThemeData theme) {
    if (_loadError != null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Could not load your devices: $_loadError',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      );
    }
    final targets = _targets;
    if (targets == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (targets.isEmpty) {
      return Text(
        'No other devices yet. Install Via on another device, or add the browser extension.',
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    final all = targets.every((t) => _selected.contains(t.id));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (targets.length > 1)
          FilterChip(
            avatar: const Icon(Icons.select_all, size: 18),
            label: const Text('All'),
            selected: all,
            showCheckmark: false,
            onSelected: _sending
                ? null
                : (on) => setState(() {
                    _selected.clear();
                    if (on) _selected.addAll(targets.map((t) => t.id));
                  }),
          ),
        for (final t in targets)
          FilterChip(
            avatar: Icon(iconForType(t.type), size: 18),
            label: Text(t.label),
            selected: _selected.contains(t.id),
            showCheckmark: false,
            onSelected: _sending
                ? null
                : (on) => setState(() => on ? _selected.add(t.id) : _selected.remove(t.id)),
          ),
      ],
    );
  }
}

/// Full-screen Send page (main app).
class ComposePage extends StatelessWidget {
  const ComposePage({super.key, required this.account, required this.kind, this.files = const []});

  final Account account;
  final SendKind kind;
  final List<OutgoingFile> files;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titleForKind(kind, files.length))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ComposeForm(
                account: account,
                kind: kind,
                files: files,
                onSent: (message) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                  Navigator.of(context).pop();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<List<OutgoingFile>> toOutgoing(Iterable<String> paths) async => [
  for (final path in paths)
    OutgoingFile(path, path.split(Platform.pathSeparator).last.split('/').last, await File(path).length()),
];
