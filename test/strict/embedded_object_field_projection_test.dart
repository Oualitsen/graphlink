import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';

// Document-store shape (§3): object/list-of-object fields stay embedded
// (no @glSkipOnServer), so the field-ref rewrite + Java List<? extends ...>
// wildcard machinery actually fires.
const _schema = '''
type Address {
    id: ID!
    city: String!
}

type Order {
    id: ID!
    total: Float!
}

type User {
    id: ID!
    name: String!
    address: Address!
    orders: [Order!]!
}
''';

void main() {
  test("Kotlin: embedded object/list fields rewritten to GL<Field>Projection", () {
    final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server);
    g.parse(_schema);

    final serializer = KotlinSerializer(g, importPrefix: "com.example");

    final userProjection = g.interfaces["GLUserProjection"]!;
    final user = g.types["User"]!;

    final userProjectionOut = serializer.serializeTypeDefinition(userProjection);
    final userOut = serializer.serializeTypeDefinition(user);

    print(userProjectionOut);
    print(userOut);

    // Projection: address/orders rewritten to GL<Field>Projection, all-nullable.
    expect(userProjectionOut, contains('val address: GLAddressProjection?'));
    expect(userProjectionOut, contains('val orders: List<GLOrderProjection>?'));

    // User: real types, no wildcard needed (Kotlin List<out E> covariance).
    expect(userOut, contains('override val address: Address'));
    expect(userOut, contains('override val orders: List<Order>'));

    // toJson/fromJson are mandatory — GLUserProjection declares an abstract
    // toJson() that `data class User` overrides.
    expect(userProjectionOut, contains('fun toJson(): Map<String, Any?>'));
    expect(userOut, contains('override fun toJson(): Map<String, Any?>'));
  });

  test("Java: embedded list field needs List<? extends GL<Field>Projection> on the projection", () {
    final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server);
    g.parse(_schema);

    final serializer = JavaSerializer(g, importPrefix: "");

    final userProjection = g.interfaces["GLUserProjection"]!;
    final user = g.types["User"]!;

    final userProjectionOut = serializer.serializeTypeDefinition(userProjection);
    final userOut = serializer.serializeTypeDefinition(user);

    print(userProjectionOut);
    print(userOut);

    // Projection getters: single object -> no wildcard; list -> List<? extends ...>.
    expect(userProjectionOut, contains('GLAddressProjection getAddress();'));
    expect(userProjectionOut, contains('List<? extends GLOrderProjection> getOrders();'));

    // User: covariant overrides with the real types.
    expect(userOut, contains('Address getAddress()'));
    expect(userOut, contains('List<Order> getOrders()'));
  });

  test("TS: embedded object/list fields rewritten to GL<Field>Projection", () {
    final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server);
    g.parse(_schema);

    final serializer = TypeScriptSerializer(g, importPrefix: "");

    final userProjection = g.interfaces["GLUserProjection"]!;
    final user = g.types["User"]!;

    final userProjectionOut = serializer.serializeTypeDefinition(userProjection);
    final userOut = serializer.serializeTypeDefinition(user);

    print(userProjectionOut);
    print(userOut);

    expect(userProjectionOut, contains('readonly address: GLAddressProjection | null;'));
    expect(userProjectionOut, contains('readonly orders: GLOrderProjection[] | null;'));

    expect(userOut, contains('readonly address: Address;'));
    expect(userOut, contains('readonly orders: Order[];'));
  });
}
