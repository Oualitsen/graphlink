import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/java/java_spring_server_serializer.dart';
import 'package:test/test.dart';

void main() {
  const schema = '''
type Book {
  id: ID!
  title: String!
  year: Int!
}
type Query {
  book(id: ID!): Book
}
''';

  test('nullable result is computed once, not once for the null check and once for toJson', () {
    final g = GLParser(identityFields: ['id'], mode: CodeGenerationMode.server);
    g.parse(schema);

    final serializer = JavaSpringServerSerializer(g, packageName: 'com.example');
    final result = serializer.serializeController(g.controllers['BookServiceController']!);

    expect(RegExp(r'bookService\.book\(').allMatches(result), hasLength(1));
    expect(result, contains('Book __gl_result__ = bookService.book(id);'));
    expect(result, contains('import com.example.types.Book;'));
    expect(result, contains('return __gl_result__ == null ? null : __gl_result__.toJson();'));
  });
}
