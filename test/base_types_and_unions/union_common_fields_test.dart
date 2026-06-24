import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

// `brand` (String!) and `year` (Int!) are identical across every member, so
// they are safe to promote onto the Vehicle union supertype.
//
// `capacity` appears on all three members BUT its type diverges — Int! for the
// passenger vehicles, Float! (cargo tonnes) for the truck. A field whose type
// is not identical across members must NOT be lifted, otherwise the supertype
// would declare a getter no member can honor.
//
// `doors` / `electric` / `axles` are each unique to one member and must not be
// lifted either.
const schema = '''
union Vehicle = Car | Motorcycle | Truck

type Car {
  brand: String!
  year: Int!
  capacity: Int!
  doors: Int!
}

type Motorcycle {
  brand: String!
  year: Int!
  capacity: Int!
  electric: Boolean!
}

type Truck {
  brand: String!
  year: Int!
  capacity: Float!
  axles: Int!
}
''';

void main() {
  test("union supertype only lifts fields identical across all members", () {
    final GLParser g = GLParser();
    g.parse(schema);

    // Unions are converted into an abstract supertype stored in `interfaces`.
    final vehicle = g.interfaces["Vehicle"]!;
    final fields = vehicle.getSerializableFields(g.mode);
    final byName = {for (final f in fields) f.name.token: f};

    // Only the fields that are identical (name + type) across every member.
    expect(byName.keys, unorderedEquals(["brand", "year"]));

    // The lifted fields keep their shared type.
    expect(byName["brand"]!.type.token, "String");
    expect(byName["year"]!.type.token, "Int");

    // Same name but divergent type across members — must not be lifted.
    expect(byName.containsKey("capacity"), isFalse);

    // Fields unique to a single member — must not be lifted.
    expect(byName.containsKey("doors"), isFalse);
    expect(byName.containsKey("electric"), isFalse);
    expect(byName.containsKey("axles"), isFalse);
  });

  test("union does not lift a field that is scalar on one member, list on another",
      () {
    // `tags` has the SAME name and the SAME element type (String!) on both
    // members, but Dog declares it as a single value and Parrot as a list.
    // List vs non-list is a type mismatch — it must not be lifted, even though
    // the inner element type matches. `name` (plain String! on both) still is.
    const schema = '''
union Pet = Dog | Parrot

type Dog {
  name: String!
  tags: String!
}

type Parrot {
  name: String!
  tags: [String!]!
}
''';

    final GLParser g = GLParser();
    g.parse(schema);

    final pet = g.interfaces["Pet"]!;
    final byName = {
      for (final f in pet.getSerializableFields(g.mode)) f.name.token: f
    };

    // Genuinely common scalar field is still lifted.
    expect(byName.keys, unorderedEquals(["name"]));
    expect(byName["name"]!.type.token, "String");
    expect(byName["name"]!.type.isList, isFalse);

    // Same name + same element type, but scalar-vs-list — must be dropped.
    expect(byName.containsKey("tags"), isFalse);
  });

  test("union does not lift a field that is a list on one member, a matrix on another",
      () {
    // `cells` has the SAME name and the SAME innermost element type (Int!) on
    // both members, but RowThing declares a list `[Int!]!` and MatrixThing a
    // list-of-lists `[[Int!]!]!`. Differing list nesting depth is a type
    // mismatch — it must not be lifted. `label` (plain String!) still is.
    //
    // This guards the asymmetry of GLType/GLListType equality: `[Int!]!` can
    // spuriously equal `[[Int!]!]!` in one direction, so the match must be
    // checked both ways.
    const schema = '''
union Grid = RowThing | MatrixThing

type RowThing {
  label: String!
  cells: [Int!]!
}

type MatrixThing {
  label: String!
  cells: [[Int!]!]!
}
''';

    final GLParser g = GLParser();
    g.parse(schema);

    final grid = g.interfaces["Grid"]!;
    final byName = {
      for (final f in grid.getSerializableFields(g.mode)) f.name.token: f
    };

    // Genuinely common scalar field is still lifted.
    expect(byName.keys, unorderedEquals(["label"]));
    expect(byName["label"]!.type.token, "String");
    expect(byName["label"]!.type.isList, isFalse);

    // List vs matrix (different nesting depth) — must be dropped.
    expect(byName.containsKey("cells"), isFalse);
  });

  test("union does not lift a matrix field whose inner list nullability differs",
      () {
    // `cells` has the SAME name, SAME nesting depth, and SAME innermost element
    // (Int!) on both members. The ONLY difference is the inner list's
    // nullability: NullableInner has `[[Int!]]` (inner list nullable) while
    // NonNullInner has `[[Int!]!]` (inner list non-null). Nullability is part
    // of the type — this must not be lifted. `label` (String!) still is.
    const schema = '''
union Grid = NullableInner | NonNullInner

type NullableInner {
  label: String!
  cells: [[Int!]]
}

type NonNullInner {
  label: String!
  cells: [[Int!]!]
}
''';

    final GLParser g = GLParser();
    g.parse(schema);

    final grid = g.interfaces["Grid"]!;
    final byName = {
      for (final f in grid.getSerializableFields(g.mode)) f.name.token: f
    };

    // Genuinely common scalar field is still lifted.
    expect(byName.keys, unorderedEquals(["label"]));

    // Inner list nullability differs ([[Int!]] vs [[Int!]!]) — must be dropped.
    expect(byName.containsKey("cells"), isFalse);
  });
}
