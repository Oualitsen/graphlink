import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

const _schema = r'''
type Query { node(id: ID!): Node  entity(id: ID!): Entity }
interface Node { id: ID! }
interface Entity implements Node { id: ID! createdBy: String! }
type Article implements Entity & Node { id: ID! createdBy: String! title: String! }
type Comment implements Entity & Node { id: ID! createdBy: String! text: String! }
''';

GLParser _parse(String operations) =>
    GLParser(generateAllFieldsFragments: true)..parse('$_schema\n$operations');

Iterable<GLInterfaceDefinition> _synthetic(GLParser g, String declared) =>
    g.projectedInterfaces.values.where((i) =>
        i.derivedFromType?.token == declared && i.syntheticImplementation != null);

Set<String> _names(Iterable<dynamic> fields) =>
    fields.map((f) => f.name.token as String).toSet();

List<Set<String>> _dispatchingInterfaces(GLParser g) => g.projectedInterfaces.values
    .where((i) => i.syntheticImplementation == null)
    .map((i) => i.implementations.map((m) => m.token).toSet())
    .where((members) => members.any((m) => m.startsWith('Article') || m.startsWith('Comment')))
    .toList();

Set<String> _projectedMembers(GLParser g) => g.projectedTypes.keys
    .where((t) => t.startsWith('Article') || t.startsWith('Comment'))
    .toSet();

void main() {
  test('a selection naming no implementer is an interface with one synthetic implementation', () {
    final g = _parse('query q(\$id: ID!) { node(id: \$id) { id } }');

    final iface = _synthetic(g, 'Node').single;
    expect(iface.token, 'Node_Id');
    expect(_names(iface.fields), {'id'});
    expect(iface.implementations, hasLength(1));
    final impl = iface.syntheticImplementation!;
    expect(impl.token, 'Node_Id_Impl');
    expect(_names(impl.fields), {'id'});
    expect(g.projectedTypes[impl.token], same(impl));
  });

  test('the implementation carries no wire type name', () {
    final g = _parse('query q(\$id: ID!) { node(id: \$id) { id } }');

    expect(_synthetic(g, 'Node').single.syntheticImplementation!.jsonTypeName, isNull);
  });

  test('it creates no dispatching interface and no member types', () {
    final g = _parse('query q(\$id: ID!) { node(id: \$id) { id } }');

    expect(_dispatchingInterfaces(g), isEmpty);
    expect(_projectedMembers(g), isEmpty);
  });

  test('every interface field selected still names no implementer', () {
    final g = _parse('query q(\$id: ID!) { entity(id: \$id) { id createdBy } }');

    final iface = _synthetic(g, 'Entity').single;
    expect(_names(iface.fields), {'id', 'createdBy'});
    expect(_names(iface.syntheticImplementation!.fields), {'id', 'createdBy'});
    expect(_dispatchingInterfaces(g), isEmpty);
    expect(_projectedMembers(g), isEmpty);
  });

  test('an inline fragment on the interface itself names no implementer either', () {
    final g = _parse('query q(\$id: ID!) { node(id: \$id) { ... on Node { id } } }');

    expect(_synthetic(g, 'Node'), hasLength(1));
    expect(_projectedMembers(g), isEmpty);
  });

  test('naming one implementer keeps the dispatching interface and the member types', () {
    final g = _parse(r'query q($id: ID!) { node(id: $id) { id ... on Article { title } } }');

    expect(_synthetic(g, 'Node'), isEmpty);
    expect(_dispatchingInterfaces(g).map((m) => (m.toList()..sort()).join(',')),
        contains('Article_IdTitle,Comment_Id'));
    expect(g.projectedTypes['Article_IdTitle']!.jsonTypeName, 'Article');
  });

  test('two identical selections share one interface and one implementation', () {
    final g = _parse(r'''
query a($id: ID!) { node(id: $id) { id } }
query b($id: ID!) { node(id: $id) { id } }
''');

    expect(_synthetic(g, 'Node'), hasLength(1));
  });

  test('the interface and its implementation never share a name with another projection', () {
    const bare = r'query a($id: ID!) { node(id: $id) { id } }';
    const dispatching =
        r'query b($id: ID!) { entity(id: $id) { id createdBy ... on Article { title } } }';
    for (final operations in ['$bare\n$dispatching', '$dispatching\n$bare']) {
      final g = _parse(operations);
      final shared =
          g.projectedTypes.keys.toSet().intersection(g.projectedInterfaces.keys.toSet());
      expect(shared, isEmpty, reason: operations);
    }
  });
}
