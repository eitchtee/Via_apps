import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:via_native/via_native.dart';

import '../src/api.dart';
import '../src/config.dart';
import '../src/sender.dart';
import 'compose.dart';

/// Android share target: a dialog over the sharing app that works out whether a link,
/// text or files were shared, and asks which devices to send them to. When a device was
/// picked in the share sheet, it only shows the send's progress.
class SharePopup extends StatefulWidget {
  const SharePopup({super.key});

  @override
  State<SharePopup> createState() => _SharePopupState();
}

class _SharePopupState extends State<SharePopup> {
  Account? _account;
  SharedData? _data;
  bool _loading = true;
  String? _error;

  /// The user asked for the full form after a direct send failed.
  bool _chooseDevices = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final account = await Account.load();
      final data = await ViaNative.getSharedData();
      setState(() {
        _account = account;
        _data = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not read what was shared: $e';
        _loading = false;
      });
    }
  }

  void _close() => SystemNavigator.pop();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _close, // tapping outside the dialog cancels
        child: SafeArea(
          child: Center(
            child: GestureDetector(
              onTap: () {}, // don't close when tapping the dialog itself
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Card(
                  margin: const EdgeInsets.all(20),
                  elevation: 6,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: SingleChildScrollView(child: _body(theme)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final account = _account;
    final data = _data;
    String? problem = _error;
    if (problem == null && account == null) problem = 'Open Via and connect it to your server first.';
    if (problem == null && (data == null || (data.files.isEmpty && (data.text ?? '').trim().isEmpty))) {
      problem = 'Nothing to send.';
    }
    if (problem != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Via', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(problem),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: _close, child: const Text('Close')),
          ),
        ],
      );
    }

    // Files win; otherwise a lone URL (optionally with a title) is a link; else text.
    final SendKind kind;
    String? text;
    String? title;
    final files = [for (final f in data!.files) OutgoingFile(f.path, f.name, f.size, mime: f.mime)];
    if (files.isNotEmpty) {
      kind = SendKind.file;
    } else {
      final shared = data.text!.trim();
      final link = extractLink(shared);
      if (link != null) {
        kind = SendKind.link;
        text = link;
        final rest = shared.replaceFirst(link, '').trim();
        title = rest.isNotEmpty ? rest : data.subject;
      } else {
        kind = SendKind.text;
        text = shared;
        title = data.subject;
      }
    }

    final target = data.target;
    if (target != null && !_chooseDevices) {
      return _DirectSend(
        account: account!,
        kind: kind,
        to: target,
        label: data.targetLabel ?? 'your device',
        type: data.targetType ?? 'other',
        text: text,
        title: title,
        files: files,
        onSent: () => Future<void>.delayed(const Duration(milliseconds: 700), _close),
        onChooseDevices: () => setState(() => _chooseDevices = true),
        onClose: _close,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(iconForKind(kind), color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(titleForKind(kind, files.length), style: theme.textTheme.titleLarge)),
            IconButton(tooltip: 'Cancel', icon: const Icon(Icons.close), onPressed: _close),
          ],
        ),
        if (title != null && title.isNotEmpty && kind == SendKind.link)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        const SizedBox(height: 8),
        ComposeForm(
          account: account!,
          kind: kind,
          initialText: text,
          title: kind == SendKind.link ? title : null,
          files: files,
          popup: true,
          initialTargets: target == null ? null : [target],
          onSent: (message) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
            Future<void>.delayed(const Duration(milliseconds: 700), _close);
          },
        ),
      ],
    );
  }
}

/// Sends to the target picked in the share sheet right away, showing only the progress.
/// On failure it offers to retry or to pick devices in the full form.
class _DirectSend extends StatefulWidget {
  const _DirectSend({
    required this.account,
    required this.kind,
    required this.to,
    required this.label,
    required this.type,
    this.text,
    this.title,
    this.files = const [],
    required this.onSent,
    required this.onChooseDevices,
    required this.onClose,
  });

  final Account account;
  final SendKind kind;
  final String to;
  final String label;
  final String type;
  final String? text;
  final String? title;
  final List<OutgoingFile> files;
  final VoidCallback onSent;
  final VoidCallback onChooseDevices;
  final VoidCallback onClose;

  @override
  State<_DirectSend> createState() => _DirectSendState();
}

class _DirectSendState extends State<_DirectSend> {
  bool _sent = false;
  String? _error;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _send();
  }

  Future<void> _send() async {
    setState(() {
      _error = null;
      _progress = widget.kind == SendKind.file ? 0 : null;
    });
    try {
      await Sender.send(
        widget.account,
        widget.kind,
        [widget.to],
        text: widget.text,
        title: widget.title,
        files: widget.files,
        onProgress: (p, _) {
          if (mounted) setState(() => _progress = p);
        },
      );
      await Sender.rememberTargets([widget.to]);
      if (!mounted) return;
      setState(() => _sent = true);
      widget.onSent();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not send: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error;
    final String status;
    if (error != null) {
      status = 'Could not send to ${widget.label}';
    } else if (_sent) {
      status = 'Sent to ${widget.label}';
    } else {
      status = 'Sending to ${widget.label}…';
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              _sent ? Icons.check_circle : iconForType(widget.type),
              color: error != null ? theme.colorScheme.error : theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(status, style: theme.textTheme.titleMedium)),
            IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: widget.onClose),
          ],
        ),
        if (error == null && !_sent) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _progress),
        ],
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: widget.onChooseDevices, child: const Text('Choose devices')),
              const SizedBox(width: 8),
              FilledButton(onPressed: _send, child: const Text('Retry')),
            ],
          ),
        ],
      ],
    );
  }
}
