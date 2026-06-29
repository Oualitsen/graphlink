import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// A *field* argument (on a non-root type field) named after a keyword is
/// structurally safe on the client: when auto-generating queries the propagated
/// variable is namespaced as `<field><Arg>` (e.g. `relatedDefault`), so the bare
/// keyword (`default`) only ever appears as the GraphQL wire argument name in
/// the query text — never as a bare code identifier. This pins that behavior so
/// a future change to the propagation naming can't silently emit `$default`.
void main() {
  test("field argument keyword: namespaced variable, wire arg name preserved",
      () {
    const text = '''
      type Query { car(id: ID!): Car }
      type Car {
        id: ID!
        related(default: Int): Car
      }
    ''';

    final g = GLParser(
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
      reservedWords: dartReservedWords,
    );
    g.parse(text);

    final serializer = DartSerializer(g, importPrefix: "");
    final out =
        DartClientSerializer(g, serializer).generateClient().toFileContent();

    // wire argument name stays `default` in the query/fragment text, bound to a
    // namespaced variable (never a bare `$default`). The fragment is emitted as
    // a Dart string literal, so the `$` is escaped (`\$relatedDefault`).
    expect(out, contains(r'related(default: \$relatedDefault)'));
    expect(out, isNot(contains(r'\$default)')));

    // never an illegal bare `default` identifier as a Dart parameter/field.
    expect(out, isNot(contains(" default,")));
    expect(out, isNot(contains(" default;")));
    expect(out, isNot(contains("required int default")));
  });
}
