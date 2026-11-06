import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

const _schema = '''
type Photo { id: ID! size: Int! url: String! }
type Video { id: ID! size: String! seconds: Int! }
type Doc { id: ID! pages: Int! }
union Media = Photo | Video
union Safe = Photo | Doc
interface Item { id: ID! name: String }
type Book implements Item { id: ID! name: String! }
type Pen implements Item { id: ID! name: String }
type Gallery { cover: Media  title: String }
type Query {
  media: Media
  safe: Safe
  item: Item
  gallery: Gallery
  photo: Photo
}
''';

GLParser _parse([String extra = '']) => GLParser(
    generateAllFieldsFragments: true, autoGenerateQueries: true)
  ..parse('$_schema\n$extra');

bool _hasQuery(GLParser g, String name) =>
    g.queries.containsKey(GLOperationKey(name, GLQueryType.query));

void main() {
  test('a query returning a union whose members clash is not generated', () {
    final g = _parse();
    expect(_hasQuery(g, 'media'), isFalse);
    final skipped = g.skippedAutoQueries.firstWhere((s) => s.name == 'media');
    final conflict = skipped.conflict!;
    expect(conflict.abstractType, 'Media');
    expect(conflict.field, 'size');
    expect({conflict.firstMember, conflict.secondMember}, {'Photo', 'Video'});
  });

  test('a query reaching the union through an object is not generated', () {
    final g = _parse();
    expect(_hasQuery(g, 'gallery'), isFalse);
    expect(g.skippedAutoQueries.firstWhere((s) => s.name == 'gallery').conflict!.abstractType, 'Media');
  });

  test('a nullability difference on an interface field is a clash', () {
    final g = _parse();
    expect(_hasQuery(g, 'item'), isFalse);
    final conflict = g.skippedAutoQueries.firstWhere((s) => s.name == 'item').conflict!;
    expect(conflict.abstractType, 'Item');
    expect(conflict.field, 'name');
  });

  test('queries that cannot reach a clash are still generated', () {
    final g = _parse();
    expect(_hasQuery(g, 'safe'), isTrue);
    expect(_hasQuery(g, 'photo'), isTrue);
  });

  test('a hand-written query with an alias on the same union is accepted', () {
    final g = _parse('query m { media { ... on Photo { size } ... on Video { videoSize: size } } }');
    expect(g.queries.containsKey(const GLOperationKey('m', GLQueryType.query)), isTrue);
  });

  test('spreading _all_fields on a clashing union is rejected with a way out', () {
    expect(
        () => _parse('query m { media { ..._all_fields } }'),
        throwsA(isA<ParseException>().having((e) => e.toString(), 'message',
            allOf(contains('Media'), contains('size'), contains('alias')))));
  });

  test('spreading _all_fields on an object that reaches a clash is rejected', () {
    expect(() => _parse('query g { gallery { ..._all_fields } }'), throwsA(isA<ParseException>()));
  });

  test('spreading _all_fields on a safe type is accepted', () {
    expect(() => _parse('query s { safe { ..._all_fields } }'), returnsNormally);
  });

  test('pruning leaves no orphan synthetic input', () {
    final g = _parse();
    expect(g.inputs.keys.where((k) => k.toLowerCase().startsWith('media')), isEmpty);
  });
}
