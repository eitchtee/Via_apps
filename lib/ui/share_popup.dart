import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:via_native/via_native.dart';

import '../src/config.dart';
import '../src/sender.dart';
import 'compose.dart';

/// Android share target: a dialog over the sharing app that works out whether a link,
/// text or files were shared, and asks which devices to send them to.
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
          onSent: (message) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
            Future<void>.delayed(const Duration(milliseconds: 700), _close);
          },
        ),
      ],
    );
  }
}
