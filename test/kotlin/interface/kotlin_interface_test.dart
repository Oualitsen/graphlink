import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:test/test.dart';

KotlinSerializer _serializer(GLParser g) => KotlinSerializer(
      g,
      importPrefix: 'com.example',
      inputsAsDataClass: true,
      typesAsDataClass: true,
    );

/// Trims every line so indentation never breaks containsAllInOrder checks.
Iterable<String> lines(String s) => s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

const schema = '''
interface BaseBase {
  id: ID!
}

interface Base implements BaseBase {
  id: ID!
}

interface Audit implements Base {
  id: ID!
  createdAt: String!
}

type Post implements Audit {
  id: ID!
  createdAt: String!
  title: String!
}

type Query {
  post(id: ID!): Post
}
''';

void main() {
  group('kotlin interface serialization', () {
    late GLParser g;

    setUp(() {
      g = GLParser()..parse(schema);
    });

    test('BaseBase — root interface, id is not an override', () {
      final out = _serializer(g).serializeTypeDefinition(g.interfaces['BaseBase']!);
      expect(lines(out), containsAllInOrder(['interface BaseBase {', 'val id: String']));
      expect(out, isNot(contains('override val id')));
    });

    test('Base — extends BaseBase, id is overridden', () {
      final out = _serializer(g).serializeTypeDefinition(g.interfaces['Base']!);
      expect(lines(out), containsAllInOrder(['interface Base : BaseBase {', 'override val id: String']));
    });

    test('Audit — extends Base, id is overridden transitively, createdAt is not', () {
      final out = _serializer(g).serializeTypeDefinition(g.interfaces['Audit']!);
      expect(lines(out), containsAllInOrder([
        'interface Audit : Base {',
        'override val id: String',
        'val createdAt: String',
      ]));
      expect(out, isNot(contains('override val createdAt')));
    });
  });
}
