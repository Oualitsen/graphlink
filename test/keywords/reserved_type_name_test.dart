import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
  type Map { id: ID! }
  type Error { id: ID! }
  type Optional { id: ID! }
  type Holder { map: Map! error: Error! optional: Optional! }
  type Query { holder: Holder! }
''';

GLParser _parse({required Set<String> typeNames, Set<String> words = const {}}) =>
    GLParser(reservedWords: words, reservedTypeNames: typeNames)..parse(_schema);

void main() {
  group('a type named after a standard-library type gets a safe code name', () {
    test('Dart', () {
      final g = _parse(typeNames: dartReservedTypeNames, words: dartReservedWords);
      expect(g.types['Map']!.codeName, 'Map_');
      expect(g.types['Holder']!.codeName, 'Holder');
    });

    test('Java', () {
      final g = _parse(typeNames: javaReservedTypeNames, words: javaReservedWords);
      expect(g.types['Map']!.codeName, 'Map_');
      expect(g.types['Error']!.codeName, 'Error_');
      expect(g.types['Optional']!.codeName, 'Optional_');
    });

    test('Kotlin', () {
      final g = _parse(typeNames: kotlinReservedTypeNames, words: kotlinReservedWords);
      expect(g.types['Map']!.codeName, 'Map_');
      expect(g.types['Error']!.codeName, 'Error_');
    });

    test('Swift', () {
      final g = _parse(typeNames: swiftReservedTypeNames, words: swiftReservedWords);
      expect(g.types['Error']!.codeName, 'Error_');
      expect(g.types['Optional']!.codeName, 'Optional_');
    });

    test('Python', () {
      final g = _parse(typeNames: pythonReservedTypeNames, words: pythonReservedWords);
      expect(g.types['Optional']!.codeName, 'Optional_');
    });

    test('TypeScript', () {
      final g = _parse(typeNames: typescriptReservedTypeNames);
      expect(g.types['Map']!.codeName, 'Map_');
      expect(g.types['Error']!.codeName, 'Error_');
    });
  });

  test('the wire name is untouched', () {
    final g = _parse(typeNames: dartReservedTypeNames, words: dartReservedWords);
    expect(g.types['Map']!.token, 'Map');
  });

  test('a renamed type never collides with an existing one', () {
    final g = GLParser(reservedTypeNames: dartReservedTypeNames)
      ..parse('type Map { id: ID! } type Map_ { id: ID! } type Query { a: Map b: Map_ }');
    expect(g.types['Map']!.codeName, isNot('Map_'));
    expect(g.types['Map_']!.codeName, 'Map_');
  });

  test('no type names are reserved by default', () {
    final g = GLParser()..parse(_schema);
    expect(g.types['Map']!.codeName, 'Map');
  });

  test('Dart: await is not usable as an argument name', () {
    final g = GLParser(
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
      reservedWords: dartReservedWords,
    )..parse('type Person { id: ID! } type Query { f(await: String!, yield: String!): Person }');
    expect(g.queries.values.single.arguments.map((a) => a.codeName), ['await_', 'yield_']);
  });

  test('Java: a field named map does not collide with the toJson local', () {
    final g = GLParser(reservedWords: javaReservedWords)
      ..parse('type Holder { map: String! } type Query { holder: Holder }');
    final out = JavaSerializer(g, importPrefix: '').serializeTypeDefinition(g.types['Holder']!);
    expect(out, contains('glMap__.put("map", map);'));
    expect(out, isNot(contains(' map = new HashMap')));
  });

  test('Swift: await is not usable as a field name', () {
    final g = GLParser(reservedWords: swiftReservedWords)
      ..parse('type Holder { await: String! } type Query { holder: Holder }');
    expect(g.types['Holder']!.fields.single.codeName, 'await_');
  });
}
