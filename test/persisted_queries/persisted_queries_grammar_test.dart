import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/grammar_factory.dart';
import 'package:test/test.dart';

GeneratorConfig _config(Map<String, dynamic> dart) => GeneratorConfig.fromJson({
      'schemaPaths': ['schema.graphql'],
      'mode': 'client',
      'typeMappings': {'ID': 'String', 'String': 'String', 'Int': 'int', 'Float': 'double', 'Boolean': 'bool', 'Null': 'null'},
      'outputDir': 'out',
      'clientConfig': {'dart': dart},
    });

void main() {
  test('the parser sees persisted queries off by default', () {
    final parser = createGrammar(_config({}));
    expect(parser.persistedQueries, isFalse);
    expect(parser.persistedQueriesUseGet, isFalse);
  });

  test('the parser sees apq and GET when configured', () {
    final parser = createGrammar(_config({'persistedQueries': 'apq', 'persistedQueriesUseGet': true}));
    expect(parser.persistedQueries, isTrue);
    expect(parser.persistedQueriesUseGet, isTrue);
  });
}
