import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';

// @glServerLenient forces a single type's own fields all-nullable (restoring
// pre-@glStrict behavior). GL<Type>Projection is unaffected — it is always
// all-nullable anyway, for every type, lenient or not.
const _schema = '''
type User @glServerLenient {
    id: ID!
    name: String!
}

type Pet {
    id: ID!
    name: String!
}
''';

void main() {
  test("TS: @glServerLenient", () {
    final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server);
    g.parse(_schema);

    final serializer = TypeScriptSerializer(g, importPrefix: "");

    final userOut = serializer.serializeTypeDefinition(g.types["User"]!);
    final userProjectionOut = serializer.serializeTypeDefinition(g.interfaces["GLUserProjection"]!);
    final petOut = serializer.serializeTypeDefinition(g.types["Pet"]!);
    final petProjectionOut = serializer.serializeTypeDefinition(g.interfaces["GLPetProjection"]!);

    print(userOut);
    print(userProjectionOut);
    print(petOut);
    print(petProjectionOut);

    // Lenient type: own fields forced nullable.
    expect(userOut, contains('readonly id: string | null;'));
    expect(userOut, contains('readonly name: string | null;'));

    // Its projection: still all-nullable (no change).
    expect(userProjectionOut, contains('readonly id: string | null;'));
    expect(userProjectionOut, contains('readonly name: string | null;'));

    // Default-strict type: real schema nullability.
    expect(petOut, contains('readonly id: string;'));
    expect(petOut, contains('readonly name: string;'));

    // Its projection: all-nullable, split still emitted.
    expect(petProjectionOut, contains('readonly id: string | null;'));
    expect(petProjectionOut, contains('readonly name: string | null;'));
  });

  test("Java: @glServerLenient", () {
    final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server);
    g.parse(_schema);

    final serializer = JavaSerializer(g, importPrefix: "", jspecify: true);

    final userOut = serializer.serializeTypeDefinition(g.types["User"]!);
    final userProjectionOut = serializer.serializeTypeDefinition(g.interfaces["GLUserProjection"]!);
    final petOut = serializer.serializeTypeDefinition(g.types["Pet"]!);
    final petProjectionOut = serializer.serializeTypeDefinition(g.interfaces["GLPetProjection"]!);

    print(userOut);
    print(userProjectionOut);
    print(petOut);
    print(petProjectionOut);

    // Lenient type: own fields forced nullable -> @Nullable.
    expect(userOut, contains('@Nullable'));
    expect(userOut, contains('String id;'));

    // Default-strict type: real schema nullability -> @NonNull / no @Nullable on fields.
    expect(petOut, contains('@NonNull'));

    // Both projections: all-nullable.
    expect(userProjectionOut, contains('@Nullable'));
    expect(petProjectionOut, contains('@Nullable'));
  });

  test("Kotlin: @glServerLenient", () {
    final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server);
    g.parse(_schema);

    final serializer = KotlinSerializer(g, importPrefix: "com.example");

    final userOut = serializer.serializeTypeDefinition(g.types["User"]!);
    final userProjectionOut = serializer.serializeTypeDefinition(g.interfaces["GLUserProjection"]!);
    final petOut = serializer.serializeTypeDefinition(g.types["Pet"]!);
    final petProjectionOut = serializer.serializeTypeDefinition(g.interfaces["GLPetProjection"]!);

    print(userOut);
    print(userProjectionOut);
    print(petOut);
    print(petProjectionOut);

    // Lenient type: own fields forced nullable.
    expect(userOut, contains('override val id: String?'));
    expect(userOut, contains('override val name: String?'));

    // Its projection: still all-nullable.
    expect(userProjectionOut, contains('val id: String?'));
    expect(userProjectionOut, contains('val name: String?'));

    // Default-strict type: real schema nullability.
    expect(petOut, contains('override val id: String,'));
    expect(petOut, contains('override val name: String,'));

    // Its projection: all-nullable, split still emitted.
    expect(petProjectionOut, contains('val id: String?'));
    expect(petProjectionOut, contains('val name: String?'));
  });

  test("Dart: @glServerLenient", () {
    final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server);
    g.parse(_schema);

    final serializer = DartSerializer(g, importPrefix: "");

    final userOut = serializer.serializeTypeDefinition(g.types["User"]!);
    final userProjectionOut = serializer.serializeTypeDefinition(g.interfaces["GLUserProjection"]!);
    final petOut = serializer.serializeTypeDefinition(g.types["Pet"]!);
    final petProjectionOut = serializer.serializeTypeDefinition(g.interfaces["GLPetProjection"]!);

    print(userOut);
    print(userProjectionOut);
    print(petOut);
    print(petProjectionOut);

    // Lenient type: own fields forced nullable.
    expect(userOut, contains('String? id'));
    expect(userOut, contains('String? name'));

    // Its projection: still all-nullable.
    expect(userProjectionOut, contains('String? get id;'));
    expect(userProjectionOut, contains('String? get name;'));

    // Default-strict type: real schema nullability.
    expect(petOut, contains('String id'));
    expect(petOut, isNot(contains('String? id')));

    // Its projection: all-nullable, split still emitted.
    expect(petProjectionOut, contains('String? get id;'));
    expect(petProjectionOut, contains('String? get name;'));
  });
}
