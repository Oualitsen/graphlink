import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_serializer.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_serializer.dart';
import 'package:test/test.dart';

import 'error_test_support.dart';

GLParser _parser() => GLParser(naming: NamingConvention.kotlin, reservedWords: kotlinReservedWords)..parse(errorSchema);

KotlinSerializer _serializer(GLParser g) => KotlinSerializer(g, importPrefix: 'com.example');

String _error(String name) {
  final g = _parser();
  return _serializer(g).serializeErrorDefinition(g.errors[name]!);
}

void main() {
  group('Kotlin error class', () {
    test('is a plain class on the runtime base and imports it', () {
      final out = _error('ArticleNotFound');
      expect(out, contains('import com.example.client.GraphLinkDomainError'));
      expect(out, isNot(contains('GraphLinkError')));
      final flatOut = flat(out);
      expect(flatOut, contains('class ArticleNotFound('));
      expect(flatOut, contains(') : GraphLinkDomainError(message)'));
      expect(flatOut, isNot(contains('data class')));
    });

    test('typed fields are constructor vals and the message is forwarded', () {
      final out = flat(_error('TitleTaken'));
      expect(out, contains('val title: String,'));
      expect(out, contains('val suggestions: List<String>? = null,'));
      expect(out, contains('message: String = "",'));
    });

    test('an error without fields only has the message', () {
      final out = flat(_error('Forbidden'));
      expect(out, contains('class Forbidden( message: String = "", ) : GraphLinkDomainError(message)'));
    });

    test('fromJson lives in the companion and decodes a map', () {
      final out = flat(_error('TitleTaken'));
      expect(out, contains('companion object {'));
      expect(out, contains('fun fromJson(map: Map<String, Any?>, message: String = ""): TitleTaken'));
      expect(out, contains('message = message'));
      expect(out, contains('title ='));
    });

    test('enum fields import and decode their enum', () {
      final out = _error('Banned');
      expect(out, contains('import com.example.enums.Reason'));
      expect(flat(out), contains('reason = Reason.fromJson('));
    });

    test('keyword fields get a safe identifier', () {
      final g = GLParser(naming: NamingConvention.kotlin, reservedWords: kotlinReservedWords)
        ..parse('type Odd @glError { object: String! } type Query { a: String }');
      final out = _serializer(g).serializeErrorDefinition(g.errors['Odd']!);
      expect(out, contains('val object_: String'));
      expect(out, contains('map["object"]'));
    });
  });

  group('Kotlin runtime base', () {
    test('is an open RuntimeException with only a message', () {
      final g = _parser();
      final model = KotlinClientSerializer(g, _serializer(g)).runtime.generateDomainErrorFile();
      final out = flat(model.body);
      expect(out, contains('open class GraphLinkDomainError(message: String = "") : RuntimeException(message)'));
      expect(out, isNot(contains('GraphLinkError')));
    });
  });
}
