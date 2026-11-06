import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

const _schema = r'''
type Query { media: Media }
type Photo { id: ID! url: String! width: Int! }
type Clip { id: ID! secs: Int! }
union Media = Photo | Clip
''';

Set<String> _interfacesImplementedBy(GLParser g, String member) => g
    .projectedInterfaces.values
    .where((i) => i.implementations.any((m) => m.token == member))
    .map((i) => i.token)
    .toSet();

Set<String> _membersOf(GLParser g, String iface) =>
    g.projectedInterfaces[iface]!.implementations.map((m) => m.token).toSet();

void main() {
  test('two selections of one union with different members get separate interfaces', () {
    final g = GLParser(generateAllFieldsFragments: true)
      ..parse('''
$_schema
query a { media { ... on Photo { id } } }
query b { media { ... on Photo { id url width } } }
''');

    final withPartial = _interfacesImplementedBy(g, 'Photo_Id');
    final withFull = _interfacesImplementedBy(g, 'Photo');
    expect(withPartial, isNotEmpty);
    expect(withFull, isNotEmpty);
    expect(withPartial.intersection(withFull), isEmpty);
  });

  test('an interface only lists the members of its own selection', () {
    final g = GLParser(generateAllFieldsFragments: true)
      ..parse('''
$_schema
query a { media { ... on Photo { id } ... on Clip { id } } }
query b { media { ... on Photo { id url width } } }
''');

    final partial = _interfacesImplementedBy(g, 'Photo_Id').single;
    expect(_membersOf(g, partial), {'Photo_Id', 'Clip_Id'});
    final full = _interfacesImplementedBy(g, 'Photo').single;
    expect(_membersOf(g, full), {'Photo'});
  });

  test('selecting every member in full keeps the schema name', () {
    final g = GLParser(generateAllFieldsFragments: true)
      ..parse('''
$_schema
query c { media { ... on Photo { id url width } ... on Clip { id secs } } }
''');

    expect(_membersOf(g, 'Media'), {'Photo', 'Clip'});
  });

  test('identical selections of the same union share one interface', () {
    final g = GLParser(generateAllFieldsFragments: true)
      ..parse('''
$_schema
query a { media { ... on Photo { id } } }
query b { media { ... on Photo { id } } }
''');

    expect(_interfacesImplementedBy(g, 'Photo_Id'), hasLength(1));
  });
}
