import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/client_serializers/swift/swift_client_serializer.dart';
import 'package:graphlink/src/serializers/swift/swift_serializer.dart';
import 'package:test/test.dart';

import 'error_test_support.dart';

GLParser _parser() => GLParser(naming: NamingConvention.swift, reservedWords: swiftReservedWords)..parse(errorSchema);

String _error(String name) {
  final g = _parser();
  return SwiftSerializer(g, importPrefix: 'Generated').serializeErrorDefinition(g.errors[name]!);
}

void main() {
  group('Swift error class', () {
    test('is a final class on the runtime base', () {
      final out = flat(_error('ArticleNotFound'));
      expect(out, contains('public final class ArticleNotFound: GraphLinkDomainError, @unchecked Sendable {'));
    });

    test('typed fields are public lets set by an init that forwards the message', () {
      final out = flat(_error('TitleTaken'));
      expect(out, contains('public let title: String'));
      expect(out, contains('public let suggestions: [String]?'));
      expect(out, contains('public init( title: String, suggestions: [String]? = nil, message: String = "" ) {'));
      expect(out, contains('self.title = title'));
      expect(out, contains('self.suggestions = suggestions'));
      expect(out, contains('super.init(message: message)'));
    });

    test('an error without fields only has the message', () {
      final out = flat(_error('Forbidden'));
      expect(out, contains('public init( message: String = "" ) {'));
    });

    test('fromJson decodes a dictionary and takes the message', () {
      final out = flat(_error('TitleTaken'));
      expect(out, contains('public static func fromJson(_ map: [String: Any?], message: String = "") throws -> TitleTaken {'));
      expect(out, contains('return TitleTaken('));
      expect(out, contains('message: message'));
      expect(out, contains('title: try'));
    });

    test('enum fields are decoded with the enum', () {
      expect(flat(_error('Banned')), contains('reason: try Reason.fromJson('));
    });

    test('it is not a struct', () {
      expect(_error('TitleTaken'), isNot(contains('struct')));
    });
  });

  group('Swift runtime base', () {
    test('is an open Error class holding only a message', () {
      final g = _parser();
      final model = SwiftClientSerializer(g, SwiftSerializer(g, importPrefix: 'Generated')).generateDomainErrorFile();
      final out = flat(model.body);
      expect(out, contains('open class GraphLinkDomainError: Error, @unchecked Sendable {'));
      expect(out, contains('public let message: String'));
      expect(out, contains('public init(message: String = "")'));
      expect(out, isNot(contains('GraphLinkError')));
    });
  });
}
