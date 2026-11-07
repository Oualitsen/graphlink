import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_throwing_decode_extension.dart';
import 'package:test/test.dart';

const _schema = '''
interface Pet { id: ID! }
type Dog implements Pet { id: ID! barks: Boolean! }
type Cat implements Pet { id: ID! }
union Hit = Dog | Cat

type Owner { id: ID! pet: Pet }
type Shelter { owners: [Owner!]! }
type Deep { shelter: Shelter }
type Finder { hits: [Hit!]! }

type Plain { id: ID! name: String }
enum Color { RED }
type Painted { color: Color! plain: Plain }

type Left { right: Right pet: Pet }
type Right { left: Left }

type Loop1 { other: Loop2 }
type Loop2 { other: Loop1 }

type Query {
  owner: Owner
  shelter: Shelter
  deep: Deep
  finder: Finder
  plain: Plain
  painted: Painted
  left: Left
  loop: Loop1
  pets: [Pet!]!
  hit: Hit
}
''';

GLParser _parse() => GLParser(autoGenerateQueries: true, generateAllFieldsFragments: true)..parse(_schema);

void main() {
  final g = _parse();

  test('an interface or union with implementations is a dispatch that can fail', () {
    expect(g.decodesWithThrows('Pet'), isTrue);
    expect(g.decodesWithThrows('Hit'), isTrue);
  });

  test('a type holding an interface or union field throws', () {
    expect(g.decodesWithThrows('Owner'), isTrue);
    expect(g.decodesWithThrows('Finder'), isTrue);
  });

  test('throwing propagates through lists and through other objects', () {
    expect(g.decodesWithThrows('Shelter'), isTrue);
    expect(g.decodesWithThrows('Deep'), isTrue);
  });

  test('members of a dispatch, plain types, enums and scalars do not throw', () {
    for (final name in ['Dog', 'Cat', 'Plain', 'Painted', 'Color', 'String', 'ID', 'Boolean']) {
      expect(g.decodesWithThrows(name), isFalse, reason: name);
    }
  });

  test('a cycle that reaches a dispatch throws on both sides; one that does not stays plain', () {
    expect(g.decodesWithThrows('Left'), isTrue);
    expect(g.decodesWithThrows('Right'), isTrue);
    expect(g.decodesWithThrows('Loop1'), isFalse);
    expect(g.decodesWithThrows('Loop2'), isFalse);
  });

  test('generated response wrappers follow their payload', () {
    final wrappers = g.projectedTypes.keys.where((k) => k.toLowerCase().contains('response')).toList();
    expect(wrappers, isNotEmpty);
    final owner = wrappers.firstWhere((k) => k.toLowerCase().contains('owner'));
    final plain = wrappers.firstWhere((k) => k.toLowerCase().contains('plain'));
    expect(g.decodesWithThrows(owner), isTrue, reason: owner);
    expect(g.decodesWithThrows(plain), isFalse, reason: plain);
  });

  test('an interface that is only a synthetic implementation follows that implementation', () {
    final g2 = GLParser(autoGenerateQueries: true, generateAllFieldsFragments: true)
      ..parse('''
interface Node { id: ID! }
type Article implements Node { id: ID! title: String }
type Query { node(id: ID!): Node }
query nodeId(\$id: ID!) { node(id: \$id) { id } }
''');
    final synthetic = g2.projectedInterfaces.values.where((i) => i.syntheticImplementation != null).toList();
    expect(synthetic, isNotEmpty);
    for (final i in synthetic) {
      expect(g2.decodesWithThrows(i.token), isFalse, reason: i.token);
    }
  });
}
