import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  final pascalConvention = NamingConvention(
    field: (s) => s.toLowerCamelCase(),
    enumValue: (s) => s.toLowerCamelCase(),
    typeName: (s) => s.toPascalCase(),
  );

  // ── type ────────────────────────────────────────────────────────────────────

  group('type name normalization', () {
    test('snake_case type → PascalCase codeName, wire name unchanged', () {
      final g = GLParser(naming: pascalConvention);
      g.parse('type my_entity { id: ID! }');
      final t = g.types['my_entity']!;
      expect(t.codeName, 'MyEntity');
      expect(t.token, 'my_entity');
    });

    test('SCREAMING_SNAKE type → PascalCase codeName, wire name unchanged', () {
      final g = GLParser(naming: pascalConvention);
      g.parse('type MY_ENTITY { id: ID! }');
      final t = g.types['MY_ENTITY']!;
      expect(t.codeName, 'MyEntity');
      expect(t.token, 'MY_ENTITY');
    });

    test('leading-underscore type → Entity_ (trailing _ added even after PascalCase strips leading _)', () {
      final g = GLParser(naming: pascalConvention);
      g.parse('type _Entity { id: ID! }');
      final t = g.types['_Entity']!;
      expect(t.codeName, 'Entity_');
      expect(t.token, '_Entity');
    });

    test('already PascalCase type is not renamed', () {
      final g = GLParser(naming: pascalConvention);
      g.parse('type Product { id: ID! }');
      final t = g.types['Product']!;
      expect(t.codeName, 'Product');
    });

    test('without NamingConvention codeName equals wire name', () {
      final g = GLParser();
      g.parse('type my_entity { id: ID! }');
      final t = g.types['my_entity']!;
      expect(t.codeName, 'my_entity');
    });
  });

  // ── input ───────────────────────────────────────────────────────────────────

  group('input name normalization', () {
    test('snake_case input → PascalCase codeName, wire name unchanged', () {
      final g = GLParser(naming: pascalConvention);
      g.parse('input product_filter { active: Boolean }');
      final i = g.inputs['product_filter']!;
      expect(i.codeName, 'ProductFilter');
      expect(i.token, 'product_filter');
    });

    test('SCREAMING_SNAKE input → PascalCase codeName', () {
      final g = GLParser(naming: pascalConvention);
      g.parse('input SEARCH_QUERY { text: String }');
      final i = g.inputs['SEARCH_QUERY']!;
      expect(i.codeName, 'SearchQuery');
      expect(i.token, 'SEARCH_QUERY');
    });

    test('already PascalCase input is not renamed', () {
      final g = GLParser(naming: pascalConvention);
      g.parse('input ProductFilter { active: Boolean }');
      final i = g.inputs['ProductFilter']!;
      expect(i.codeName, 'ProductFilter');
    });
  });

  // ── union ───────────────────────────────────────────────────────────────────

  group('union name normalization', () {
    test('snake_case union → PascalCase codeName, wire name unchanged', () {
      final g = GLParser(naming: pascalConvention);
      g.parse('''
        type Cat { name: String }
        type Dog { name: String }
        union search_result = Cat | Dog
      ''');
      final u = g.unions['search_result']!;
      expect(u.codeName, 'SearchResult');
      expect(u.token, 'search_result');
    });

    test('SCREAMING_SNAKE union → PascalCase codeName', () {
      final g = GLParser(naming: pascalConvention);
      g.parse('''
        type Cat { name: String }
        type Dog { name: String }
        union SEARCH_RESULT = Cat | Dog
      ''');
      final u = g.unions['SEARCH_RESULT']!;
      expect(u.codeName, 'SearchResult');
      expect(u.token, 'SEARCH_RESULT');
    });

    test('already PascalCase union is not renamed', () {
      final g = GLParser(naming: pascalConvention);
      g.parse('''
        type Cat { name: String }
        type Dog { name: String }
        union SearchResult = Cat | Dog
      ''');
      final u = g.unions['SearchResult']!;
      expect(u.codeName, 'SearchResult');
    });
  });

  // ── leading-underscore sanitization (runs even without a convention) ────────

  group('leading underscore sanitization', () {
    test('_Entity without convention → Entity_', () {
      final g = GLParser(); // no naming convention
      g.parse('type _Entity { id: ID! }');
      expect(g.types['_Entity']!.codeName, 'Entity_');
      expect(g.types['_Entity']!.token, '_Entity');
    });

    test('_Entity with convention → Entity_ (wire name starts with _, trailing _ always added)', () {
      final g = GLParser(naming: pascalConvention);
      g.parse('type _Entity { id: ID! }');
      // Even after toPascalCase removes the leading _, sanitizeTypeNames must
      // add a trailing _ because the wire name starts with _.
      expect(g.types['_Entity']!.codeName, 'Entity_');
    });

    test('collision: _Entity_ and Entity_ both exist → Entity_2', () {
      // Wire name `Entity_` clashes with what `_Entity` would normalize to.
      final g = GLParser();
      g.parse('''
        type _Entity { id: ID! }
        type Entity_ { id: ID! }
      ''');
      expect(g.types['_Entity']!.codeName, 'Entity_2');
      expect(g.types['Entity_']!.codeName, 'Entity_');
    });

    test('collision with index also taken → bumps to next free index', () {
      final g = GLParser();
      g.parse('''
        type _Entity { id: ID! }
        type Entity_ { id: ID! }
        type Entity_2 { id: ID! }
      ''');
      expect(g.types['_Entity']!.codeName, 'Entity_3');
    });

    test('leading underscore on input is sanitized', () {
      final g = GLParser();
      g.parse('input _Filter { active: Boolean }');
      expect(g.inputs['_Filter']!.codeName, 'Filter_');
    });

    test('leading underscore on union is sanitized', () {
      final g = GLParser();
      g.parse('''
        type Cat { name: String }
        type Dog { name: String }
        union _Result = Cat | Dog
      ''');
      expect(g.unions['_Result']!.codeName, 'Result_');
    });

    test('_Entity union: union codeName is Entity_, auto-synthesized interface is unaffected', () {
      // Unions are internally converted to interfaces (fromUnion == true).
      // The synthesized _Entity interface must NOT compete with the union for
      // the Entity_ code name — it is excluded from sanitization entirely.
      final g = GLParser();
      g.parse('''
        type App { id: ID! }
        type PageType { id: ID! }
        union _Entity = App | PageType
      ''');
      // Union gets the sanitized name.
      expect(g.unions['_Entity']!.codeName, 'Entity_');
      expect(g.unions['_Entity']!.token, '_Entity');
      // The synthesized interface is synced to the union's codeName so the
      // abstract class declaration and `implements` clauses stay consistent.
      expect(g.interfaces['_Entity']!.codeName, 'Entity_');
    });

    test('leading underscore on enum is sanitized', () {
      final g = GLParser();
      g.parse('enum _Status { ACTIVE }');
      expect(g.enums['_Status']!.codeName, 'Status_');
    });
  });

  // ── enum definition name ─────────────────────────────────────────────────

  group('enum definition name normalization', () {
    test('snake_case enum → PascalCase codeName, wire name unchanged', () {
      final g = GLParser(naming: pascalConvention);
      g.parse('enum order_status { PENDING SHIPPED }');
      final e = g.enums['order_status']!;
      expect(e.codeName, 'OrderStatus');
      expect(e.token, 'order_status');
    });

    test('already PascalCase enum is not renamed', () {
      final g = GLParser(naming: pascalConvention);
      g.parse('enum OrderStatus { PENDING SHIPPED }');
      final e = g.enums['OrderStatus']!;
      expect(e.codeName, 'OrderStatus');
    });
  });
}
