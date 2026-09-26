import 'dart:io';

import 'package:path/path.dart' as p;

import 'config.dart';
import 'models.dart';

enum SendKind { link, file, text }

class OutgoingFile {
  OutgoingFile(this.path, this.name, this.size, {String? mime}) : mime = mime ?? mimeFor(name);
  final String path;
  final String name;
  final int size;
  final String mime;
}

/// Loads send targets and sends.
class Sender {
  /// Your other devices, then accepted contacts.
  static Future<List<Target>> targets(Account account) async {
    final api = account.api();
    try {
      final devices = await api.devices();
      final contacts = await api.contacts().catchError((_) => <Contact>[]);
      return [
        for (final d in devices)
          if (!d.current && d.id != account.deviceId) Target.device(d),
        for (final c in contacts) Target.contact(c),
      ];
    } finally {
      api.close();
    }
  }

  static Future<List<String>> lastTargets() async =>
      (await Prefs.getString('last_targets'))?.split(',').where((s) => s.isNotEmpty).toList() ?? [];

  static Future<void> rememberTargets(List<String> ids) => Prefs.setString('last_targets', ids.join(','));

  /// Sends one item. For files, [onProgress] reports the overall fraction (0..1).
  static Future<void> send(
    Account account,
    SendKind kind,
    List<String> to, {
    String? text,
    String? title,
    List<OutgoingFile> files = const [],
    void Function(double progress, int index)? onProgress,
  }) async {
    final api = account.api();
    try {
      switch (kind) {
        case SendKind.link:
          await api.sendLink(normalizeLink(text!), to, title: title);
        case SendKind.text:
          await api.sendNote(text!, to, title: title);
        case SendKind.file:
          final total = files.fold<int>(0, (sum, f) => sum + f.size);
          var done = 0;
          for (final (i, f) in files.indexed) {
            await api.sendFile(
              File(f.path),
              f.name,
              f.mime,
              to,
              onProgress: (sent, _) => onProgress?.call(total == 0 ? 1 : (done + sent) / total, i),
            );
            done += f.size;
          }
      }
    } finally {
      api.close();
    }
  }
}

/// A single http(s) URL, possibly surrounded by whitespace, counts as a link.
bool looksLikeLink(String text) {
  final t = text.trim();
  if (t.contains(RegExp(r'\s'))) return false;
  final uri = Uri.tryParse(t);
  return uri != null && (uri.isScheme('http') || uri.isScheme('https')) && uri.host.isNotEmpty;
}

/// Finds the URL in shared text like "Some title https://example.com".
String? extractLink(String text) {
  if (looksLikeLink(text)) return text.trim();
  final matches = RegExp(r'https?://\S+').allMatches(text).toList();
  if (matches.length != 1) return null;
  final rest = text.replaceFirst(matches.single.group(0)!, '').trim();
  // Only when the rest is short, like a page title; otherwise it's text with a link in it.
  return rest.length <= 200 && !rest.contains('\n\n') ? matches.single.group(0) : null;
}

String normalizeLink(String input) {
  final t = input.trim();
  return t.contains('://') ? t : 'https://$t';
}

String mimeFor(String name) => switch (p.extension(name).toLowerCase()) {
  '.jpg' || '.jpeg' => 'image/jpeg',
  '.png' => 'image/png',
  '.gif' => 'image/gif',
  '.webp' => 'image/webp',
  '.heic' => 'image/heic',
  '.svg' => 'image/svg+xml',
  '.mp4' => 'video/mp4',
  '.mov' => 'video/quicktime',
  '.webm' => 'video/webm',
  '.mkv' => 'video/x-matroska',
  '.mp3' => 'audio/mpeg',
  '.m4a' => 'audio/mp4',
  '.ogg' => 'audio/ogg',
  '.wav' => 'audio/wav',
  '.pdf' => 'application/pdf',
  '.zip' => 'application/zip',
  '.txt' => 'text/plain',
  '.csv' => 'text/csv',
  '.json' => 'application/json',
  '.apk' => 'application/vnd.android.package-archive',
  '.doc' => 'application/msword',
  '.docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  '.xls' => 'application/vnd.ms-excel',
  '.xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  '.ppt' => 'application/vnd.ms-powerpoint',
  '.pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  _ => 'application/octet-stream',
};

String formatSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return unit == 0 ? '$bytes B' : '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${units[unit]}';
}
