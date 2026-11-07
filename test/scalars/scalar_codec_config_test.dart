import 'package:graphlink/src/config.dart';
import 'package:test/test.dart';

Map<String, dynamic> _config(Map<String, dynamic> typeMappings) => {
      'schemaPaths': ['schema.graphql'],
      'mode': 'client',
      'outputDir': 'out',
      'typeMappings': typeMappings,
    };

void main() {
  test('plain string mappings keep working and stay in typeMappings', () {
    final c = GeneratorConfig.fromJson(_config({'Long': 'int', 'ID': 'String'}));
    expect(c.typeMappings, {'Long': 'int', 'ID': 'String'});
    expect(c.scalarCodecs['Long']!.canDecode, isFalse);
  });

  test('an object mapping contributes its type to typeMappings', () {
    final c = GeneratorConfig.fromJson(_config({
      'DateTime': {'type': 'DateTime', 'fromJson': 'DateTime.parse({})', 'toJson': '{}.toIso8601String()'},
      'Long': 'int',
    }));
    expect(c.typeMappings, {'DateTime': 'DateTime', 'Long': 'int'});
    expect(c.scalarCodecs['DateTime']!.decode('v'), 'DateTime.parse(v)');
  });

  test('imports of an object mapping are kept', () {
    final c = GeneratorConfig.fromJson(_config({
      'Money': {'type': 'Decimal', 'import': 'package:decimal/decimal.dart'},
    }));
    expect(c.scalarCodecs['Money']!.imports, {'package:decimal/decimal.dart'});
  });

  test('an invalid mapping names the scalar in the error', () {
    expect(
      () => GeneratorConfig.fromJson(_config({
        'Money': {'fromJson': '{}', 'toJson': '{}'},
      })),
      throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('Money'))),
    );
  });

  test('a config without typeMappings has no codecs', () {
    final c = GeneratorConfig.fromJson({'schemaPaths': [], 'mode': 'client', 'outputDir': 'o'});
    expect(c.scalarCodecs, isEmpty);
    expect(c.typeMappings, isEmpty);
  });
}
