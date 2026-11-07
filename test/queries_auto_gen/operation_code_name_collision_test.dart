import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:test/test.dart';

const _schema = '''
  type Photo { id: ID! url: String! }
  type Query { photo(id: ID!): Photo }
  type Mutation { removePhoto(id: ID!): Photo }

  query Photo { photo(id: "p1") { id } }
''';

GLParser _parse() => GLParser(
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
      naming: NamingConvention.dart,
    )..parse(_schema);

void main() {
  test('operations whose names only differ by case get distinct code names', () {
    final g = _parse();
    final names = g.queries.values.where((q) => q.type.name == 'query').map((q) => q.codeName).toList();
    expect(names.toSet(), hasLength(names.length), reason: '$names');
  });

  test('the generated operation keeps its name, the hand-written one yields', () {
    final g = _parse();
    final generated = g.queries.values.firstWhere((q) => q.token == 'photo');
    final custom = g.queries.values.firstWhere((q) => q.token == 'Photo');
    expect(generated.codeName, 'photo');
    expect(custom.codeName, 'photo2');
  });

  test('the wire name of the hand-written operation is untouched', () {
    final custom = _parse().queries.values.firstWhere((q) => q.token == 'Photo');
    expect(custom.token, 'Photo');
  });

  test('the response types of the two operations do not collide', () {
    final g = _parse();
    final types = g.queries.values
        .where((q) => q.type.name == 'query')
        .map((q) => q.getGeneratedTypeDefinition().codeName)
        .toList();
    expect(types.toSet(), hasLength(types.length), reason: '$types');
  });
}
