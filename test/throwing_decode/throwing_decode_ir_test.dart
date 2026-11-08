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

  test('every object, interface and union validates the JSON it reads', () {
    for (final name in ['Pet', 'Hit', 'Dog', 'Cat', 'Owner', 'Shelter', 'Deep', 'Finder', 'Plain', 'Painted']) {
      expect(g.decodesWithThrows(name), isTrue, reason: name);
    }
  });

  test('cycles throw on both sides, whether or not they reach a dispatch', () {
    for (final name in ['Left', 'Right', 'Loop1', 'Loop2']) {
      expect(g.decodesWithThrows(name), isTrue, reason: name);
    }
  });

  test('enums and scalars never throw', () {
    for (final name in ['Color', 'String', 'ID', 'Boolean']) {
      expect(g.decodesWithThrows(name), isFalse, reason: name);
    }
  });

  test('generated response wrappers throw too', () {
    final wrappers = g.projectedTypes.keys.where((k) => k.toLowerCase().contains('response')).toList();
    expect(wrappers, isNotEmpty);
    for (final w in wrappers) {
      expect(g.decodesWithThrows(w), isTrue, reason: w);
    }
  });

  test('an interface that is only a synthetic implementation throws like any interface', () {
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
      expect(g2.decodesWithThrows(i.token), isTrue, reason: i.token);
    }
  });
}
