import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';

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
    final responseType = g.queries[queryName]!.getGeneratedTypeDefinition();
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

  test("self-reference: expansion terminates — deepest manager has no further manager",
      () {
    final g = parse();
    GLTypeDefinition current = fieldType(g, "getEmployee", "getEmployee");
    const maxDepth = 20;
    int depth = 0;
    while (depth < maxDepth) {
      final managerField =
          current.fields.where((f) => f.name.token == "manager").firstOrNull;
      if (managerField == null) break;
      current = g.projectedTypes[managerField.type.inlineType.token]!;
      depth++;
    }
    expect(depth, lessThan(maxDepth),
        reason: "manager chain did not terminate within $maxDepth levels");
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

  test("four-type cycle: expansion terminates — chain has finite length", () {
    final g = parse();
    final fieldSequence = ["orders", "product", "supplier", "customers"];
    GLTypeDefinition current = fieldType(g, "getCustomer", "getCustomer");
    int steps = 0;
    const maxSteps = 20;

    outer:
    while (steps < maxSteps) {
      for (final name in fieldSequence) {
        final f =
            current.fields.where((f) => f.name.token == name).firstOrNull;
        if (f == null) break outer;
        final next = g.projectedTypes[f.type.inlineType.token];
        if (next == null) break outer;
        current = next;
        steps++;
        if (steps >= maxSteps) break outer;
      }
    }
    expect(steps, lessThan(maxSteps),
        reason:
            "Customer→Order→Product→Supplier cycle did not terminate within $maxSteps steps");
  });

  // ─── @glExpand directive overrides depth ───────────────────────────────────

  test("@glExpand(depth:2) — manager chain is deeper than default depth:1", () {
    final schema = _schema.replaceFirst(
      "type Employee {",
      "type Employee @glExpand(depth: 2) {",
    );
    final g = parse(schema: schema);
    GLTypeDefinition current = fieldType(g, "getEmployee", "getEmployee");
    int depth = 0;
    const maxDepth = 20;
    while (depth < maxDepth) {
      final f = current.fields.where((f) => f.name.token == "manager").firstOrNull;
      if (f == null) break;
      current = g.projectedTypes[f.type.inlineType.token]!;
      depth++;
    }
    expect(depth, greaterThan(1),
        reason: "@glExpand(depth:2) should expand manager 2 levels deep");
  });

  test("@glExpand(depth:0) — cyclic field is absent from fragment", () {
    final schema = _schema.replaceFirst(
      "type Employee {",
      "type Employee @glExpand(depth: 0) {",
    );
    final g = parse(schema: schema);
    final employee = fieldType(g, "getEmployee", "getEmployee");
    final names = employee.fields.map((f) => f.name.token).toList();
    expect(names, isNot(contains("manager")));
  });

  // ─── isExhaustive ──────────────────────────────────────────────────────────

  test("cyclic leaf is exhaustive", () {
    final g = parse();
    final employee = fieldType(g, "getEmployee", "getEmployee");
    final managerField = employee.fields.firstWhere((f) => f.name.token == "manager");
    final leaf = g.projectedTypes[managerField.type.inlineType.token]!;
    expect(leaf.isExhaustive(g), isTrue,
        reason: "leaf has all scalars of Employee, missing only the cyclic complex field");
  });

  test("schema type is always exhaustive", () {
    final g = parse();
    final schemaEmployee = g.types["Employee"]!;
    expect(schemaEmployee.isExhaustive(g), isTrue,
        reason: "derivedFromType == null => schema type is definitionally exhaustive");
  });

  test("partial projection is not exhaustive", () {
    final g = GLParser(
      generateAllFieldsFragments: false,
    )..parse('''
      type Employee { id: ID! name: String! manager: Employee }
      type Query { getEmployee: Employee! }
      fragment partialEmployee on Employee { id }
      query getEmployee { getEmployee { ...partialEmployee } }
    ''');
    final projected = g.projectedTypes.values
        .firstWhere((t) => t.derivedFromType?.token == "Employee");
    expect(projected.isExhaustive(g), isFalse,
        reason: "projection omits scalar field name => not exhaustive");
  });
}
