import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

/// `_applyTypeNaming` (gl_grammar_normalization_extension.dart) sets each
/// container's codeName independently: `container.codeName =
/// convention.typeName(container.wireName)`, with no check against sibling
/// containers. Unlike the leading-underscore rule (sanitizeTypeNames) and the
/// keyword-safe pass (assignCodeNames), which both dedupe against a `taken`
/// set, a naming-convention collision between two *distinct* declared names
/// is never detected — the second one silently overwrites the first's
/// generated file. This needs no adversarial schema, just two ordinarily
/// distinct GraphQL names that happen to normalize to the same code name.
void main() {
  final pascalConvention = NamingConvention(
    field: (s) => s.toLowerCamelCase(),
    enumValue: (s) => s.toLowerCamelCase(),
    typeName: (s) => s.toPascalCase(),
  );

  test('two distinct type names colliding under PascalCase get distinct codeNames', () {
    final g = GLParser(naming: pascalConvention);
    g.parse('''
      type foo { id: ID! }
      type Foo { id: ID! }
    ''');

    final a = g.types['foo']!;
    final b = g.types['Foo']!;

    expect(a.codeName, isNot(b.codeName));
  });

  test('two distinct input names colliding under PascalCase get distinct codeNames', () {
    final g = GLParser(naming: pascalConvention);
    g.parse('''
      input product_filter { active: Boolean }
      input ProductFilter { active: Boolean }
    ''');

    final a = g.inputs['product_filter']!;
    final b = g.inputs['ProductFilter']!;

    expect(a.codeName, isNot(b.codeName));
  });

  test('a type and an input colliding under PascalCase get distinct codeNames', () {
    // Types and inputs live in the same generated-identifier namespace in
    // every target language, so a cross-container collision is just as real.
    final g = GLParser(naming: pascalConvention);
    g.parse('''
      type search_result { id: ID! }
      input SearchResult { active: Boolean }
    ''');

    final t = g.types['search_result']!;
    final i = g.inputs['SearchResult']!;

    expect(t.codeName, isNot(i.codeName));
  });
}
