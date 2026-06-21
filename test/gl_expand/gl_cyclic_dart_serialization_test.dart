import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';

GLParser parseAuto(String schema, {int defaultExpandDepth = 1}) => GLParser(
      generateAllFieldsFragments: true,
      autoGenerateQueries: true,
      defaultExpandDepth: defaultExpandDepth,
    )..parse(schema);

String dartFor(GLParser g, String typeName) =>
    DartSerializer(g, importPrefix: 'package:app/models')
        .doSerializeTypeDefinition(g.projectedTypes[typeName]!);

// Two-type cycle. The generated types must be depth-independent: one class per
// schema type, mutually recursive, both cyclic edges nullable.
const _authorBook = '''
type Author {
  id: ID!
  name: String!
  book: Book!
}
type Book {
  id: ID!
  title: String!
  author: Author!
}
type Query { getAuthor(id: ID!): Author! }
''';

// Self-cycle.
const _employee = '''
type Employee {
  id: ID!
  name: String!
  manager: Employee!
}
type Query { getEmployee(id: ID!): Employee! }
''';

void main() {
  group('two-type cycle — Dart serialization (Author ⇄ Book)', () {
    test('Author has a nullable Book edge', () {
      final dart = dartFor(parseAuto(_authorBook), 'Author');
      expect(dart, contains('class Author {'));
      expect(dart, contains('final String id;'));
      expect(dart, contains('final String name;'));
      expect(dart, contains('final Book? book;'));
      // Nullable edge → optional constructor param + null-aware (de)serialization.
      expect(dart, contains('this.book'));
      expect(dart, contains("'book': book?.toJson()"));
      expect(dart, contains(
          "book: json['book'] == null ? null : Book.fromJson(json['book'] as Map<String, dynamic>)"));
    });

    test('Book has a nullable Author edge', () {
      final dart = dartFor(parseAuto(_authorBook), 'Book');
      expect(dart, contains('class Book {'));
      expect(dart, contains('final Author? author;'));
      expect(dart, contains('this.author'));
      expect(dart, contains("'author': author?.toJson()"));
      expect(dart, contains(
          "author: json['author'] == null ? null : Author.fromJson(json['author'] as Map<String, dynamic>)"));
    });

    test('exactly one class per schema type (no depth-suffixed duplicates)', () {
      final g = parseAuto(_authorBook);
      final names = g.projectedTypes.keys
          .where((k) => !k.startsWith('GraphLink') &&
              !k.toLowerCase().endsWith('response'))
          .toList();
      expect(names, containsAll(['Author', 'Book']));
      // No Author_IdName / Book_2 style depth-bounded copies.
      expect(names.where((n) => n.startsWith('Author')).toList(), ['Author']);
      expect(names.where((n) => n.startsWith('Book')).toList(), ['Book']);
    });
  });

  group('self-cycle — Dart serialization (Employee)', () {
    test('Employee has a nullable self edge', () {
      final dart = dartFor(parseAuto(_employee), 'Employee');
      expect(dart, contains('class Employee {'));
      expect(dart, contains('final Employee? manager;'));
      expect(dart, contains(
          "manager: json['manager'] == null ? null : Employee.fromJson(json['manager'] as Map<String, dynamic>)"));
    });
  });
}
