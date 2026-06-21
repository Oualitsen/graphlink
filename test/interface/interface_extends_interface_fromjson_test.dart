import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

const schema = '''
interface Entity {
  id: ID!
}

interface Vehicle implements Entity {
  id: ID!
  wheels: Int!
}

type Car implements Vehicle & Entity {
  id: ID!
  wheels: Int!
  doors: Int!
}

type Truck implements Vehicle & Entity {
  id: ID!
  wheels: Int!
  loadCapacity: Float!
}
''';

// Transitive-only: Car/Truck declare `implements Vehicle` but NOT Entity.
// Entity has no direct concrete implementers; they only reach it via Vehicle.
const transitiveSchema = '''
interface Entity {
  id: ID!
}

interface Vehicle implements Entity {
  id: ID!
  wheels: Int!
}

type Car implements Vehicle {
  id: ID!
  wheels: Int!
  doors: Int!
}

type Truck implements Vehicle {
  id: ID!
  wheels: Int!
  loadCapacity: Float!
}
''';

// A plain union over the same concrete types. Union members are always concrete
// object types, so the transitive-flattening fix must leave union dispatch intact.
const unionSchema = '''
type Car {
  id: ID!
  doors: Int!
}

type Truck {
  id: ID!
  loadCapacity: Float!
}

union Vehicle = Car | Truck
''';

void main() {
  test("interface extends interface fromJson", () {
    final GLParser g = GLParser();
    g.parse(schema);

    var serializer = DartSerializer(g, importPrefix: "");

    final entity =
        serializer.serializeInterface(g.interfaces["Entity"]!).trim();

    // Entity dispatches only to concrete types, never to the Vehicle sub-interface.
    expect(entity, contains("case 'Car':"));
    expect(entity, contains("case 'Truck':"));
    expect(entity, isNot(contains("case 'Vehicle':")));
    expect(entity, isNot(contains("Vehicle.fromJson")));
  });

  test("transitive-only: Entity resolves implementers through Vehicle", () {
    final GLParser g = GLParser();
    g.parse(transitiveSchema);

    var serializer = DartSerializer(g, importPrefix: "");

    final entity =
        serializer.serializeInterface(g.interfaces["Entity"]!).trim();

    // Car/Truck only declare `implements Vehicle`; Entity must still reach them.
    expect(entity, contains("case 'Car':"));
    expect(entity, contains("case 'Truck':"));
    expect(entity, isNot(contains("case 'Vehicle':")));
  });

  test("union fromJson dispatch is unaffected by the fix", () {
    final GLParser g = GLParser();
    g.parse(unionSchema);

    var serializer = DartSerializer(g, importPrefix: "");

    final vehicle =
        serializer.serializeInterface(g.interfaces["Vehicle"]!).trim();

    expect(vehicle, contains("case 'Car':"));
    expect(vehicle, contains("case 'Truck':"));
  });
}
