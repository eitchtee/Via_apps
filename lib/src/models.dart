class ServerInfo {
  ServerInfo({required this.apiVersion, required this.version, required this.features, required this.limits});

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    final features = json['features'];
    return ServerInfo(
      apiVersion: (json['api_version'] as num?)?.toInt() ?? 0,
      version: '${json['version'] ?? ''}',
      features: features is Map
          ? {
              for (final e in features.entries)
                if (e.value == true) '${e.key}',
            }
          : features is List
          ? {for (final f in features) '$f'}
          : <String>{},
      limits: Map<String, dynamic>.from(json['limits'] as Map? ?? const {}),
    );
  }

  final int apiVersion;
  final String version;
  final Set<String> features;
  final Map<String, dynamic> limits;

  int? get maxFileSize => (limits['max_file_size'] as num?)?.toInt();
  int? get maxTextLength => (limits['max_text_length'] as num?)?.toInt();
}

class Device {
  Device({required this.id, required this.name, required this.type, this.current = false});

  factory Device.fromJson(Map<String, dynamic> json) => Device(
    id: json['id'] as String,
    name: json['name'] as String,
    type: json['type'] as String? ?? 'other',
    current: json['current'] as bool? ?? false,
  );

  final String id;
  final String name;
  final String type;
  final bool current;
}

class Contact {
  Contact({required this.id, required this.username});

  factory Contact.fromJson(Map<String, dynamic> json) =>
      Contact(id: json['id'] as String, username: json['username'] as String);

  final String id;
  final String username;
}

/// Something that can be sent to: one of your devices or a contact (`@username`).
class Target {
  Target.device(Device d) : id = d.id, label = d.name, type = d.type, isContact = false;
  Target.contact(Contact c)
    : id = '@${c.username}',
      label = '@${c.username}',
      type = 'contact',
      isContact = true;

  final String id;
  final String label;
  final String type;
  final bool isContact;
}

class InboxFile {
  InboxFile({
    required this.name,
    required this.mime,
    required this.size,
    required this.sha256,
    required this.available,
  });

  factory InboxFile.fromJson(Map<String, dynamic> json) => InboxFile(
    name: json['name'] as String? ?? 'file',
    mime: json['mime'] as String? ?? 'application/octet-stream',
    size: (json['size'] as num?)?.toInt() ?? 0,
    sha256: json['sha256'] as String? ?? '',
    available: json['available'] as bool? ?? true,
  );

  final String name;
  final String mime;
  final int size;
  final String sha256;
  final bool available;
}

class InboxItem {
  InboxItem({
    required this.id,
    required this.kind,
    required this.createdAt,
    this.sourceDeviceId,
    this.sender,
    this.title,
    this.body,
    this.url,
    this.file,
  });

  factory InboxItem.fromJson(Map<String, dynamic> json) => InboxItem(
    id: json['id'] as String,
    kind: json['kind'] as String,
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    sourceDeviceId: json['source_device_id'] as String?,
    sender: json['sender'] as String?,
    title: json['title'] as String?,
    body: json['body'] as String?,
    url: json['url'] as String?,
    file: json['file'] == null ? null : InboxFile.fromJson(json['file'] as Map<String, dynamic>),
  );

  final String id;
  final String kind;
  final DateTime createdAt;
  final String? sourceDeviceId;
  final String? sender;
  final String? title;
  final String? body;
  final String? url;
  final InboxFile? file;
}

class InboxPage {
  InboxPage(this.items, this.cursor);

  factory InboxPage.fromJson(Map<String, dynamic> json) => InboxPage([
    for (final i in json['items'] as List) InboxItem.fromJson(i as Map<String, dynamic>),
  ], json['cursor'] as String?);

  final List<InboxItem> items;
  final String? cursor;
}
