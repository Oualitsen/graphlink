import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

/// Tests for GraphQL spec compliance gaps found in gl_parser.dart.
/// Each group documents the spec rule and the parser location that violates it.
void main() {
  // ── Issue 1 ──────────────────────────────────────────────────────────────
  // Spec: DirectiveLocations → `|`? DirectiveLocation (optional leading pipe)
  // Parser: _parseDirectiveScopes() calls _parseDirectiveScope() immediately
  //         without consuming an optional leading |.
  group('directive scope list — optional leading pipe', () {
    test('directive on single scope with leading pipe', () {
      final parser = GLParser();
      expect(
        () => parser.parse('directive @foo on | FIELD_DEFINITION',
            validate: false),
        returnsNormally,
      );
    });

    test('directive on multiple scopes with leading pipe', () {
      final parser = GLParser();
      expect(
        () => parser.parse(
            'directive @foo on | FIELD_DEFINITION | OBJECT | INPUT_FIELD_DEFINITION',
            validate: false),
        returnsNormally,
      );
    });
  });

  // ── Issue 2 ──────────────────────────────────────────────────────────────
  // Spec: ImplementsInterfaces → `implements` `&`? NamedType (optional leading ampersand)
  // Parser: _parseImplementsClause() calls expectName() immediately after
  //         consuming `implements`, without consuming an optional leading &.
  group('implements clause — optional leading ampersand', () {
    test('type implements single interface with leading ampersand', () {
      final parser = GLParser();
      expect(
        () => parser.parse('type Foo implements & Bar { id: ID! }',
            validate: false),
        returnsNormally,
      );
    });

    test('type implements multiple interfaces with leading ampersand', () {
      final parser = GLParser();
      expect(
        () => parser.parse(
            'type Foo implements & Bar & Baz { id: ID! }', validate: false),
        returnsNormally,
      );
    });
  });

  // ── Issue 3 ──────────────────────────────────────────────────────────────
  // Spec: ObjectTypeExtension → extend type Name Directives[Const]  (no body required)
  //        InputObjectTypeExtension → extend input Name Directives[Const]
  //        InterfaceTypeExtension → extend interface Name Directives[Const]
  //        EnumTypeExtension → extend enum Name Directives[Const]
  // Parser: _parseTypeDefinition / _parseInputDefinition / _parseInterfaceDefinition /
  //         _parseEnumDefinition all call expect(openBrace) unconditionally,
  //         so directive-only extensions without a body throw.
  group('extension definitions — directive-only (no body braces)', () {
    test('extend type with only directives and no body', () {
      final parser = GLParser();
      expect(
        () => parser.parse(
            'type Base { id: ID! }\nextend type Base @deprecated',
            validate: false),
        returnsNormally,
      );
    });

    test('extend input with only directives and no body', () {
      final parser = GLParser();
      expect(
        () => parser.parse(
            'input BaseInput { id: ID! }\nextend input BaseInput @deprecated',
            validate: false),
        returnsNormally,
      );
    });

    test('extend interface with only directives and no body', () {
      final parser = GLParser();
      expect(
        () => parser.parse(
            'interface Node { id: ID! }\nextend interface Node @deprecated',
            validate: false),
        returnsNormally,
      );
    });

    test('extend enum with only directives and no body', () {
      final parser = GLParser();
      expect(
        () => parser.parse(
            'enum Status { ACTIVE }\nextend enum Status @deprecated',
            validate: false),
        returnsNormally,
      );
    });
  });
}
