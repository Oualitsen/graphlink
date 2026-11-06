import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
import 'package:test/test.dart';

void main() {
  const schema = r'''
type Query { media: Media }
type Photo { id: ID! url: String! width: Int! }
type Clip { id: ID! secs: Int! }
union Media = Photo | Clip
query a { media { ... on Photo { id } ... on Clip { secs } } }
''';

  late GLParser g;
  late TypeScriptSerializer serializer;

  setUp(() {
    g = GLParser(generateAllFieldsFragments: true)..parse(schema);
    serializer = TypeScriptSerializer(g, importPrefix: '');
  });

  test('a projected union member is tagged and dispatched with the wire __typename', () {
    final union = g.projectedInterfaces.values.firstWhere(
        (i) => i.implementations.any((m) => m.token == 'Photo_Id'));
    final output = serializer.serializeTypeDefinition(union);

    expect(output, contains('case "Photo":'));
    expect(output, contains('case "Clip":'));
    expect(output, isNot(contains('case "Photo_Id"')));
  });

  test('a projected type writes the wire __typename', () {
    final output = serializer.serializeTypeDefinition(g.projectedTypes['Photo_Id']!);

    expect(output, contains("readonly __typename: 'Photo'"));
    expect(output, contains('"__typename": "Photo"'));
    expect(output, contains("__typename: 'Photo'"));
  });
}
