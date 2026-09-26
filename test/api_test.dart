// End-to-end tests of the API client against a real server. Skipped unless
// VIA_TEST_SERVER is set, e.g. from ../Via:
//   VIA_DATA_DIR=/tmp/via VIA_PORT=8766 VIA_ADMIN_USERNAME=alice VIA_ADMIN_PASSWORD=password123 uv run via serve
//   VIA_TEST_SERVER=http://localhost:8766 VIA_TEST_USER=alice VIA_TEST_PASSWORD=password123 flutter test
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:via_app/src/api.dart';

void main() {
  final server = Platform.environment['VIA_TEST_SERVER'];
  final user = Platform.environment['VIA_TEST_USER'] ?? 'alice';
  final password = Platform.environment['VIA_TEST_PASSWORD'] ?? 'password123';

  group('ViaApi', skip: server == null ? 'VIA_TEST_SERVER not set' : null, () {
    late ViaApi phone;
    late ViaApi laptop;
    late String laptopId;

    setUpAll(() async {
      final anon = ViaApi(server!);
      final session = await anon.login(user, password);
      final (_, phoneToken) = await anon.registerDevice(session, 'test phone', 'android');
      final (laptopDevice, laptopToken) = await anon.registerDevice(session, 'test laptop', 'desktop');
      await anon.logout(session);
      phone = ViaApi(server, token: phoneToken);
      laptop = ViaApi(server, token: laptopToken);
      laptopId = laptopDevice.id;
    });

    test('info', () async {
      final info = await phone.info();
      expect(info.apiVersion, 1);
      expect(info.features, contains('sse'));
    });

    test('rename and list devices', () async {
      final me = await laptop.renameMe('renamed laptop');
      expect(me.name, 'renamed laptop');
      final devices = await phone.devices();
      expect(devices.where((d) => d.current).single.name, 'test phone');
      expect(devices.any((d) => d.id == laptopId), isTrue);
    });

    test('link, note and file arrive; file downloads resumably and verifies', () async {
      await phone.sendLink('https://example.com/a', [laptopId], title: 'Example');
      await phone.sendNote('remember the milk', [laptopId]);
      final tmp = await Directory.systemTemp.createTemp('via_test');
      final src = File('${tmp.path}/hello.txt')..writeAsStringSync('hello via ' * 1000);
      await phone.sendFile(src, 'hello.txt', 'text/plain', [laptopId]);

      final page = await laptop.inbox();
      final kinds = page.items.map((i) => i.kind).toList();
      expect(kinds, containsAll(['link', 'note', 'file']));
      final link = page.items.firstWhere((i) => i.kind == 'link');
      expect(link.url, 'https://example.com/a');
      expect(link.title, 'Example');
      final file = page.items.firstWhere((i) => i.kind == 'file');

      // Simulate an interrupted download: keep the first 100 bytes, then resume.
      final part = File('${tmp.path}/part');
      part.writeAsBytesSync(src.readAsBytesSync().sublist(0, 100));
      expect(await laptop.downloadFile(file.id, part), isTrue);
      expect(sha256.convert(part.readAsBytesSync()).toString(), file.file!.sha256);

      await laptop.ackMany(page.items.map((i) => i.id).toList());
      expect((await laptop.inbox()).items, isEmpty);
      await tmp.delete(recursive: true);
    });

    test('events stream starts with ready and signals pushes', () async {
      final client = http.Client();
      final response = await laptop.events(client);
      final lines = response.stream.transform(utf8.decoder).transform(const LineSplitter());
      final events = <String>[];
      final sub = lines.listen((l) {
        if (l.startsWith('event:')) events.add(l.substring(6).trim());
      });
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await phone.sendNote('ping', [laptopId]);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await sub.cancel();
      client.close();
      expect(events.first, 'ready');
      expect(events, contains('push'));
      final page = await laptop.inbox();
      await laptop.ackMany(page.items.map((i) => i.id).toList());
    });

    test('a bad token is unauthorized', () async {
      final bad = ViaApi(server!, token: 'via_d_nope');
      await expectLater(bad.inbox(), throwsA(isA<ApiException>().having((e) => e.isUnauthorized, '401', true)));
    });
  });
}
