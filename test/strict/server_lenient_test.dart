import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';

// @glServerLenient forces a single type's own fields all-nullable on the server
// (restoring pre-strict behavior), so a resolver can return a partially
// populated object. Non-lenient types keep real schema nullability.
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
    final petOut = serializer.serializeTypeDefinition(g.types["Pet"]!);

    // Lenient type: own fields forced nullable.
    expect(userOut, contains('readonly id: string | null;'));
    expect(userOut, contains('readonly name: string | null;'));

    // Default-strict type: real schema nullability.
    expect(petOut, contains('readonly id: string;'));
    expect(petOut, contains('readonly name: string;'));
  });

  test("Java: @glServerLenient", () {
    final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server);
    g.parse(_schema);

    final serializer = JavaSerializer(g, importPrefix: "", jspecify: true);

    final userOut = serializer.serializeTypeDefinition(g.types["User"]!);
    final petOut = serializer.serializeTypeDefinition(g.types["Pet"]!);

    // Lenient type: own fields forced nullable -> @Nullable.
    expect(userOut, contains('@Nullable'));
    expect(userOut, contains('String id;'));

    // Default-strict type: real schema nullability -> @NonNull.
    expect(petOut, contains('@NonNull'));
  });

  test("Kotlin: @glServerLenient", () {
    final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server);
    g.parse(_schema);

    final serializer = KotlinSerializer(g, importPrefix: "com.example");

    final userOut = serializer.serializeTypeDefinition(g.types["User"]!);
    final petOut = serializer.serializeTypeDefinition(g.types["Pet"]!);

    // Lenient type: own fields forced nullable.
    expect(userOut, contains('val id: String?'));
    expect(userOut, contains('val name: String?'));

    // Default-strict type: real schema nullability.
    expect(petOut, contains('val id: String,'));
    expect(petOut, contains('val name: String,'));
  });

  test("Dart: @glServerLenient", () {
    final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server);
    g.parse(_schema);

    final serializer = DartSerializer(g, importPrefix: "");

    final userOut = serializer.serializeTypeDefinition(g.types["User"]!);
    final petOut = serializer.serializeTypeDefinition(g.types["Pet"]!);

    // Lenient type: own fields forced nullable.
    expect(userOut, contains('String? id'));
    expect(userOut, contains('String? name'));

    // Default-strict type: real schema nullability.
    expect(petOut, contains('String id'));
    expect(petOut, isNot(contains('String? id')));
  });
}
