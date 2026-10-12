import 'package:flutter/material.dart';

import '../src/command.dart';
import '../src/config.dart';
import '../src/models.dart';
import '../src/sender.dart';
import '../src/tasker.dart';
import 'compose.dart';

/// What Tasker opens to configure the "Via Command" event or the "Send Via Command" action,
/// as a dialog over Tasker.
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
                    _ => _ActionForm(values: _values),
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

Widget _header(BuildContext context, String title) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: Row(
    children: [
      Icon(Icons.bolt, color: Theme.of(context).colorScheme.primary),
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
        _header(context, 'Via Command'),
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

class _ActionForm extends StatefulWidget {
  const _ActionForm({required this.values});

  final Map<String, String> values;

  @override
  State<_ActionForm> createState() => _ActionFormState();
}

class _ActionFormState extends State<_ActionForm> {
  late final _command = TextEditingController(text: widget.values['command'] ?? '');
  late final List<TextEditingController> _params = [
    for (var i = 0; i < (int.tryParse(widget.values['param_count'] ?? '') ?? 0); i++)
      TextEditingController(text: widget.values['param$i'] ?? ''),
  ];
  late final Set<String> _selected = {
    for (final id in (widget.values['to'] ?? '').split(',')) if (id.isNotEmpty) id,
  };
  Account? _account;
  List<Target>? _targets;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _command.dispose();
    for (final p in _params) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final account = await Account.load();
      if (account == null) {
        setState(() => _error = 'Open Via and connect it to your server first.');
        return;
      }
      final targets = await Sender.targets(account);
      setState(() {
        _account = account;
        _targets = targets;
        _selected.retainWhere((id) => targets.any((t) => t.id == id));
      });
    } catch (e) {
      setState(() => _error = 'Could not load your devices: $e');
    }
  }

  void _save() {
    final names = _targets!.where((t) => _selected.contains(t.id)).map((t) => t.label);
    final name = _command.text.trim();
    final params = [for (final p in _params) p.text];
    TaskerEditChannel.save(
      {
        'to': _selected.join(','),
        'command': name,
        'param_count': '${params.length}',
        for (final (i, p) in params.indexed) 'param$i': p,
      },
      '${[name, ...params].join(' · ')} → ${names.join(', ')}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = _command.text.trim();
    final nameError = name.isEmpty || _validName(name) ? null : 'Letters, digits, _ and -, starting with a letter';
    final canSave = _account != null && _selected.isNotEmpty && name.isNotEmpty && nameError == null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, 'Send Via Command'),
        Text('To', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        _targetPicker(theme),
        const SizedBox(height: 16),
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

  Widget _targetPicker(ThemeData theme) {
    if (_error != null) {
      return Row(
        children: [
          Expanded(child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
          if (_account != null || !_error!.startsWith('Open Via'))
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
    if (targets.isEmpty) return const Text('No other devices yet.');
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in targets)
          FilterChip(
            avatar: Icon(iconForType(t.type), size: 18),
            label: Text(t.label),
            selected: _selected.contains(t.id),
            showCheckmark: false,
            onSelected: (on) => setState(() => on ? _selected.add(t.id) : _selected.remove(t.id)),
          ),
      ],
    );
  }
}
