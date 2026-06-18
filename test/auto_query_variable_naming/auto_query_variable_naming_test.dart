import 'dart:io';

import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:test/test.dart';

void main() {
  late GLParser parser;

  setUp(() {
    final schema = File('test/auto_query_variable_naming/schema.graphql')
        .readAsStringSync();
    parser = GLParser(
      generateAllFieldsFragments: true,
      autoGenerateQueries: true,
      defaultAlias: 'data',
    );
    parser.parse(schema);
  });

  test('auto-query generation does not throw for same-field-name with different input types', () {
    expect(parser.queries.containsKey('enterprise'), true);
  });

  test('input type args use the type name as variable (globally unique)', () {
    final def = parser.queries['enterprise']!;
    final varTokens = def.arguments.map((a) => a.token).toSet();

    // Each input type becomes $camelCaseTypeName
    expect(varTokens, contains('\$enterpriseTeamOrganizationOrder'));
    expect(varTokens, contains('\$auditLogOrder'));
    expect(varTokens, contains('\$repositoryOrder'));
    expect(varTokens, contains('\$teamRepositoryOrder'));
  });

  test('scalar args use field+arg name as variable', () {
    final def = parser.queries['enterprise']!;
    final varTokens = def.arguments.map((a) => a.token).toSet();

    // Int arg on Organization.members → $membersLimit
    expect(varTokens, contains('\$membersLimit'));
  });

  test('no duplicate or conflicting variable declarations', () {
    final def = parser.queries['enterprise']!;
    final tokens = def.arguments.map((a) => a.token).toList();
    // All variable names must be unique
    expect(tokens.toSet().length, equals(tokens.length));
  });

  test('generated query string references all declared variables', () {
    final def = parser.queries['enterprise']!;
    final serializer = GLGraphqlSerializer(parser, false);
    final query = serializer.serializeQueryDefinition(def);

    expect(query, contains('\$enterpriseTeamOrganizationOrder'));
    expect(query, contains('\$auditLogOrder'));
    expect(query, contains('\$repositoryOrder'));
    expect(query, contains('\$teamRepositoryOrder'));
    expect(query, contains('\$membersLimit'));
  });

  test('generated Dart client exposes all variables as method parameters', () {
    final serializer = DartClientSerializer(
      parser,
      DartSerializer(parser, importPrefix: '', generateJsonMethods: true),
      generateAdapters: true,
    );
    final client = serializer.generateClient().toFileContent();

    expect(client, contains('EnterpriseTeamOrganizationOrder? enterpriseTeamOrganizationOrder'));
    expect(client, contains('AuditLogOrder? auditLogOrder'));
    expect(client, contains('RepositoryOrder? repositoryOrder'));
    expect(client, contains('TeamRepositoryOrder? teamRepositoryOrder'));
    expect(client, contains('int? membersLimit'));
  });
}
