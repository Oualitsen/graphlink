/// Value of a GraphQL string literal: `"..."` with its escapes resolved, or a
/// `"""..."""` block string with the common indentation removed. Anything else
/// (an enum value, a number) is returned as it is.
String decodeGraphqlString(String raw) {
  if (raw.length >= 6 && raw.startsWith('"""') && raw.endsWith('"""')) {
    return _blockStringValue(raw.substring(3, raw.length - 3).replaceAll(r'\"""', '"""'));
  }
  if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
    return _unescape(raw.substring(1, raw.length - 1));
  }
  return raw;
}

String _unescape(String body) {
  const simple = {'"': '"', '\\': '\\', '/': '/', 'b': '\b', 'f': '\f', 'n': '\n', 'r': '\r', 't': '\t'};
  final out = StringBuffer();
  for (var i = 0; i < body.length; i++) {
    final c = body[i];
    if (c != '\\' || i + 1 >= body.length) {
      out.write(c);
      continue;
    }
    final next = body[++i];
    if (next == 'u') {
      final braced = i + 1 < body.length && body[i + 1] == '{';
      final end = braced ? body.indexOf('}', i) : i + 4;
      final digits = braced ? body.substring(i + 2, end) : body.substring(i + 1, i + 5);
      out.writeCharCode(int.parse(digits, radix: 16));
      i = braced ? end : i + 4;
    } else {
      out.write(simple[next] ?? '\\$next');
    }
  }
  return out.toString();
}

String _blockStringValue(String body) {
  final lines = body.split(RegExp(r'\r\n|\n|\r'));
  var common = -1;
  for (final line in lines.skip(1)) {
    final indent = line.length - line.trimLeft().length;
    if (indent == line.length) continue;
    if (common < 0 || indent < common) common = indent;
  }
  final dedented = [
    for (var i = 0; i < lines.length; i++)
      if (i == 0 || common <= 0) lines[i] else (lines[i].length >= common ? lines[i].substring(common) : ''),
  ];
  while (dedented.isNotEmpty && dedented.first.trim().isEmpty) {
    dedented.removeAt(0);
  }
  while (dedented.isNotEmpty && dedented.last.trim().isEmpty) {
    dedented.removeLast();
  }
  return dedented.join('\n');
}

/// Escapes [value] for the inside of a string literal delimited by [quote].
/// [dollar] also escapes `$` (languages that interpolate), and [control] spells
/// the control characters other than `\n`, `\r` and `\t`.
String escapeStringBody(
  String value, {
  required String quote,
  bool dollar = false,
  String Function(int codeUnit)? control,
}) {
  final out = StringBuffer();
  for (final unit in value.codeUnits) {
    final c = String.fromCharCode(unit);
    if (c == '\\' || c == quote || (dollar && c == r'$')) {
      out.write('\\$c');
    } else if (c == '\n') {
      out.write(r'\n');
    } else if (c == '\r') {
      out.write(r'\r');
    } else if (c == '\t') {
      out.write(r'\t');
    } else if ((unit < 0x20 || unit == 0x7f) && control != null) {
      out.write(control(unit));
    } else {
      out.write(c);
    }
  }
  return out.toString();
}
