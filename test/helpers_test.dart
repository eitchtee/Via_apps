import 'package:flutter_test/flutter_test.dart';
import 'package:via_app/src/api.dart';
import 'package:via_app/src/platform.dart';
import 'package:via_app/src/sender.dart';

void main() {
  test('normalizeServerUrl', () {
    expect(normalizeServerUrl(' via.example.com/ '), 'https://via.example.com');
    expect(normalizeServerUrl('http://10.0.0.2:8080//'), 'http://10.0.0.2:8080');
  });

  test('shared text: a lone URL or "title + URL" is a link, anything else is text', () {
    expect(extractLink('https://example.com/x?y=1'), 'https://example.com/x?y=1');
    expect(extractLink('  https://example.com  '), 'https://example.com');
    expect(extractLink('Cool article https://example.com/a'), 'https://example.com/a');
    expect(extractLink('just some text'), isNull);
    expect(extractLink('two https://a.com and https://b.com'), isNull);
    expect(extractLink('example.com'), isNull);
  });

  test('sanitizeFileName', () {
    expect(LocalActions.sanitizeFileName('../../etc/passwd'), '_.._etc_passwd');
    expect(LocalActions.sanitizeFileName('a<b>:c.txt'), 'a_b__c.txt');
    expect(LocalActions.sanitizeFileName('CON.txt'), '_CON.txt');
    expect(LocalActions.sanitizeFileName('...'), 'file');
    expect(LocalActions.sanitizeFileName('report. '), 'report');
    expect(LocalActions.sanitizeFileName('${'x' * 300}.pdf').length, 180);
  });

  test('formatSize', () {
    expect(formatSize(512), '512 B');
    expect(formatSize(1536), '1.5 KB');
    expect(formatSize(300 * 1024 * 1024), '300 MB');
  });
}
