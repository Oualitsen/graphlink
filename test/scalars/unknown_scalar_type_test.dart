import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';

const schema = '''
type Query { me: User }
type User {
  id: ID!
  handle: UserId!
  external: ExtId!
  mapped: MappedId!
}
scalar UserId
scalar ExtId @glExternal(glClass: "BigInt")
scalar MappedId
''';

void main() {
  test('unmapped custom scalar is emitted verbatim when no fallback set', () {
    final g = GLParser();
    g.parse(schema);
    final serializer = DartSerializer(g, importPrefix: '');
    final out = serializer.serializeTypeDefinition(g.types['User']!);

    expect(out, contains('UserId handle;'));
    expect(out, contains('MappedId mapped;'));
  });

  test('unmapped custom scalars fall back to unknownScalarType', () {
    final g = GLParser()..unknownScalarType = 'String';
    g.parse(schema);
    final serializer = DartSerializer(g, importPrefix: '');
    final out = serializer.serializeTypeDefinition(g.types['User']!);

    // Both unmapped scalars resolve to the configured fallback.
    expect(out, contains('String handle;'));
    expect(out, contains('String mapped;'));
    expect(out, isNot(contains('UserId')));
    expect(out, isNot(contains('MappedId')));
  });

  test('fallback does not override @glExternal scalars', () {
    final g = GLParser()..unknownScalarType = 'String';
    g.parse(schema);
    final serializer = DartSerializer(g, importPrefix: '');
    final out = serializer.serializeTypeDefinition(g.types['User']!);

    expect(out, contains('BigInt external;'));
  });

  test('explicit typeMappings take precedence over the fallback', () {
    final g = GLParser()..unknownScalarType = 'String';
    g.parse(schema);
    final serializer = DartSerializer(
      g,
      importPrefix: '',
      typeMapOverrides: const {'MappedId': 'num'},
    );
    final out = serializer.serializeTypeDefinition(g.types['User']!);

    expect(out, contains('num mapped;'));
    // The other unmapped scalar still uses the fallback.
    expect(out, contains('String handle;'));
  });
}
