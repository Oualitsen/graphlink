import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_expand_grammar_extension.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';

GLParser parseAuto(String schema, {int defaultExpandDepth = 1}) => GLParser(
      generateAllFieldsFragments: true,
      autoGenerateQueries: true,
      defaultExpandDepth: defaultExpandDepth,
    )..parse(schema);

// ─── abstract-only cycle ────────────────────────────────────────────────────
// The ONLY edge closing the cycle is interface-typed: Item.next : Node!, where
// Node is implemented by Item. There is no concrete back-edge — the previous
// feedback-set pass (concrete-only) left this cycle unbroken, which made the
// `_all_fields_Item` / `_all_fields_Node` fragments reference each other forever
// (stack overflow). The abstract edge must itself be the break point.
const _abstractOnly = '''
interface Node {
  id: ID!
  next: Node!
}
type Item implements Node {
  id: ID!
  value: String!
  next: Node!
}
type Query { getItem(id: ID!): Item! }
''';

// Union variant: the closing edge is a union-typed field with no concrete
// back-edge on any member.
const _abstractOnlyUnion = '''
union Linkable = Item
type Item {
  id: ID!
  value: String!
  next: Linkable!
}
type Query { getItem(id: ID!): Item! }

query getItem {
  getItem {
    id
    value
    next { ... on Item { id value } }
  }
}
''';

void main() {
  group('abstract-only cycle — detection', () {
    test('Item is flagged cyclic and Item.next is the (abstract) back-edge', () {
      final g = parseAuto(_abstractOnly);
      expect(g.cyclicTypeNames, contains('Item'));
      expect(g.isBackEdgeField('Item', 'next'), isTrue,
          reason: 'the abstract edge must be broken — no concrete back-edge exists');
    });
  });

  group('abstract-only cycle — generation terminates', () {
    test('schema with auto-gen + all-fields fragments parses (no stack overflow)',
        () {
      expect(() => parseAuto(_abstractOnly), returnsNormally);
    });

    test('the all-fields fragment graph is acyclic: _all_fields_Item does not '
        'spread _all_fields_Node', () {
      final g = parseAuto(_abstractOnly);
      final fragName = GLGrammarExtension.allFieldsFragmentName('Item');
      final frag = g.fragments[fragName]!;
      final str = GLGraphqlSerializer(g).serializeFragmentDefinitionBase(frag);
      // The abstract back-edge is inline-bounded, not spread, so the Item
      // fragment never references the Node fragment (which would close the
      // fragment-reference cycle).
      expect(str.contains(GLGrammarExtension.allFieldsFragmentName('Node')),
          isFalse,
          reason: 'abstract back-edge must be inlined, not spread');
      // It is bounded inline through the concrete member instead.
      expect(str.contains('... on Item'), isTrue);
    });
  });

  group('abstract-only cycle — projected type', () {
    test('Item.next is forced nullable and typed as the interface', () {
      final g = parseAuto(_abstractOnly);
      final item = g.projectedTypes['Item']!;
      final next = item.fields.firstWhere((f) => f.name.token == 'next');
      expect(next.type.nullable, isTrue,
          reason: 'cyclic edge must be nullable (depth-independent shape)');
      expect(next.type.inlineType.token, 'Node');
    });

    test('Dart serialization: Item implements Node with Node? next', () {
      final g = parseAuto(_abstractOnly);
      final dart = DartSerializer(g, importPrefix: 'package:app/models')
          .doSerializeTypeDefinition(g.projectedTypes['Item']!);
      expect(dart, contains('class Item implements Node'));
      expect(dart, contains('final Node? next;'));
    });
  });

  group('abstract-only cycle — union variant', () {
    test('union-closed cycle is detected and the abstract edge is the break point',
        () {
      final g = GLParser()..parse(_abstractOnlyUnion);
      expect(g.cyclicTypeNames, contains('Item'));
      expect(g.isBackEdgeField('Item', 'next'), isTrue,
          reason: 'union back-edge is broken the same way as an interface one');
    });
  });
}
