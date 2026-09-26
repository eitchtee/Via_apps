import 'package:flutter/services.dart';

/// Android-only helpers. All but [getSharedData] also work in background isolates.
class ViaNative {
  static const _channel = MethodChannel('via_native');

  static Future<void> copyText(String text) => _channel.invokeMethod('copyText', {'text': text});

  /// Copies the file at [path] to Download/Via and returns its content URI.
  static Future<String> saveToDownloads(String path, String name, String mime) async =>
      (await _channel.invokeMethod<String>('saveToDownloads', {'path': path, 'name': name, 'mime': mime}))!;

  /// The name the user gave this phone in system settings, or its model.
  static Future<String?> deviceName() => _channel.invokeMethod<String>('deviceName');

  static Future<bool> openFile(String uri, String mime) async =>
      await _channel.invokeMethod<bool>('openFile', {'uri': uri, 'mime': mime}) ?? false;

  /// What was shared to the current activity, or null if it wasn't started by a share.
  static Future<SharedData?> getSharedData() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('getSharedData');
    return raw == null ? null : SharedData._(raw);
  }
}

class SharedFile {
  SharedFile(this.path, this.name, this.mime, this.size);
  final String path;
  final String name;
  final String mime;
  final int size;
}

class SharedData {
  SharedData._(Map<String, dynamic> raw)
    : text = raw['text'] as String?,
      subject = raw['subject'] as String?,
      files = [
        for (final f in (raw['files'] as List? ?? const []))
          SharedFile(
            f['path'] as String,
            f['name'] as String,
            f['mime'] as String,
            (f['size'] as num).toInt(),
          ),
      ];

  final String? text;
  final String? subject;
  final List<SharedFile> files;
}
