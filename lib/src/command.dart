/// A command sent as text, for apps like Tasker to act on instead of being shown or copied.
///
/// Syntax: `!:name`, optionally followed by params, each after a `::` separator:
/// `!:volume::40`, `!:say::Dinner's ready::pt-BR`. The name is a letter followed by one or more
/// letters, digits, `_` or `-`. A param can be wrapped in `"…"` or `'…'` to carry `::` or a
/// leading quote (`!:ping::"fe80::1"`); the wrap is only recognised when the closing quote is
/// right before the next `::` or the end, otherwise the quote is part of the text.
class ViaCommand {
  ViaCommand(this.name, [this.params = const []]);

  static const prefix = '!:';
  static const separator = '::';
  static final _name = RegExp(r'^[A-Za-z][A-Za-z0-9_-]+$');

  final String name;
  final List<String> params;

  static bool isValidName(String name) => _name.hasMatch(name);

  /// The command in [text], or null when it's plain text.
  static ViaCommand? parse(String text) {
    if (!text.startsWith(prefix)) return null;
    final s = text.substring(prefix.length);
    final nameEnd = s.indexOf(separator);
    final name = nameEnd < 0 ? s : s.substring(0, nameEnd);
    if (!_name.hasMatch(name)) return null;
    if (nameEnd < 0) return ViaCommand(name);

    final params = <String>[];
    var pos = nameEnd + separator.length;
    while (true) {
      final end = _quotedEnd(s, pos);
      if (end != null) {
        params.add(s.substring(pos + 1, end));
        pos = end + 1;
      } else {
        final next = s.indexOf(separator, pos);
        params.add(s.substring(pos, next < 0 ? s.length : next));
        pos = next < 0 ? s.length : next;
      }
      if (pos >= s.length) break;
      pos += separator.length;
    }
    return ViaCommand(name, params);
  }

  /// When a quoted param starts at [pos], the index of its closing quote.
  static int? _quotedEnd(String s, int pos) {
    if (pos >= s.length) return null;
    final quote = s[pos];
    if (quote != '"' && quote != "'") return null;
    for (var i = s.indexOf(quote, pos + 1); i >= 0; i = s.indexOf(quote, i + 1)) {
      if (i + 1 == s.length || s.startsWith(separator, i + 1)) return i;
    }
    return null;
  }

  /// The command as text, quoting the params that need it. Throws [ArgumentError] when the
  /// name is invalid or a param contains both `"::` and `'::`.
  String encode() {
    if (!isValidName(name)) throw ArgumentError.value(name, 'name', 'Not a valid command name');
    return [prefix + name, ...params.map(_encodeParam)].join(separator);
  }

  static String _encodeParam(String p) {
    final needsQuotes =
        p.contains(separator) || p.startsWith('"') || p.startsWith("'") || p.endsWith(':');
    if (!needsQuotes) return p;
    for (final quote in ['"', "'"]) {
      if (!p.contains('$quote$separator')) return '$quote$p$quote';
    }
    throw ArgumentError.value(p, 'param', 'Cannot contain both "$separator and \'$separator');
  }
}
