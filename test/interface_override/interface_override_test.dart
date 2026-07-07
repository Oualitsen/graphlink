import 'package:graphlink/src/model/gl_collection_imports.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/java_imports.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:test/test.dart';

const schema = '''
interface Base { id: ID! }
type Cat implements Base { id: ID! name: String }
''';

void main() {
  test('Dart: implementing type emits @override on interface-declared field', () {
    final g = GLParser()..parse(schema);
    final ser = DartSerializer(g, importPrefix: '');

    final cat = ser.serializeTypeDefinition(g.types['Cat']!);

    expect(cat, contains('@override\n   final String id;'));
    expect(cat, isNot(contains('@override\n   final String? name;')));
    expect(cat, contains("import '/interfaces/base.dart';"));
  });

  test('Java: implementing type emits @Override on interface-declared getter', () {
    final g = GLParser()..parse(schema);
    final ser = JavaSerializer(g, importPrefix: '');

    final cat = ser.serializeTypeDefinition(g.types['Cat']!);

    expect(cat, contains('@Override\n   public String getId()'));
    expect(cat, isNot(contains('@Override\n   public String getName()')));
    expect(cat, contains('import .interfaces.Base;'));
  });

  test('Kotlin: implementing type emits override on interface-declared property', () {
    final g = GLParser()..parse(schema);
    final ser = KotlinSerializer(g, importPrefix: '');

    final cat = ser.serializeTypeDefinition(g.types['Cat']!);

    expect(cat, contains('override val id: String'));
    expect(cat, isNot(contains('override val name: String')));
    expect(cat, contains('import .interfaces.Base'));
  });

  test('Java: overriding getter matches interface nullability when a non-null '
      'field narrows a nullable Boolean', () {
    const narrowingSchema = '''
interface Base { alive: Boolean }
type Cat implements Base { alive: Boolean! }
''';
    final g = GLParser()..parse(narrowingSchema);
    final ser = JavaSerializer(g,
        importPrefix: '', typeMapOverrides: const {'Boolean': 'boolean'});

    final base = ser.serializeTypeDefinition(g.interfaces['Base']!);
    final cat = ser.serializeTypeDefinition(g.types['Cat']!);

    // Interface keeps the boxed, nullable-style getter.
    expect(base, contains('Boolean getAlive();'));

    // The implementer's private field narrows to primitive boolean, but the
    // public getter must still match the interface's boxed return type and
    // "get"-prefixed name (not "isAlive") to remain a valid override.
    expect(cat, contains('private boolean alive;'));
    expect(cat, contains('@Override\n   public Boolean getAlive()'));
    expect(cat, isNot(contains('isAlive')));
    expect(cat, contains('import .interfaces.Base;'));
  });

  test('Java: print output when a covariant list field narrows the interface element type', () {
    const listSchema = '''
interface Animal { id: ID! }
interface Enclosure { animals: [Animal!]! }

type Lion implements Animal { id: ID! }
type Zoo implements Enclosure { animals: [Lion!]! }

type Query {
  getZoo: Zoo!
}
''';
    final g = GLParser(collectionImports: const GLCollectionImports(listImport: JavaImports.list, mapImport: JavaImports.map))..parse(listSchema);
    final ser = JavaSerializer(g, importPrefix: '');

    final zoo = ser.serializeTypeDefinition(g.types['Zoo']!);

    print(zoo);

    expect(zoo, contains('@Override\n   public List<Lion> getAnimals()'));

    expect(zoo, contains('import .types.Lion;'));

    expect(zoo, contains('import .interfaces.Enclosure;'));

    expect(zoo, contains('import java.util.List;'));

    // Zoo returns its own narrowed element type, so it never needs to import
    // the interface's declared element type (Animal) directly.
    expect(zoo, isNot(contains('import .interfaces.Animal;')));
  });
}
