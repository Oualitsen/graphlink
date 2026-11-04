import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/grammar_factory.dart';
import 'package:test/test.dart';

GeneratorConfig _config({Object? suffix = _unset, Object? restNullable = _unset}) => GeneratorConfig.fromJson({
      'schemaPaths': ['schema.graphql'],
      'mode': 'client',
      'typeMappings': {'ID': 'String', 'String': 'String', 'Int': 'int', 'Float': 'double', 'Boolean': 'bool', 'Null': 'null'},
      'outputDir': 'out',
      if (suffix != _unset) 'restNullableSuffix': suffix,
      if (restNullable != _unset) 'restNullable': restNullable,
      'clientConfig': {'dart': <String, dynamic>{}},
    });

const _unset = Object();

void main() {
  group('restNullableSuffix', () {
    test('defaults to Rest', () {
      expect(_config().restNullableSuffix, 'Rest');
      expect(createGrammar(_config()).restNullableSuffix, 'Rest');
    });

    test('is read from the top-level config and reaches the parser', () {
      final config = _config(suffix: 'Raw');
      expect(config.restNullableSuffix, 'Raw');
      expect(createGrammar(config).restNullableSuffix, 'Raw');
    });

    test('must be a non-empty identifier fragment', () {
      for (final bad in ['', ' ', 'Re st', '1Rest', 'Rest!', 'Rest-X']) {
        expect(() => _config(suffix: bad), throwsA(isA<ArgumentError>()), reason: 'suffix "$bad"');
      }
    });

    test('must be a string', () {
      expect(() => _config(suffix: 3), throwsA(isA<ArgumentError>()));
    });
  });

  group('restNullable', () {
    test('defaults to false', () {
      expect(_config().restNullable, isFalse);
      expect(createGrammar(_config()).restNullable, isFalse);
    });

    test('is read from the top-level config and reaches the parser', () {
      final config = _config(restNullable: true);
      expect(config.restNullable, isTrue);
      expect(createGrammar(config).restNullable, isTrue);
    });

    test('must be a boolean', () {
      expect(() => _config(restNullable: 'yes'), throwsA(isA<ArgumentError>()));
    });
  });
}
