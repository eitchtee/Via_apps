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

  /// Asks Tasker to query the event plugin whose edit activity is [activity], passing [data]
  /// (strings and string lists) through to its query receiver.
  static Future<void> requestTaskerQuery(String activity, Map<String, Object> data) =>
      _channel.invokeMethod('requestTaskerQuery', {'activity': activity, 'data': data});

  /// Whether Via may read any file in shared storage, which sending a file by path (from
  /// Tasker) needs: "All files access" on Android 11+, storage permission on Android 10.
  static Future<bool> hasAllFilesAccess() async =>
      await _channel.invokeMethod<bool>('hasAllFilesAccess') ?? false;

  /// Opens the system screen to grant [hasAllFilesAccess] (or asks for it on Android 10).
  static Future<void> requestAllFilesAccess() => _channel.invokeMethod('requestAllFilesAccess');

  /// Shows [targets] in the system share sheet as direct targets, most relevant first,
  /// replacing the previous ones. Does nothing before Android 10.
  static Future<void> setShareTargets(List<ShareTarget> targets) => _channel.invokeMethod('setShareTargets', {
    'targets': [
      for (final t in targets) {'id': t.id, 'label': t.label, 'type': t.type},
    ],
  });

  /// Tells the system these share targets were just used, so it ranks them higher.
  static Future<void> reportShareTargetUsed(List<String> ids) =>
      _channel.invokeMethod('reportShareTargetUsed', {'ids': ids});

  /// What was shared to the current activity, or null if it wasn't started by a share.
  static Future<SharedData?> getSharedData() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('getSharedData');
    return raw == null ? null : SharedData._(raw);
  }
}

class ShareTarget {
  ShareTarget(this.id, this.label, this.type);
  final String id;
  final String label;

  /// Picks the icon: android, ios, desktop, browser, cli, contact or anything else.
  final String type;
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
      target = raw['target'] as String?,
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

  /// The [ShareTarget.id] picked in the share sheet, if a direct target was used.
  final String? target;
}
