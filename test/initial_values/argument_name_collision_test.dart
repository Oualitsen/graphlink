import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';
import 'package:test/test.dart';

/// Bug hunt: when multiple fields on the same type have arguments with the
/// same name but different nullability/defaults, the null default from one
/// field's argument might leak to the other field's argument.
///
///   engine(name: String!)              ← non-null, no default
///   transmission(name: String = null)  ← nullable, default null
///
/// Auto-generated queries should produce distinct variables and each must
/// preserve its own nullability/default independently.

const _schema = '''
schema { query: Query }

type Query {
  car(id: ID!): Car
}

type Car {
  id: ID!
  engine(name: String!): Engine
  transmission(name: String = null): Transmission
}

type Engine {
  horsepower: Int!
}

type Transmission {
  gears: Int!
}
''';

GLParser _parser() {
  final g = GLParser(
    identityFields: ['id'],
    mode: CodeGenerationMode.client,
    autoGenerateQueries: true,
    generateAllFieldsFragments: true,
  );
  g.parse(_schema);
  return g;
}

void main() {
  test('non-null field argument does not get null default from sibling field', () {
    final g = _parser();
    final s = DartSerializer(g, importPrefix: '');
    final out =
        DartClientSerializer(g, s).getQueriesClass()?.toFileContent() ?? '';
    print('=== Dart client ===\n$out');

    // engine(name: String!) → required String engineName (non-null, no default)
    expect(out, contains('required String engineName'));
    expect(out, isNot(contains('String? engineName')));
    expect(out, isNot(contains('engineName = null')));

    // transmission(name: String = null) → String? transmissionName = null
    expect(out, contains('String? transmissionName = null'));

    // argumentDeclarations: engineName must be String!, transmissionName must
    // be String (nullable, not String!)
    expect(out, contains(r'"\$engineName: String!"'));
    expect(out, isNot(contains(r'"\$transmissionName: String!"')));
  });
}
