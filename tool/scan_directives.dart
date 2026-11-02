import 'dart:io';

import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_directive_validation_extension.dart';

Iterable<MapEntry<String, String>> sources() sync* {
  for (final root in ['test', 'examples', 'integration_tests', 'server_integration_tests']) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      final p = f.path;
      if (p.contains('/generated/') || p.contains('node_modules') || p.contains('.dart_tool') || p.contains('/build/')) continue;
      if (p.endsWith('.graphql') || p.endsWith('.gql')) {
        yield MapEntry(p, f.readAsStringSync());
      } else if (p.endsWith('.dart') && p.startsWith('test/')) {
        final text = f.readAsStringSync();
        final re = RegExp("'''([\\s\\S]*?)'''|\"\"\"([\\s\\S]*?)\"\"\"");
        var i = 0;
        for (final m in re.allMatches(text)) {
          final body = m.group(1) ?? m.group(2)!;
          if (body.contains('type ') || body.contains('directive ')) yield MapEntry('$p#${i++}', body);
        }
      }
    }
  }
}

void main() {
  final byMessage = <String, List<String>>{};
  var ok = 0, skipped = 0, total = 0;
  for (final s in sources()) {
    total++;
    final parser = GLParser();
    try {
      parser.parse(s.value, validate: false);
    } catch (_) {
      skipped++;
      continue;
    }
    try {
      parser.validateDirectives();
      ok++;
    } catch (e) {
      final message = e.toString().split('\n').first.replaceAll(RegExp(r'\(.*?\)\s*$'), '');
      byMessage.putIfAbsent(message.replaceAll(RegExp(r'line \d+.*'), ''), () => []).add(s.key);
    }
  }
  stdout.writeln('total=$total ok=$ok skipped=$skipped failing=${total - ok - skipped}');
  final sorted = byMessage.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
  for (final e in sorted) {
    stdout.writeln('${e.value.length}x ${e.key}\n    e.g. ${e.value.take(2).join(', ')}');
  }
}
