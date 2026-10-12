import 'package:flutter_test/flutter_test.dart';
import 'package:via_app/src/command.dart';

void main() {
  List<String>? params(String text) => ViaCommand.parse(text)?.params;

  test('a command is "!:" + name, with optional "::"-separated params', () {
    expect(ViaCommand.parse('!:lights_on')?.name, 'lights_on');
    expect(params('!:lights_on'), isEmpty);
    expect(ViaCommand.parse('!:volume::40')?.name, 'volume');
    expect(params('!:volume::40'), ['40']);
    expect(params("!:say::Dinner's ready::pt-BR"), ["Dinner's ready", 'pt-BR']);
    expect(params('!:set::::x'), ['', 'x']);
    expect(params('!:set::'), ['']);
    expect(params('!:say::line 1\nline 2'), ['line 1\nline 2']);
  });

  test('anything else is plain text', () {
    for (final text in [
      'hello',
      ' !:lights_on',
      '!:',
      '!:)',
      '!:D',
      '!:P::x',
      '!:1',
      r'!:$',
      '!:s/foo/bar/',
      '!: lights_on',
      '!:lights on',
      '!:9lives',
      'lights_on',
    ]) {
      expect(ViaCommand.parse(text), isNull, reason: text);
    }
  });

  test('a param wrapped in matching quotes is unwrapped', () {
    expect(params('!:cmd::":)"::\':):\''), [':)', ':):']);
    expect(params('!:ping::"fe80::1"'), ['fe80::1']);
    expect(params('!:say::""hi""'), ['"hi"']);
    expect(params('!:say::""'), ['']);
    expect(params('!:say::\'he said "a"::b\''), ['he said "a"::b']);
    expect(params('!:say::"a"::b"'), ['a', 'b"']);
  });

  test('half a quote is taken literally', () {
    expect(params("!:say::'tis late"), ["'tis late"]);
    expect(params('!:say::"abc::def'), ['"abc', 'def']);
    expect(params('!:say::"a"b::c'), ['"a"b', 'c']);
    expect(params('!:say::"'), ['"']);
    expect(params('!:say::x"::"y'), ['x"', '"y']);
  });

  test('encode quotes params only when needed, and round-trips', () {
    expect(ViaCommand('lights_on').encode(), '!:lights_on');
    expect(ViaCommand('volume', ['40']).encode(), '!:volume::40');
    expect(ViaCommand('ping', ['fe80::1']).encode(), '!:ping::"fe80::1"');
    expect(ViaCommand('say', ['"hi"']).encode(), '!:say::""hi""');
    expect(ViaCommand('open', ['C:', 'next']).encode(), '!:open::"C:"::next');

    for (final p in [
      <String>[],
      [''],
      ['', ''],
      ['fe80::1', 'x'],
      ['"hi"', "'tis", 'C:', ':x', 'a"', "b'"],
      ['he said "a"::b'],
      ["it's 'a'::b"],
      ['line 1\nline 2', '::', '"', "'", ':'],
    ]) {
      final encoded = ViaCommand('cmd', p).encode();
      expect(ViaCommand.parse(encoded)?.params, p, reason: encoded);
    }
  });

  test('encode rejects what the syntax cannot carry', () {
    expect(() => ViaCommand('lights on').encode(), throwsArgumentError);
    expect(() => ViaCommand('x').encode(), throwsArgumentError);
    expect(() => ViaCommand('cmd', ['"a"::\'b\'::c']).encode(), throwsArgumentError);
  });
}
