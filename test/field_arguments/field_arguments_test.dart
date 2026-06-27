import 'dart:io';

import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/gl_queries.dart';

void main() {
  test("field arguments are propagated through the auto all-fields projection", () {
    final text =
        File("test/field_arguments/field_arguments.graphql").readAsStringSync();
    final g = GLParser(generateAllFieldsFragments: true, autoGenerateQueries: true);
    g.parse(text);

    final def = g.queries[GLOperationKey("getAuthor", GLQueryType.query)]!;

    // `id` is the operation's own declared arg → stays a direct argument.
    expect(def.arguments.map((a) => a.token), contains("\$id"));
    // `lastArticlesLimit` is a propagated field arg → grouped into the
    // synthesized GetAuthorFieldArgs input, no longer a flat operation arg.
    expect(g.inputs['GetAuthorFieldArgs']!.fields.map((f) => f.name.token),
        contains("lastArticlesLimit"));

    final serializer = GLGraphqlSerializer(g, false);
    final query = serializer.serializeQueryDefinition(def);
    final fragments = def
        .fragments(g)
        .map((f) => serializer.serializeFragmentDefinitionBase(f))
        .join(' ');
    // the operation still DECLARES the propagated variable (expanded from the
    // synthesized input) and the fragment still references it.
    expect(query, contains("\$lastArticlesLimit"));
    expect("$query $fragments", contains("lastArticles(limit: \$lastArticlesLimit)"));
  });

  test("field arguments written explicitly in a query are preserved without duplication", () {
    final text = File("test/field_arguments/field_arguments_explicit.graphql")
        .readAsStringSync();
    final g = GLParser();
    g.parse(text);

    final def = g.queries[GLOperationKey("getAuthor", GLQueryType.query)]!;
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

    final def = g.queries[GLOperationKey("getAuthorWithNoArticles", GLQueryType.query)]!;
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
