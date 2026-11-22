import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/dart/dart_serializer.dart';
import 'package:graphlink/src/serializers/go/go_serializer.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:graphlink/src/serializers/swift/swift_serializer.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
type Query { noop: String }

input CreateArticleInput @glMapsTo(type: "Article") {
  title: String!
  authorId: ID!
}

type Article
  @glMapsTo(type: "ArticleSummary")
  @glMapsTo(type: "UpdateArticleInput") {
  id: ID!
  title: String! @glMapField(to: "headline", target: "ArticleSummary")
  authorId: ID!
}

type ArticleSummary {
  id: ID!
  headline: String!
}

input UpdateArticleInput {
  id: ID!
  title: String!
  published: Boolean!
}
''';

GLParser _parse(String schema, {CodeGenerationMode mode = CodeGenerationMode.server, bool generateMappers = false}) =>
    GLParser(mode: mode, generateMappers: generateMappers)..parse(schema);

void _rejects(String schema, String message) {
  expect(
    () => _parse(schema),
    throwsA(isA<ParseException>().having((e) => e.errorMessage, 'errorMessage', contains(message))),
  );
}

void main() {
  group('declared on a type', () {
    test('generates one to method per target and no from method', () {
      final g = _parse(_schema);
      final out = DartSerializer(g, importPrefix: '').serializeTypeDefinition(g.types['Article']!);
      expect(out, contains('ArticleSummary toArticleSummary()'));
      expect(out, contains('return ArticleSummary(id: id, headline: title);'));
      expect(out, contains('UpdateArticleInput toUpdateArticleInput({'));
      expect(out, contains('required bool published'));
      expect(out, contains('return UpdateArticleInput(id: id, title: title, published: published);'));
      expect(out, isNot(contains('fromArticle')));
    });

    test('input to type still works and has no from method', () {
      final g = _parse(_schema);
      final out = DartSerializer(g, importPrefix: '').serializeInputDefinition(g.inputs['CreateArticleInput']!);
      expect(out, contains('Article toArticle({'));
      expect(out, isNot(contains('fromArticle')));
    });

    test('an untargeted @glMapField does not rename for another target', () {
      final g = _parse(_schema);
      final out = DartSerializer(g, importPrefix: '').serializeTypeDefinition(g.types['Article']!);
      expect(out, contains('title: title'));
    });
  });

  group('client opt-in', () {
    const schema = '''
type Query { noop: String }
input DraftInput @glMapsTo(type: "PublishedInput") { title: String! }
input PublishedInput { title: String! }
''';

    test('a client generates no mapper by default', () {
      final g = _parse(schema, mode: CodeGenerationMode.client);
      final out = DartSerializer(g, importPrefix: '').serializeInputDefinition(g.inputs['DraftInput']!);
      expect(out, isNot(contains('toPublishedInput')));
    });

    test('generateMappers turns them on', () {
      final g = _parse(schema, mode: CodeGenerationMode.client, generateMappers: true);
      final out = DartSerializer(g, importPrefix: '').serializeInputDefinition(g.inputs['DraftInput']!);
      expect(out, contains('PublishedInput toPublishedInput()'));
    });
  });

  group('validation', () {
    test('a source cannot map to itself', () {
      _rejects('type Query { a: String }\ntype A @glMapsTo(type: "A") { x: String }', 'cannot target itself');
    });

    test('the same target twice is an error', () {
      _rejects('type Query { a: String }\ntype A @glMapsTo(type: "B") @glMapsTo(type: "B") { x: String }\ntype B { x: String }',
          'declared twice');
    });

    test('an enum target is an error', () {
      _rejects('type Query { a: String }\nenum E { X }\ntype A @glMapsTo(type: "E") { x: String }',
          'does not exist or is not a type or input');
    });

    test('@glMapField without target: is an error when several targets are declared', () {
      _rejects('''
type Query { a: String }
type A @glMapsTo(type: "B") @glMapsTo(type: "C") { x: String @glMapField(to: "y") }
type B { y: String }
type C { y: String }
''', 'needs target:');
    });

    test('@glMapField(target:) must be one of the declared targets', () {
      _rejects('''
type Query { a: String }
type A @glMapsTo(type: "B") { x: String @glMapField(to: "y", target: "C") }
type B { y: String }
type C { y: String }
''', 'is not one of');
    });

    test('@glMapField on a field with arguments is an error', () {
      _rejects('''
type Query { a: String }
type A @glMapsTo(type: "B") { x(n: Int): String @glMapField(to: "y") }
type B { y: String }
''', 'never take part');
    });

    test('two targets generating the same method name are an error', () {
      final g = _parse('''
type Query { a: String }
type A @glMapsTo(type: "B") @glMapsTo(type: "B2") { x: String }
type B { x: String }
type B2 { x: String }
''');
      g.types['B2']!.codeName = 'B';
      expect(
        () => DartSerializer(g, importPrefix: '').serializeTypeDefinition(g.types['A']!),
        throwsA(isA<ParseException>()),
      );
    });
  });

  group('every language emits to methods on a type', () {
    const schema = '''
type Query { noop: String }
type Article @glMapsTo(type: "ArticleSummary") { id: ID! title: String! }
type ArticleSummary { id: ID! title: String! }
''';

    test('Kotlin', () {
      final g = _parse(schema);
      expect(KotlinSerializer(g, importPrefix: '').serializeTypeDefinition(g.types['Article']!),
          contains('fun toArticleSummary(): ArticleSummary'));
    });
    test('Swift', () {
      final g = _parse(schema);
      expect(SwiftSerializer(g, importPrefix: '').serializeTypeDefinition(g.types['Article']!),
          contains('func toArticleSummary() -> ArticleSummary'));
    });
    test('Python', () {
      final g = _parse(schema);
      expect(PythonSerializer(g, importPrefix: '').serializeTypeDefinition(g.types['Article']!),
          contains('def to_article_summary(self)'));
    });
    test('Go', () {
      final g = _parse(schema);
      expect(GoSerializer(g, importPrefix: '').serializeTypeDefinition(g.types['Article']!),
          contains('func (v Article) ToArticleSummary() ArticleSummary'));
    });
    test('TypeScript puts the function in the type namespace', () {
      final g = _parse(schema);
      final out = TypeScriptSerializer(g, importPrefix: '').serializeTypeDefinition(g.types['Article']!);
      expect(out, contains('export namespace Article'));
      expect(out, contains('export function toArticleSummary(obj: Article): ArticleSummary'));
      expect(out, contains('id: obj.id'));
    });
    test('TypeScript maps nested and list fields through the nested mapping', () {
      const nested = '''
type Query { noop: String }
type Tag @glMapsTo(type: "TagInput") { name: String! }
input TagInput { name: String! }
type Post @glMapsTo(type: "PostInput") { tags: [Tag!]! main: Tag }
input PostInput { tags: [TagInput!]! main: TagInput }
''';
      final g = _parse(nested);
      final out = TypeScriptSerializer(g, importPrefix: '').serializeTypeDefinition(g.types['Post']!);
      expect(out, contains('tags: obj.tags.map((e0) => Tag.toTagInput(e0))'));
      expect(out, contains('main: obj.main == null ? obj.main : Tag.toTagInput(obj.main)'));
    });
  });

  test('mutual mappings do not recurse forever', () {
    const schema = '''
type Query { noop: String }
type A @glMapsTo(type: "B") { id: ID! b: B }
type B @glMapsTo(type: "A") { id: ID! a: A }
''';
    final g = _parse(schema);
    expect(DartSerializer(g, importPrefix: '').serializeTypeDefinition(g.types['A']!), contains('toB('));
  });
}
