import 'package:flutter/material.dart';
import 'package:via_native/via_native.dart';

import '../src/command.dart';
import '../src/config.dart';
import '../src/models.dart';
import '../src/sender.dart';
import '../src/tasker.dart';
import 'compose.dart';

/// What Tasker opens to configure the "Via Command" event or one of the actions ("Send Via
/// Command", "Send with Via"), as a dialog over Tasker.
class TaskerEditPopup extends StatefulWidget {
  const TaskerEditPopup({super.key});

  @override
  State<TaskerEditPopup> createState() => _TaskerEditPopupState();
}

class _TaskerEditPopupState extends State<TaskerEditPopup> {
  String? _mode;
  Map<String, String> _values = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final (mode, values) = await TaskerEditChannel.config();
    setState(() {
      _mode = mode;
      _values = values;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              margin: const EdgeInsets.all(20),
              elevation: 6,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: SingleChildScrollView(
                  child: switch (_mode) {
                    null => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    'event' => _EventForm(values: _values),
                    'item' => _ItemForm(values: _values),
                    _ => _CommandForm(values: _values),
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _header(BuildContext context, IconData icon, String title) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: Row(
    children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 12),
      Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
    ],
  ),
);

Widget _buttons({required VoidCallback? onSave}) => Padding(
  padding: const EdgeInsets.only(top: 8),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      TextButton(onPressed: TaskerEditChannel.cancel, child: const Text('Cancel')),
      const SizedBox(width: 8),
      FilledButton(onPressed: onSave, child: const Text('Save')),
    ],
  ),
);

/// A command name, or a Tasker variable that will hold one.
bool _validName(String name) => ViaCommand.isValidName(name) || name.contains('%');

class _EventForm extends StatefulWidget {
  const _EventForm({required this.values});

  final Map<String, String> values;

  @override
  State<_EventForm> createState() => _EventFormState();
}

class _EventFormState extends State<_EventForm> {
  late final _commands = TextEditingController(text: widget.values['commands'] ?? '');
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    Tasker.commandsEnabled().then((v) => setState(() => _enabled = v));
  }

  List<String> get _names => [
    for (final n in _commands.text.split(',')) if (n.trim().isNotEmpty) n.trim(),
  ];

  @override
  void dispose() {
    _commands.dispose();
    super.dispose();
  }

  void _save() {
    final names = _names;
    TaskerEditChannel.save({'commands': names.join(',')}, names.isEmpty ? 'Any command' : names.join(', '));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final invalid = _names.where((n) => !ViaCommand.isValidName(n)).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, Icons.bolt, 'Via Command'),
        if (_enabled == false)
          Card.filled(
            color: theme.colorScheme.errorContainer,
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              textColor: theme.colorScheme.onErrorContainer,
              title: const Text('Commands are off'),
              subtitle: const Text('Via treats them as normal text until you turn them on.'),
              trailing: TextButton(
                onPressed: () async {
                  await Tasker.setCommandsEnabled(true);
                  setState(() => _enabled = true);
                },
                child: const Text('Turn on'),
              ),
            ),
          ),
        TextField(
          controller: _commands,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Commands',
            hintText: 'lights_on, volume',
            helperText: 'Comma-separated. Leave empty to fire for any command.',
            errorText: invalid.isEmpty ? null : 'Not a command name: ${invalid.join(', ')}',
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: invalid.isEmpty ? (_) => _save() : null,
        ),
        const SizedBox(height: 16),
        Text(
          'Fires when another of your devices sends text like !:volume::40. Variables:\n'
          '%via_command  the command name\n'
          '%via_params()  its params (%via_params1, %via_params2, …)\n'
          '%via_from  the device that sent it\n'
          '%via_raw  the text as received',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        _buttons(onSave: invalid.isEmpty ? _save : null),
      ],
    );
  }
}

/// What both send actions share: picking the devices and contacts to send to.
abstract class _SendFormState<T extends StatefulWidget> extends State<T> {
  Map<String, String> get values;

  late final Set<String> selected = {
    for (final id in (values['to'] ?? '').split(',')) if (id.isNotEmpty) id,
  };
  Account? account;
  List<Target>? _targets;
  String? _error;

  String get targetNames => _targets!.where((t) => selected.contains(t.id)).map((t) => t.label).join(', ');

  @override
  void initState() {
    super.initState();
    _loadTargets();
  }

  Future<void> _loadTargets() async {
    setState(() => _error = null);
    try {
      final account = await Account.load();
      if (account == null) {
        setState(() => _error = 'Open Via and connect it to your server first.');
        return;
      }
      final targets = await Sender.targets(account);
      setState(() {
        this.account = account;
        _targets = targets;
        selected.retainWhere((id) => targets.any((t) => t.id == id));
      });
    } catch (e) {
      setState(() => _error = 'Could not load your devices: $e');
    }
  }

  Widget targetPicker(ThemeData theme) {
    if (_error != null) {
      return Row(
        children: [
          Expanded(child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
          if (!_error!.startsWith('Open Via')) TextButton(onPressed: _loadTargets, child: const Text('Retry')),
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
    if (targets.isEmpty) return const Text('No other devices yet.');
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in targets)
          FilterChip(
            avatar: Icon(iconForType(t.type), size: 18),
            label: Text(t.label),
            selected: selected.contains(t.id),
            showCheckmark: false,
            onSelected: (on) => setState(() => on ? selected.add(t.id) : selected.remove(t.id)),
          ),
      ],
    );
  }

  List<Widget> toSection(ThemeData theme) => [
    Text('To', style: theme.textTheme.labelLarge),
    const SizedBox(height: 8),
    targetPicker(theme),
    const SizedBox(height: 16),
  ];
}

class _CommandForm extends StatefulWidget {
  const _CommandForm({required this.values});

  final Map<String, String> values;

  @override
  State<_CommandForm> createState() => _CommandFormState();
}

class _CommandFormState extends _SendFormState<_CommandForm> {
  @override
  Map<String, String> get values => widget.values;

  late final _command = TextEditingController(text: values['command'] ?? '');
  late final List<TextEditingController> _params = [
    for (var i = 0; i < (int.tryParse(values['param_count'] ?? '') ?? 0); i++)
      TextEditingController(text: values['param$i'] ?? ''),
  ];

  @override
  void dispose() {
    _command.dispose();
    for (final p in _params) {
      p.dispose();
    }
    super.dispose();
  }

  void _save() {
    final name = _command.text.trim();
    final params = [for (final p in _params) p.text];
    TaskerEditChannel.save(
      {
        'type': 'command',
        'to': selected.join(','),
        'command': name,
        'param_count': '${params.length}',
        for (final (i, p) in params.indexed) 'param$i': p,
      },
      '${[name, ...params].join(' · ')} → $targetNames',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = _command.text.trim();
    final nameError = name.isEmpty || _validName(name) ? null : 'Letters, digits, _ and -, starting with a letter';
    final canSave = account != null && selected.isNotEmpty && name.isNotEmpty && nameError == null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, Icons.bolt, 'Send Via Command'),
        ...toSection(theme),
        TextField(
          controller: _command,
          decoration: InputDecoration(
            labelText: 'Command',
            hintText: 'volume',
            errorText: nameError,
            helperText: 'Tasker variables are allowed here and in the params.',
          ),
          onChanged: (_) => setState(() {}),
        ),
        for (final (i, p) in _params.indexed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              controller: p,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Param ${i + 1}',
                suffixIcon: IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => setState(() => _params.removeAt(i).dispose()),
                ),
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add param'),
            onPressed: () => setState(() => _params.add(TextEditingController())),
          ),
        ),
        _buttons(onSave: canSave ? _save : null),
      ],
    );
  }
}

class _ItemForm extends StatefulWidget {
  const _ItemForm({required this.values});

  final Map<String, String> values;

  @override
  State<_ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends _SendFormState<_ItemForm> with WidgetsBindingObserver {
  @override
  Map<String, String> get values => widget.values;

  late SendKind _kind = switch (values['kind']) {
    'link' => SendKind.link,
    'file' => SendKind.file,
    _ => SendKind.text,
  };
  late final _content = TextEditingController(text: values['content'] ?? '');
  late final _title = TextEditingController(text: values['title'] ?? '');
  bool? _fileAccess;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkFileAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _content.dispose();
    _title.dispose();
    super.dispose();
  }

  // Back from the system's "All files access" screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkFileAccess();
  }

  Future<void> _checkFileAccess() async {
    final access = await ViaNative.hasAllFilesAccess();
    if (mounted) setState(() => _fileAccess = access);
  }

  void _save() {
    final content = _content.text;
    final title = _kind == SendKind.file ? '' : _title.text.trim();
    final what = switch (_kind) {
      SendKind.text => 'Text',
      SendKind.link => 'Link',
      SendKind.file => 'File',
    };
    final preview = content.trim().split('\n').first;
    TaskerEditChannel.save(
      {
        'type': 'item',
        'to': selected.join(','),
        'kind': _kind.name,
        'content': content,
        'title': title,
      },
      '$what: ${preview.length > 60 ? '${preview.substring(0, 60)}…' : preview} → $targetNames',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = account != null && selected.isNotEmpty && _content.text.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, Icons.send_outlined, 'Send with Via'),
        ...toSection(theme),
        SegmentedButton<SendKind>(
          segments: const [
            ButtonSegment(value: SendKind.text, icon: Icon(Icons.notes), label: Text('Text')),
            ButtonSegment(value: SendKind.link, icon: Icon(Icons.link), label: Text('Link')),
            ButtonSegment(value: SendKind.file, icon: Icon(Icons.attach_file), label: Text('Files')),
          ],
          selected: {_kind},
          onSelectionChanged: (s) => setState(() => _kind = s.single),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _content,
          minLines: _kind == SendKind.link ? 1 : 2,
          maxLines: _kind == SendKind.link ? 1 : 6,
          keyboardType: _kind == SendKind.link ? TextInputType.url : TextInputType.multiline,
          decoration: InputDecoration(
            labelText: switch (_kind) {
              SendKind.text => 'Text',
              SendKind.link => 'Link',
              SendKind.file => 'Files',
            },
            hintText: switch (_kind) {
              SendKind.text => 'Hello from %DEVID',
              SendKind.link => 'https://example.com',
              SendKind.file => '/storage/emulated/0/Download/report.pdf',
            },
            helperText: _kind == SendKind.file
                ? 'One path per line, or a Tasker array like %files(). Variables are allowed.'
                : 'Tasker variables are allowed.',
            helperMaxLines: 2,
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_kind != SendKind.file) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title (optional)'),
          ),
        ],
        if (_kind == SendKind.file && _fileAccess == false)
          Card.filled(
            color: theme.colorScheme.errorContainer,
            margin: const EdgeInsets.only(top: 12),
            child: ListTile(
              textColor: theme.colorScheme.onErrorContainer,
              title: const Text('Via can\'t read your files'),
              subtitle: const Text('To send files by path, allow Via to access all files.'),
              trailing: TextButton(onPressed: ViaNative.requestAllFilesAccess, child: const Text('Allow')),
            ),
          ),
        _buttons(onSave: canSave ? _save : null),
      ],
    );
  }
}
