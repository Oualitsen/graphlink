import 'package:test/test.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';

/// One hoisted argument (`Thing.items(limit: Int)` → `$itemsLimit`) alongside one
/// declared argument (`getThing(id: ID!)`). After grouping, the hoisted arg is a
/// field of the synthesized `GetThingFieldArgs` input and the operation carries a
/// single synthetic object arg in its place.
///
/// This checks that `divideQueryDefinition` still expands that synthetic arg back
/// into the flat wire variables on each `DividedQuery` — asserting on the
/// structured `variables` / `argumentDeclarations` data, NOT on any serialized
/// query string.
void main() {
  const schema = '''
type Query {
  getThing(id: ID!): Thing
}

type Thing {
  id: ID!
  items(limit: Int): String
}
''';

  test('divided query expands the single hoisted arg into a flat wire variable',
      () {
    final g = GLParser(
      generateAllFieldsFragments: true,
      autoGenerateQueries: true,
    );
    g.parse(schema);

    final def = g.queries[const GLOperationKey('getThing', GLQueryType.query)]!;

    // Grouping happened: the operation keeps the declared $id and a single
    // synthetic object arg; the lone hoisted arg lives on the input.
    expect(def.arguments.map((a) => a.token), contains(r'$id'));
    expect(def.arguments.where((a) => a.hoistArgsInput != null).length, equals(1),
        reason: 'exactly one synthetic <Op>FieldArgs object arg');
    expect(g.inputs['GetThingFieldArgs']!.fields.map((f) => f.name.token),
        equals(['itemsLimit']));

    final divided = GLGraphqlSerializer(g).divideQueryDefinition(def, g);

    // One root element → one divided query.
    expect(divided.length, equals(1));
    final dq = divided.single;

    // The divided query declares the FLAT variables — declared $id AND the
    // expanded hoisted $itemsLimit — never the synthetic $fieldArgs container.
    expect(dq.variables, containsAll([r'$id', r'$itemsLimit']));
    expect(dq.variables, isNot(contains(r'$fieldArgs')));

    expect(dq.argumentDeclarations,
        containsAll([r'$id: ID!', r'$itemsLimit: Int']));
    expect(dq.argumentDeclarations.any((d) => d.contains('FieldArgs')), isFalse,
        reason: 'the synthetic <Op>FieldArgs object must not reach the wire');
  });
}
