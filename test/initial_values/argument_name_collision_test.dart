import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
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

    // engineName / transmissionName are propagated field args, now grouped into
    // the synthesized CarFieldArgs input. Each must keep its OWN nullability —
    // the `= null` default from transmission(name) must not leak onto the
    // non-null engine(name) field (which would be a compile error).
    final byName = {
      for (final f in g.inputs['CarFieldArgs']!.fields) f.name.token: f
    };

    // engine(name: String!) → non-null, no default
    expect(byName['engineName']!.type.nullable, isFalse);
    expect(byName['engineName']!.initialValue, isNull);
    // transmission(name: String = null) → nullable
    expect(byName['transmissionName']!.type.nullable, isTrue);

    // The query-string declaration must preserve each variable's own nullability.
    final query = GLGraphqlSerializer(g, false).serializeQueryDefinition(
        g.queries[GLOperationKey('car', GLQueryType.query)]!);
    expect(query, contains(r'$engineName: String!'));
    expect(query, isNot(contains(r'$transmissionName: String!')));
  });
}
