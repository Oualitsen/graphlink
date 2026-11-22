import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart/dart_serializer.dart';
import 'package:test/test.dart';

import 'error_test_support.dart';

GLParser _parser() => GLParser(naming: NamingConvention.dart, reservedWords: dartReservedWords)..parse(errorSchema);

String _error(String name) {
  final g = _parser();
  return DartSerializer(g, importPrefix: 'package:app/gen').serializeErrorDefinition(g.errors[name]!);
}

void main() {
  group('Dart error class', () {
    test('extends the runtime base and imports it', () {
      final out = _error('ArticleNotFound');
      expect(out, contains("import 'package:app/gen/client/graph_link_domain_error.dart';"));
      expect(out, isNot(contains('graph_link_error.dart')));
      expect(flat(out), contains('class ArticleNotFound extends GraphLinkDomainError {'));
    });

    test('carries typed fields and a const constructor that forwards the message', () {
      final out = flat(_error('TitleTaken'));
      expect(out, contains('final String title;'));
      expect(out, contains('final List<String>? suggestions;'));
      expect(out, contains("const TitleTaken({required this.title, this.suggestions, String message = ''}) : super(message);"));
    });

    test('an error without fields only has the message', () {
      final out = flat(_error('Forbidden'));
      expect(out, contains("const Forbidden({String message = ''}) : super(message);"));
    });

    test('fromJson decodes a map and takes the message', () {
      final out = flat(_error('TitleTaken'));
      expect(out, contains("static TitleTaken fromJson(Map<String, dynamic> json, {String message = ''})"));
      expect(out, contains("title: json['title'] as String"));
      expect(out, contains('message: message'));
    });

    test('enum and custom scalar fields are decoded and their types imported', () {
      final out = _error('Banned');
      expect(out, contains("import 'package:app/gen/enums/reason.dart';"));
      expect(flat(out), contains("reason: Reason.fromJson(json['reason'] as String)"));
    });

    test('it is not a data class: no toJson and no equality', () {
      final out = _error('TitleTaken');
      expect(out, isNot(contains('toJson')));
      expect(out, isNot(contains('hashCode')));
    });
  });

  group('Dart runtime base', () {
    test('implements Exception and holds only a message', () {
      final g = _parser();
      final model = DartClientSerializer(g, DartSerializer(g, importPrefix: 'x')).runtime.generateDomainErrorFile();
      final out = flat(model.body);
      expect(out, contains('class GraphLinkDomainError implements Exception {'));
      expect(out, contains('final String message;'));
      expect(out, contains("const GraphLinkDomainError([this.message = '']);"));
      expect(out, isNot(contains('GraphLinkError')));
    });
  });
}
