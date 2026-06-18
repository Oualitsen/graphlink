import 'dart:io';

import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:test/test.dart';

void main() {
  test("field arguments are propagated through the auto all-fields projection", () {
    final text =
        File("test/field_arguments/field_arguments.graphql").readAsStringSync();
    final g = GLParser(generateAllFieldsFragments: true, autoGenerateQueries: true);
    g.parse(text);

    final def = g.queries["getAuthor"]!;
    expect(def.arguments.map((a) => a.token), containsAll(["\$id", "\$lastArticlesLimit"]));

    final serializer = GLGraphqlSerializer(g, false);
    final query = serializer.serializeQueryDefinition(def);
    final fragments = def
        .fragments(g)
        .map((f) => serializer.serializeFragmentDefinitionBase(f))
        .join(' ');
    expect("$query $fragments", contains("lastArticles(limit: \$lastArticlesLimit)"));
  });

  test("field arguments written explicitly in a query are preserved without duplication", () {
    final text = File("test/field_arguments/field_arguments_explicit.graphql")
        .readAsStringSync();
    final g = GLParser();
    g.parse(text);

    final def = g.queries["getAuthor"]!;
    expect(def.arguments.map((a) => a.token).toList(), ["\$id", "\$limit"]);

    final serializer = GLGraphqlSerializer(g, false);
    final query = serializer.serializeQueryDefinition(def);
    expect(query, contains("lastArticles(limit: \$limit)"));
  });

  test("a field's arguments are not added when the field is not projected", () {
    final text = File("test/field_arguments/field_arguments_explicit.graphql")
        .readAsStringSync();
    final g = GLParser();
    g.parse(text);

    final def = g.queries["getAuthorWithNoArticles"]!;
    expect(def.arguments.map((a) => a.token).toList(), ["\$id"]);
    expect(def.arguments.map((a) => a.token), isNot(contains("\$limit")));

    final serializer = GLGraphqlSerializer(g, false);
    final query = serializer.serializeQueryDefinition(def);
    expect(query, isNot(contains("lastArticles")));
    expect(query, isNot(contains("limit")));
  });

  test("conflicting argument types for the same variable name throws", () {
    final text = File("test/field_arguments/field_arguments_collision.graphql")
        .readAsStringSync();
    final g = GLParser();

    expect(() => g.parse(text), throwsA(isA<ParseException>()));
  });
}
