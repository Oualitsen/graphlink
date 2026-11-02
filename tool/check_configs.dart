// Parses (and validates) the schemas of every glink config under the given roots without generating anything.
import 'dart:convert';
import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/gl_grammar_io.dart' as grammar_io;
import 'package:graphlink/src/grammar_factory.dart';
import 'package:yaml/yaml.dart';

Future<void> main(List<String> roots) async {
  final origin = Directory.current;
  var ok = 0;
  final failures = <String>[];
  for (final root in roots) {
    final configs = Directory(root).absolute
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => !f.path.contains('node_modules') && !f.path.contains('.dart_tool'))
        .where((f) => RegExp(r'/(config\.json|glink\.(json|ya?ml))$').hasMatch(f.path));
    for (final file in configs) {
      Directory.current = file.parent;
      try {
        final raw = file.readAsStringSync();
        final json = file.path.endsWith('.json')
            ? jsonDecode(raw) as Map<String, dynamic>
            : (loadYaml(raw) as YamlMap).toMap();
        final config = GeneratorConfig.fromJson(json);
        final paths = [for (final p in config.schemaPaths) ...Glob(p).listSync().whereType<File>().map((f) => f.path)];
        final grammar = createGrammar(config);
        final files = await Future.wait(paths.map(grammar_io.readLogicalFile));
        grammar_io.parseFiles(grammar, files, extraGql: buildExtraGql(grammar, config));
        ok++;
      } catch (e) {
        failures.add('${file.path.replaceFirst(origin.path, '')}: ${e.toString().split('\n').first}');
      }
      Directory.current = origin;
    }
  }
  stdout.writeln('ok=$ok failing=${failures.length}');
  failures.forEach(stdout.writeln);
}

extension on YamlMap {
  Map<String, dynamic> toMap() => jsonDecode(jsonEncode(this)) as Map<String, dynamic>;
}
