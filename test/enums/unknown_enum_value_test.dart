import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

const schema = '''
enum Gender { male female }
type Query { gender: Gender }
''';

GLParser parse({required bool tolerant, String source = schema}) =>
    GLParser(tolerantEnums: tolerant)..parse(source);

void main() {
  test('absent when tolerantEnums is off', () {
    final gender = parse(tolerant: false).enums['Gender']!;
    expect(gender.unknownValue, isNull);
    expect(gender.allValues.map((v) => v.codeName), ['male', 'female']);
  });

  test('present but outside values when tolerantEnums is on', () {
    final gender = parse(tolerant: true).enums['Gender']!;
    expect(gender.values.map((v) => v.codeName), ['male', 'female']);
    expect(gender.unknownValue!.codeName, unknownEnumValueName);
    expect(gender.allValues.map((v) => v.codeName),
        ['male', 'female', unknownEnumValueName]);
  });

  test('avoids a declared value with the same name', () {
    final gender = parse(
      tolerant: true,
      source: 'enum Gender { male $unknownEnumValueName } type Query { g: Gender }',
    ).enums['Gender']!;
    expect(gender.unknownValue!.codeName, '${unknownEnumValueName}2');
  });

  test('keeps counting while suffixed names are taken too', () {
    final gender = parse(
      tolerant: true,
      source:
          'enum Gender { male ${unknownEnumValueName} ${unknownEnumValueName}2 } type Query { g: Gender }',
    ).enums['Gender']!;
    expect(gender.unknownValue!.codeName, '${unknownEnumValueName}3');
  });

  test('generator-internal enums never get a fallback', () {
    final g = parse(tolerant: true);
    expect(g.enums['GraphLinkAckStatus']!.unknownValue, isNull);
  });
}
