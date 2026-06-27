import 'package:test/test.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_operation_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';

/// Probe: after the hoist pass, an auto-generated query's propagated
/// (nested-field) arguments are pulled out of the operation arg list and grouped
/// into a synthesized `<Op>FieldArgs` input, replaced by a single `fieldArgs`
/// object arg. This test PRINTS the resulting operation args, the synthesized
/// input, the full query string (`serializeQueryDefinition`) and the per-element
/// divided queries (`divideQueryDefinition`, the cache/partial path) so we can
/// see empirically whether the wire output is correct or needs fixing.
void main() {
  const schema = '''
type Query {
  getCompanies(start: Int, end: Int, filter: String): [Company]
}

type Company {
  id: ID!
  name: String
  employees(department: String, active: Boolean): [Employee]
  ceo: Employee
}

type Employee {
  id: ID!
  name: String
  salaryHistory(year: Int!, currency: String): [Salary]
  manager(includeArchived: Boolean): Employee
}

type Salary {
  amount: Float
  bonus(includeStock: Boolean): Float
}
''';

  test('hoisted args are grouped into <Op>FieldArgs; inspect query output', () {
    final g = GLParser(
      generateAllFieldsFragments: true,
      autoGenerateQueries: true,
    );
    g.parse(schema);

    final query = g.queries[GLOperationKey('getCompanies', GLQueryType.query)]!;

    // ignore: avoid_print
    print('=== operation args after hoist (${query.arguments.length}) ===');
    for (final a in query.arguments) {
      // ignore: avoid_print
      print('  ${a.token}: ${a.type.token}${a.type.nullable ? '' : '!'}'
          '  hoistInput=${a.hoistArgsInput?.declaredName ?? '-'}');
    }

    final input = g.inputs['GetCompaniesFieldArgs'];
    // ignore: avoid_print
    print('=== synthesized input GetCompaniesFieldArgs ===');
    if (input == null) {
      // ignore: avoid_print
      print('  <MISSING>');
    } else {
      for (final f in input.fields) {
        // ignore: avoid_print
        print('  ${f.name.token}: ${f.type.token}${f.type.nullable ? '' : '!'}'
            '${f.initialValue != null ? ' = ${f.initialValue}' : ''}');
      }
    }

    final serializer = GLGraphqlSerializer(g, false);

    // ignore: avoid_print
    print('=== serializeQueryDefinition ===');
    // ignore: avoid_print
    print(serializer.serializeQueryDefinition(query));

    // ignore: avoid_print
    print('=== divideQueryDefinition (cache/partial path) ===');
    for (final dq in serializer.divideQueryDefinition(query, g)) {
      // ignore: avoid_print
      print('  --- ${dq.operationName} ---');
      // ignore: avoid_print
      print('  variables: ${dq.variables}');
      // ignore: avoid_print
      print('  argumentDeclarations: ${dq.argumentDeclarations}');
      // ignore: avoid_print
      print('  query: ${dq.query}');
    }

    final dartSer = DartSerializer(g, importPrefix: '');
    final opSer = DartClientOperationSerializer(
        g, DartCodeGenUtils(), serializer, dartSer);
    // ignore: avoid_print
    print('=== dart generateVariables ===');
    // ignore: avoid_print
    print(opSer.generateVariables(query));
  });
}
