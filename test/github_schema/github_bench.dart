import 'dart:io';

import 'package:graphlink/src/model/new_parser/gl_parser.dart';

/// Standalone parse benchmark for the GitHub schema.
///
/// Run: fvm dart run test/github_schema/github_bench.dart [iterations]
///
/// Realistic config: generateAllFieldsFragments + autoGenerateQueries (default
/// validate:true) — the way the tool is generally used. Measures parse time and
/// retained RSS so we have a baseline before/after the model-layer memory work.
void main(List<String> args) {
  final iterations = args.isNotEmpty ? int.parse(args.first) : 2;
  final schema =
      File('test/github_schema/schema.docs.graphql').readAsStringSync();
  print('schema size: ${schema.length} chars, '
      '${schema.split('\n').length} lines');
  print('iterations: $iterations\n');

  final beforeAny = ProcessInfo.currentRss / (1024 * 1024);

  for (var i = 0; i < iterations; i++) {
    final parser = GLParser(
      generateAllFieldsFragments: true,
      autoGenerateQueries: true,
      defaultAlias: 'data',
    );

    final sw = Stopwatch()..start();
    parser.parse(schema);
    sw.stop();

    final rssMb = ProcessInfo.currentRss / (1024 * 1024);
    print('iter ${i + 1}: parse=${sw.elapsedMilliseconds}ms  '
        'rss=${rssMb.toStringAsFixed(1)}MB  '
        '(types=${parser.types.length} inputs=${parser.inputs.length} '
        'enums=${parser.enums.length} interfaces=${parser.interfaces.length} '
        'fragments=${parser.fragments.length} queries=${parser.queries.length})');
  }

  print('\nRSS before any parse: ${beforeAny.toStringAsFixed(1)}MB');
  print('peak RSS: ${(ProcessInfo.maxRss / (1024 * 1024)).toStringAsFixed(1)}MB');
}
