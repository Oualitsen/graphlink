import 'package:test/test.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';

const _schema = '''
# Simple self-reference cycle: Employee -> Employee (uses default depth: 1)
type Employee {
  id: ID!
  name: String!
  manager: Employee
}

# Two-field self-referential cycle: Category { parent, children }
type Category {
  id: ID!
  label: String!
  parent: Category
  children: [Category!]
}

# Four-type cycle: Customer -> Order -> Product -> Supplier -> Customer
type Customer {
  id: ID!
  name: String!
  orders: [Order!]
}

type Order {
  id: ID!
  total: Float!
  product: Product
}

type Product {
  id: ID!
  title: String!
  supplier: Supplier
}

type Supplier {
  id: ID!
  company: String!
  customers: [Customer!]
}

type Query {
  getEmployee(id: ID!): Employee!
  getCategory(id: ID!): Category!
  getCustomer(id: ID!): Customer!
}
''';

void main() {
  GLParser parse({int defaultExpandDepth = 1, String? schema}) =>
      GLParser(
        generateAllFieldsFragments: true,
        autoGenerateQueries: true,
        defaultExpandDepth: defaultExpandDepth,
      )..parse(schema ?? _schema);

  /// Navigate: query → response type → field by name → its projected type.
  GLTypeDefinition fieldType(GLParser g, String queryName, String fieldName) {
    final responseType = g.queries[GLOperationKey(queryName, GLQueryType.query)]!.getGeneratedTypeDefinition();
    final field =
        responseType.fields.firstWhere((f) => f.name.token == fieldName);
    return g.projectedTypes[field.type.inlineType.token]!;
  }

  // ─── generated class names ─────────────────────────────────────────────────

  test("print generated class names", () {
    final g = parse();
    final names = g.projectedTypes.keys.toList()..sort();
    print("\n=== Generated projected types (${names.length}) ===");
    for (final name in names) {
      final fields = g.projectedTypes[name]!.fields
          .map((f) => f.name.token)
          .join(", ");
      print("  $name { $fields }");
    }
    // Always passes — this test is for inspection.
    expect(names, isNotEmpty);
  });

  // ─── cycle is broken ───────────────────────────────────────────────────────

  test("parsing succeeds — no Dependency Cycle exception", () {
    expect(() => parse(), returnsNormally);
  });

  // ─── self-reference: Employee { manager: Employee } ────────────────────────

  test("self-reference: Employee projected type has id, name, manager", () {
    final g = parse();
    final employee = fieldType(g, "getEmployee", "getEmployee");
    final names = employee.fields.map((f) => f.name.token).toList();
    expect(names, containsAll(["id", "name", "manager"]));
  });

  test("self-reference: manager field expands into a typed Employee", () {
    final g = parse();
    final employee = fieldType(g, "getEmployee", "getEmployee");
    final managerField =
        employee.fields.firstWhere((f) => f.name.token == "manager");
    final managerType =
        g.projectedTypes[managerField.type.inlineType.token];
    expect(managerType, isNotNull);
    expect(managerType!.fields.map((f) => f.name.token),
        containsAll(["id", "name"]));
  });

  test("self-reference: manager is a recursive fixpoint — one depth-independent Employee type",
      () {
    final g = parse();
    final employee = fieldType(g, "getEmployee", "getEmployee");
    final managerField =
        employee.fields.firstWhere((f) => f.name.token == "manager");
    // Depth-independent type: manager is nullable and points back to the *same*
    // Employee projection (a fixpoint), so the type graph is recursive but
    // finite — termination now lives in the query string, not the type.
    expect(managerField.type.nullable, isTrue);
    expect(managerField.type.inlineType.token, employee.token);
    expect(identical(g.projectedTypes[managerField.type.inlineType.token], employee),
        isTrue);
  });

  // ─── two-field self-referential cycle: Category { parent, children } ───────

  test("Category projected type has id, label, parent, children", () {
    final g = parse();
    final category = fieldType(g, "getCategory", "getCategory");
    final names = category.fields.map((f) => f.name.token).toList();
    expect(names, containsAll(["id", "label", "parent", "children"]));
  });

  test("Category.parent expands into a typed Category", () {
    final g = parse();
    final category = fieldType(g, "getCategory", "getCategory");
    final parentField =
        category.fields.firstWhere((f) => f.name.token == "parent");
    final parentType =
        g.projectedTypes[parentField.type.inlineType.token];
    expect(parentType, isNotNull);
    expect(parentType!.fields.map((f) => f.name.token),
        containsAll(["id", "label"]));
  });

  // ─── four-type cycle: Customer → Order → Product → Supplier → Customer ────

  test("four-type cycle: Customer projected type has id, name, orders", () {
    final g = parse();
    final customer = fieldType(g, "getCustomer", "getCustomer");
    final names = customer.fields.map((f) => f.name.token).toList();
    expect(names, containsAll(["id", "name", "orders"]));
  });

  test("four-type cycle: Customer.orders expands into Order with its own fields", () {
    final g = parse();
    final customer = fieldType(g, "getCustomer", "getCustomer");
    final ordersField =
        customer.fields.firstWhere((f) => f.name.token == "orders");
    final orderType = g.projectedTypes[ordersField.type.inlineType.token];
    expect(orderType, isNotNull);
    expect(orderType!.fields.map((f) => f.name.token),
        containsAll(["id", "total"]));
  });

  test("four-type cycle: finite recursive type graph — chain revisits a type", () {
    final g = parse();
    final fieldSequence = ["orders", "product", "supplier", "customers"];
    GLTypeDefinition current = fieldType(g, "getCustomer", "getCustomer");
    final seen = <String>{current.token};
    bool revisited = false;
    int steps = 0;
    const maxSteps = 20;

    outer:
    while (steps < maxSteps) {
      for (final name in fieldSequence) {
        final fMatches = current.fields.where((f) => f.name.token == name);
        if (fMatches.isEmpty) break outer;
        final next = g.projectedTypes[fMatches.first.type.inlineType.token];
        if (next == null) break outer;
        steps++;
        if (!seen.add(next.token)) {
          revisited = true;
          break outer;
        }
        current = next;
      }
    }
    // The type graph is a finite cycle: following the edges returns to an
    // already-seen type rather than minting fresh per-depth copies forever.
    expect(revisited, isTrue,
        reason: "Customer→Order→Product→Supplier should revisit a type");
    // One projected type per schema type in the cycle (no per-depth copies).
    for (final t in ["Customer", "Order", "Product", "Supplier"]) {
      expect(g.projectedTypes.containsKey(t), isTrue,
          reason: "$t should have a projected type");
    }
  });

  // ─── @glExpand directive overrides depth ───────────────────────────────────

  test("@glExpand(depth:2) — manager chain is deeper than default depth:1", () {
    final g = parse(schema: '''
      type Employee @glExpand(depth: 2) {
        id: ID!
        name: String!
        manager: Employee
      }
      type Query { getEmployee(id: ID!): Employee! }
    ''');
    GLTypeDefinition current = fieldType(g, "getEmployee", "getEmployee");
    int depth = 0;
    const maxDepth = 20;
    while (depth < maxDepth) {
      final fMatches = current.fields.where((f) => f.name.token == "manager");
      if (fMatches.isEmpty) break;
      current = g.projectedTypes[fMatches.first.type.inlineType.token]!;
      depth++;
    }
    expect(depth, greaterThan(1),
        reason: "@glExpand(depth:2) should expand manager 2 levels deep");
  });

  test("@glExpand(depth:0) — cyclic field stays on the type but is dropped from the fragment",
      () {
    final g = parse(schema: '''
      type Employee @glExpand(depth: 0) {
        id: ID!
        name: String!
        manager: Employee
      }
      type Query { getEmployee(id: ID!): Employee! }
    ''');
    // The generated type is depth-independent: manager is still a field, now
    // nullable (the cyclic edge is forced nullable).
    final employee = fieldType(g, "getEmployee", "getEmployee");
    final manager =
        employee.fields.firstWhere((f) => f.name.token == "manager");
    expect(manager.type.nullable, isTrue);
    // But depth:0 omits the cyclic field from the generated query selection
    // (the _all_fields_Employee fragment).
    final fragName = GLGrammarExtension.allFieldsFragmentName("Employee");
    final frag = g.fragments[fragName];
    expect(frag, isNotNull);
    final fragStr =
        GLGraphqlSerializer(g).serializeFragmentDefinitionBase(frag!);
    expect(fragStr.contains("manager"), isFalse,
        reason: "depth:0 drops the cyclic field from the selection");
  });

  // ─── isExhaustive ──────────────────────────────────────────────────────────

  

  

  // ─── depth:2 serialization inspection ────────────────────────────────────

  test("depth:2 — print all projected types serialized as Dart", () {
    final g = parse(schema: '''
      type Employee @glExpand(depth: 2) {
        id: ID!
        name: String!
        manager: Employee
      }
      type Query { getEmployee(id: ID!): Employee! }
    ''');
    final serializer = DartSerializer(g, importPrefix: '');
    final output = g.projectedTypes.entries
        .where((e) =>
            !e.key.startsWith('GraphLink') && !e.key.endsWith('Response'))
        .map((e) {
          final code = serializer.serializeTypeDefinition(e.value);
          return '// --- ${e.key} \n$code';
        })
        .join('\n');
    print('\n$output');
    expect(g.projectedTypes.keys
        .where((k) => !k.startsWith('GraphLink') && !k.endsWith('Response'))
        .length, greaterThan(0));
  });

  // ─── @glExpand depth validation ───────────────────────────────────────────

  test("@glExpand(depth:-1) — negative depth throws ParseException", () {
    expect(
      () => parse(schema: '''
        type Employee @glExpand(depth: -1) {
          id: ID!
          name: String!
          manager: Employee
        }
        type Query { getEmployee(id: ID!): Employee! }
      '''),
      throwsA(isA<ParseException>()),
    );
  });

  
}
