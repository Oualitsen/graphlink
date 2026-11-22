import 'package:graphlink/src/model/gl_collection_imports.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_serializer.dart';
import 'package:graphlink/src/serializers/java/java_imports.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:test/test.dart';

import 'error_test_support.dart';

GLParser _parser() => GLParser(
      naming: NamingConvention.java,
      reservedWords: javaReservedWords,
      collectionImports: const GLCollectionImports(listImport: JavaImports.list, mapImport: JavaImports.map),
    )..parse(errorSchema);

JavaSerializer _serializer(GLParser g) => JavaSerializer(g, importPrefix: 'com.example');

String _error(String name) {
  final g = _parser();
  return _serializer(g).serializeErrorDefinition(g.errors[name]!);
}

void main() {
  group('Java error class', () {
    test('is an unchecked exception through the runtime base and imports it', () {
      final out = _error('ArticleNotFound');
      expect(out, contains('import com.example.client.GraphLinkDomainError;'));
      expect(out, isNot(contains('GraphLinkError')));
      expect(flat(out), contains('public class ArticleNotFound extends GraphLinkDomainError {'));
    });

    test('typed fields are private finals with getters, no setters and no builder', () {
      final out = flat(_error('TitleTaken'));
      expect(out, contains('private final String title;'));
      expect(out, contains('private final List<String> suggestions;'));
      expect(out, contains('public String getTitle() {'));
      expect(out, contains('public List<String> getSuggestions() {'));
      expect(out, isNot(contains('setTitle')));
      expect(out, isNot(contains('Builder')));
    });

    test('the full constructor forwards the message and checks required fields for null', () {
      final out = flat(_error('TitleTaken'));
      expect(out, contains('public TitleTaken(String title, List<String> suggestions, String message) {'));
      expect(out, contains('super(message);'));
      expect(out, contains('Objects.requireNonNull(title);'));
      expect(out, contains('this.title = title;'));
      expect(out, contains('this.suggestions = suggestions;'));
    });

    test('a shorter constructor only takes the typed fields', () {
      final out = flat(_error('TitleTaken'));
      expect(out, contains('public TitleTaken(String title, List<String> suggestions) {'));
      expect(out, contains('this(title, suggestions, "");'));
    });

    test('an error without fields has a no-argument constructor', () {
      final out = flat(_error('Forbidden'));
      expect(out, contains('public Forbidden() {'));
      expect(out, contains('this("");'));
      expect(out, contains('public Forbidden(String message) {'));
    });

    test('fromJson decodes a map and takes the message', () {
      final out = flat(_error('TitleTaken'));
      expect(out, contains('@SuppressWarnings("unchecked")'));
      expect(out, contains('public static TitleTaken fromJson(Map<String, Object> json, String message) {'));
      expect(out, contains('return new TitleTaken('));
      expect(out, contains('json.get("title")'));
      expect(out, contains('message );'));
    });

    test('enum fields import their enum', () {
      expect(_error('Banned'), contains('import com.example.enums.Reason;'));
    });

    test('keyword fields get a safe identifier', () {
      final g = GLParser(
        naming: NamingConvention.java,
        reservedWords: javaReservedWords,
        collectionImports: const GLCollectionImports(listImport: JavaImports.list, mapImport: JavaImports.map),
      )..parse('type Odd @glError { class: String! } type Query { a: String }');
      final out = _serializer(g).serializeErrorDefinition(g.errors['Odd']!);
      expect(out, contains('private final String class_;'));
      expect(out, contains('json.get("class")'));
    });
  });

  group('Java runtime base', () {
    test('is a RuntimeException that never has a null message', () {
      final g = _parser();
      final model = JavaClientSerializer(g, _serializer(g)).runtime.generateDomainErrorFile();
      final out = flat(model.body);
      expect(out, contains('public class GraphLinkDomainError extends RuntimeException {'));
      expect(out, contains('public GraphLinkDomainError(String message) {'));
      expect(out, contains('super(message == null ? "" : message);'));
      expect(out, isNot(contains('GraphLinkError')));
    });

    test('compiles on Java 8: no List.of or Map.of', () {
      final g = _parser();
      final out = JavaClientSerializer(g, _serializer(g)).runtime.generateDomainErrorFile().body;
      expect(out, isNot(contains('List.of')));
      expect(out, isNot(contains('Map.of')));
    });
  });
}
