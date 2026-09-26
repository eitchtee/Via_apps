import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A received item, as kept in the local history.
class HistoryEntry {
  HistoryEntry({
    required this.id,
    required this.kind,
    required this.receivedAt,
    required this.from,
    this.fromContact = false,
    this.title,
    this.body,
    this.url,
    this.fileName,
    this.fileMime,
    this.fileSize,
    this.location,
    this.status = 'ok',
    this.error,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
    id: j['id'] as String,
    kind: j['kind'] as String,
    receivedAt: DateTime.parse(j['received_at'] as String),
    from: j['from'] as String? ?? '',
    fromContact: j['from_contact'] as bool? ?? false,
    title: j['title'] as String?,
    body: j['body'] as String?,
    url: j['url'] as String?,
    fileName: j['file_name'] as String?,
    fileMime: j['file_mime'] as String?,
    fileSize: j['file_size'] as int?,
    location: j['location'] as String?,
    status: j['status'] as String? ?? 'ok',
    error: j['error'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'received_at': receivedAt.toUtc().toIso8601String(),
    'from': from,
    'from_contact': fromContact,
    'title': title,
    'body': body,
    'url': url,
    'file_name': fileName,
    'file_mime': fileMime,
    'file_size': fileSize,
    'location': location,
    'status': status,
    'error': error,
  };

  final String id;
  final String kind;
  final DateTime receivedAt;

  /// Device name, or `@username` for a contact.
  final String from;
  final bool fromContact;
  final String? title;
  final String? body;
  final String? url;
  final String? fileName;
  final String? fileMime;
  final int? fileSize;

  /// Where a file was saved: a path on Windows, a content URI on Android.
  final String? location;

  /// `ok`, `failed` (will be retried) or `gone` (the file expired or was recalled).
  final String status;
  final String? error;
}

/// The history file. Also remembers handled item ids, so an item whose ack got lost
/// isn't handled twice. Background isolates write it too, so every change re-reads it.
class History {
  static const _maxEntries = 500;
  static const _maxHandled = 2000;
  static final _changes = StreamController<void>.broadcast();
  static Future<void> _queue = Future.value();

  /// Fires when this isolate changes the history.
  static Stream<void> get changes => _changes.stream;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'history.json'));
  }

  static Future<Map<String, dynamic>> _read() async {
    try {
      final file = await _file();
      if (await file.exists()) return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {}
    return {'entries': [], 'handled': []};
  }

  static Future<void> _write(Map<String, dynamic> data) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(file.path);
  }

  static Future<T> _locked<T>(Future<T> Function() fn) {
    final result = _queue.then((_) => fn());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  static Future<List<HistoryEntry>> entries() async {
    final data = await _read();
    return [for (final e in data['entries'] as List) HistoryEntry.fromJson(e as Map<String, dynamic>)];
  }

  static Future<bool> isHandled(String id) async => ((await _read())['handled'] as List).contains(id);

  /// Adds or replaces an entry. [handled] marks the item id as done.
  static Future<void> put(HistoryEntry entry, {required bool handled}) => _locked(() async {
    final data = await _read();
    final entries = (data['entries'] as List).where((e) => e['id'] != entry.id).toList()
      ..insert(0, entry.toJson());
    data['entries'] = entries.take(_maxEntries).toList();
    if (handled) {
      final ids = (data['handled'] as List)
        ..remove(entry.id)
        ..add(entry.id);
      data['handled'] = ids.length > _maxHandled ? ids.sublist(ids.length - _maxHandled) : ids;
    }
    await _write(data);
    _changes.add(null);
  });

  static Future<HistoryEntry?> get(String id) async {
    for (final e in await entries()) {
      if (e.id == id) return e;
    }
    return null;
  }

  static Future<void> remove(String id) => _locked(() async {
    final data = await _read();
    data['entries'] = (data['entries'] as List).where((e) => e['id'] != id).toList();
    await _write(data);
    _changes.add(null);
  });

  static Future<void> clear() => _locked(() async {
    final data = await _read();
    data['entries'] = [];
    await _write(data);
    _changes.add(null);
  });

  static Future<void> wipe() => _locked(() async {
    await _write({'entries': [], 'handled': []});
    _changes.add(null);
  });
}
