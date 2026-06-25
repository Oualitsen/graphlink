import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/gl_expand_grammar_extension.dart';
import 'package:graphlink/src/gl_grammar_extension.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';

// Tests for @glExpand depth propagation through interface-mediated cycles.
//
// Regression: when the cycle back-edge is an abstract field (interface/union),
// the fragment generator used `defaultExpandDepth` instead of the owning
// type's `@glExpand(depth:)` value, producing inline fragments that dropped
// all object-typed fields past the interface hop (owner, driver, etc.).

GLParser parseAuto(String schema, {int defaultExpandDepth = 1}) => GLParser(
      generateAllFieldsFragments: true,
      autoGenerateQueries: true,
      defaultExpandDepth: defaultExpandDepth,
    )..parse(schema);

String fragFor(GLParser g, String typeName) {
  final name = GLGrammarExtension.allFieldsFragmentName(typeName);
  final frag = g.fragments[name]!;
  return GLGraphqlSerializer(g).serializeFragmentDefinitionBase(frag);
}

// ─── baseline: concrete self-cycle ────────────────────────────────────────────
// @glExpand on a concrete self-referential type — the existing path.
// depth 2 → manager { manager { scalars } }.

const _concreteSelfCycle = '''
type Employee @glExpand(depth: 2) {
  id: ID!
  name: String!
  manager: Employee
}
type Query { getEmployee(id: ID!): Employee! }
''';

// ─── abstract back-edge: 3-type chain through interface ───────────────────────
// Car/Bike are declared FIRST so the DFS visits them before VehicleDriver.
// Path: Car → VehicleOwner → VehicleDriver → vehicle:Vehicle → Car (on stack)
// ⇒ "VehicleDriver.vehicle" (abstract) is recorded as the back-edge.
//
// With @glExpand(depth:2) on VehicleDriver the inline expansion should be:
//   layer 1 — Car/Bike scalars + id       (vehicle → Car/Bike, depth rem 1)
//   layer 2 — Car.owner / Bike.owner      (→ VehicleOwner scalars, depth rem 0)
//
// Bug: abstract back-edge uses defaultExpandDepth=1 instead of 2, collapsing
// the inline expansion to depth:0 → Car/Bike scalars only, owner missing.
const _abstractBackEdgeDepth2 = '''
type Car implements Vehicle {
  id: ID!
  model: String!
  owner: VehicleOwner!
}
type Bike implements Vehicle {
  id: ID!
  brand: String!
  owner: VehicleOwner!
}
interface Vehicle {
  id: ID!
  owner: VehicleOwner!
}
type VehicleOwner {
  id: ID!
  name: String!
  driver: VehicleDriver!
}
type VehicleDriver @glExpand(depth: 2) {
  id: ID!
  name: String!
  vehicle: Vehicle
}
type Query { getVehicleDriver(id: ID!): VehicleDriver! }
''';

// Same structure but depth:3.
// layer 3: VehicleOwner.driver → VehicleDriver scalars (depth rem 0)
const _abstractBackEdgeDepth3 = '''
type Car implements Vehicle {
  id: ID!
  model: String!
  owner: VehicleOwner!
}
type Bike implements Vehicle {
  id: ID!
  brand: String!
  owner: VehicleOwner!
}
interface Vehicle {
  id: ID!
  owner: VehicleOwner!
}
type VehicleOwner {
  id: ID!
  name: String!
  driver: VehicleDriver!
}
type VehicleDriver @glExpand(depth: 3) {
  id: ID!
  name: String!
  vehicle: Vehicle
}
type Query { getVehicleDriver(id: ID!): VehicleDriver! }
''';

void main() {
  // ── baseline: concrete self-cycle still works ──────────────────────────────

  group('baseline — concrete self-cycle @glExpand(depth:2)', () {
    test('manager appears at depth 1', () {
      final g = parseAuto(_concreteSelfCycle);
      final frag = fragFor(g, 'Employee');
      expect(frag, contains('manager'),
          reason: 'depth 2 must include at least one manager hop');
    });

    test('inner manager (depth 2) appears', () {
      final g = parseAuto(_concreteSelfCycle);
      final frag = fragFor(g, 'Employee');
      print(frag);
      // The serialized fragment contains manager twice: once for depth-1 and
      // once for depth-2 (scalars-only).
      final count = 'manager'.allMatches(frag).length;
      expect(count, greaterThanOrEqualTo(2),
          reason: 'depth 2 should produce two manager expansions');
    });
  });

  // ── abstract back-edge detection ─────────────────────────────────────────

  group('abstract back-edge — detection', () {
    test('VehicleDriver.vehicle is the abstract back-edge', () {
      final g = parseAuto(_abstractBackEdgeDepth2);
      expect(g.isBackEdgeField('VehicleDriver', 'vehicle'), isTrue,
          reason: 'Car appears before VehicleDriver in the schema — the DFS '
              'discovers Car while on VehicleDriver, so the abstract field '
              'vehicle becomes the recorded break point');
    });

    test('VehicleDriver is cyclic', () {
      final g = parseAuto(_abstractBackEdgeDepth2);
      expect(g.cyclicTypeNames, contains('VehicleDriver'));
    });
  });

  // ── abstract back-edge, depth:2 ───────────────────────────────────────────

  group('abstract back-edge @glExpand(depth:2)', () {
    test('parsing succeeds', () {
      expect(() => parseAuto(_abstractBackEdgeDepth2), returnsNormally);
    });

    test('_all_fields_VehicleDriver contains the vehicle field', () {
      final g = parseAuto(_abstractBackEdgeDepth2);
      expect(fragFor(g, 'VehicleDriver'), contains('vehicle'));
    });

    test('Car inline fragment contains model (layer 1 scalar)', () {
      final g = parseAuto(_abstractBackEdgeDepth2);
      expect(fragFor(g, 'VehicleDriver'), contains('model'));
    });

    test('Bike inline fragment contains brand (layer 1 scalar)', () {
      final g = parseAuto(_abstractBackEdgeDepth2);
      expect(fragFor(g, 'VehicleDriver'), contains('brand'));
    });

    test('owner appears at layer 2 inside Car/Bike inline fragments', () {
      final g = parseAuto(_abstractBackEdgeDepth2);
      final frag = fragFor(g, 'VehicleDriver');
      // depth:2 → vehicle(layer1) → owner(layer2) → VehicleOwner scalars
      // Bug: abstract back-edge collapses to depth:0, owner never appears.
      expect(frag, contains('owner'),
          reason: '@glExpand(depth:2) must expand one hop past the interface '
              'to include Car.owner / Bike.owner');
    });

    test('driver is absent — depth:2 terminates at VehicleOwner scalars', () {
      final g = parseAuto(_abstractBackEdgeDepth2);
      final frag = fragFor(g, 'VehicleDriver');
      expect(frag, isNot(contains('driver')),
          reason: 'depth:2 stops at VehicleOwner; driver would be depth:3');
    });
  });

  // ── abstract back-edge, depth:3 ───────────────────────────────────────────

  group('abstract back-edge @glExpand(depth:3)', () {
    test('owner appears at layer 2', () {
      final g = parseAuto(_abstractBackEdgeDepth3);
      expect(fragFor(g, 'VehicleDriver'), contains('owner'));
    });

    test('driver appears at layer 3', () {
      final g = parseAuto(_abstractBackEdgeDepth3);
      final frag = fragFor(g, 'VehicleDriver');
      // depth:3 → vehicle(1) → owner(2) → driver(3) → VehicleDriver scalars
      expect(frag, contains('driver'),
          reason: '@glExpand(depth:3) must reach the third cyclic hop');
    });

    test('vehicle appears exactly once — dropped at depth:0 inside driver', () {
      final g = parseAuto(_abstractBackEdgeDepth3);
      final frag = fragFor(g, 'VehicleDriver');
      // The innermost VehicleDriver (inside driver at depth:3) has
      // remainingDepth=0 so its vehicle field is dropped.
      expect('vehicle'.allMatches(frag).length, equals(1),
          reason: 'vehicle appears only at the top-level expansion');
    });
  });

  // ── union back-edge — same fix, union path ────────────────────────────────
  // Identical structure but Vehicle is a union instead of an interface.
  // The `isConcreteTarget = false` branch also fires for unions, so the same
  // fix applies.  Car still comes first → DFS records VehicleDriver.vehicle
  // (union-typed) as the abstract back-edge.

  group('union back-edge @glExpand(depth:2)', () {
    const _unionBackEdgeDepth2 = '''
type Car {
  id: ID!
  model: String!
  owner: VehicleOwner!
}
type Bike {
  id: ID!
  brand: String!
  owner: VehicleOwner!
}
union Vehicle = Car | Bike
type VehicleOwner {
  id: ID!
  name: String!
  driver: VehicleDriver!
}
type VehicleDriver @glExpand(depth: 2) {
  id: ID!
  name: String!
  vehicle: Vehicle
}
type Query { getVehicleDriver(id: ID!): VehicleDriver! }
''';

    test('VehicleDriver.vehicle is the union back-edge', () {
      final g = parseAuto(_unionBackEdgeDepth2);
      expect(g.isBackEdgeField('VehicleDriver', 'vehicle'), isTrue);
    });

    test('owner appears at layer 2 inside Car/Bike inline fragments', () {
      final g = parseAuto(_unionBackEdgeDepth2);
      final frag = fragFor(g, 'VehicleDriver');
      expect(frag, contains('owner'),
          reason: '@glExpand(depth:2) on a union back-edge must also '
              'respect the owning type depth, not defaultExpandDepth');
    });

    test('driver is absent — depth:2 terminates at VehicleOwner', () {
      final g = parseAuto(_unionBackEdgeDepth2);
      expect(fragFor(g, 'VehicleDriver'), isNot(contains('driver')));
    });
  });

  // ── defaultExpandDepth fallback (no @glExpand) ─────────────────────────────

  group('no @glExpand — defaultExpandDepth controls abstract back-edge depth', () {
    const _noDirective = '''
type Car implements Vehicle { id: ID! model: String! owner: VehicleOwner! }
interface Vehicle { id: ID! owner: VehicleOwner! }
type VehicleOwner { id: ID! name: String! driver: VehicleDriver! }
type VehicleDriver { id: ID! name: String! vehicle: Vehicle }
type Query { getVehicleDriver(id: ID!): VehicleDriver! }
''';

    test('defaultExpandDepth:1 → owner absent (only layer-1 scalars)', () {
      final g = parseAuto(_noDirective, defaultExpandDepth: 1);
      final frag = fragFor(g, 'VehicleDriver');
      expect(frag, contains('vehicle'));
      expect(frag, contains('model'));
      expect(frag, isNot(contains('owner')),
          reason: 'depth:1 → Car scalars only; owner is at depth:2');
    });

    test('defaultExpandDepth:2 → owner present', () {
      final g = parseAuto(_noDirective, defaultExpandDepth: 2);
      expect(fragFor(g, 'VehicleDriver'), contains('owner'));
    });
  });
}
