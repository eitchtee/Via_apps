import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:via_app/src/tasker.dart';

void main() {
  test('file paths: one path, a Tasker array or one per line', () {
    expect(Tasker.filePaths(''), isEmpty);
    expect(Tasker.filePaths('  /sdcard/a.pdf  '), ['/sdcard/a.pdf']);
    expect(Tasker.filePaths('/sdcard/a.pdf,/sdcard/b.jpg'), ['/sdcard/a.pdf', '/sdcard/b.jpg']);
    expect(Tasker.filePaths('/sdcard/a.pdf\n/sdcard/b.jpg\n'), ['/sdcard/a.pdf', '/sdcard/b.jpg']);
  });

  test('file paths: an existing file with a comma in its name stays whole', () {
    final dir = Directory.systemTemp.createTempSync('via');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File(p.join(dir.path, 'bills, 2026.pdf'))..writeAsStringSync('x');
    expect(Tasker.filePaths(file.path), [file.path]);
  });
}
