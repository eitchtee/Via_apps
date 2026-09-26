import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:via_native/via_native.dart';

/// Platform actions for received items.
class LocalActions {
  static Future<void> copyText(String text) async {
    if (Platform.isAndroid) {
      await ViaNative.copyText(text);
    } else {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  static Future<bool> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Moves a downloaded [temp] file into the Downloads folder (Download/Via on Android)
  /// and returns where it ended up.
  static Future<String> saveDownload(File temp, String name, String mime) async {
    final safe = sanitizeFileName(name);
    if (Platform.isAndroid) {
      final uri = await ViaNative.saveToDownloads(temp.path, safe, mime);
      await temp.delete();
      return uri;
    }
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    await dir.create(recursive: true);
    final target = _unique(dir.path, safe);
    try {
      await temp.rename(target);
    } on FileSystemException {
      await temp.copy(target); // different volume
      await temp.delete();
    }
    return target;
  }

  static String _unique(String dir, String name) {
    final base = p.basenameWithoutExtension(name);
    final ext = p.extension(name);
    var candidate = p.join(dir, name);
    for (var i = 1; File(candidate).existsSync(); i++) {
      candidate = p.join(dir, '$base ($i)$ext');
    }
    return candidate;
  }

  static Future<bool> openFile(String location, String? mime) async {
    if (Platform.isAndroid) {
      return ViaNative.openFile(location, mime ?? '*/*');
    }
    if (!File(location).existsSync()) return false;
    return launchUrl(Uri.file(location));
  }

  /// Shows the file in Explorer (Windows only).
  static Future<void> showInFolder(String path) async {
    if (Platform.isWindows) await Process.start('explorer.exe', ['/select,', path]);
  }

  /// A file name that is safe on Windows and Android: no path separators, reserved
  /// characters or reserved names, and not too long.
  static String sanitizeFileName(String name) {
    var s = name.replaceAll(RegExp(r'[\x00-\x1f<>:"/\\|?*]'), '_').trim();
    s = s.replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
    if (s.isEmpty) s = 'file';
    final stem = p.basenameWithoutExtension(s).toUpperCase();
    if (RegExp(r'^(CON|PRN|AUX|NUL|COM\d|LPT\d)$').hasMatch(stem)) s = '_$s';
    if (s.length > 180) {
      final ext = p.extension(s);
      s = s.substring(0, 180 - (ext.length > 20 ? 0 : ext.length)) + (ext.length > 20 ? '' : ext);
    }
    return s;
  }
}
