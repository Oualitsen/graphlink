import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/serializers/swift_serializer.dart';
import 'package:test/test.dart';

SwiftSerializer _serializer(GLParser g) => SwiftSerializer(g, importPrefix: 'GraphLinkGenerated');

void main() {
  group('doSerializeField', () {
    late GLParser g;
    late SwiftSerializer s;

    setUp(() {
      // reservedWords must be supplied explicitly — GLParser defaults to an
      // empty set, so codeName renaming (default -> default_) only fires
      // when the target language's reserved-word set is passed in, exactly
      // as grammar_factory.dart does for real generation.
      g = GLParser(reservedWords: swiftReservedWords)..parse('''
        type User {
          id: ID!
          name: String
          legacy: String @deprecated(reason: "unused")
          default: String!
        }
      ''');
      s = _serializer(g);
    });

    test('immutable non-nullable field uses `let` with no default', () {
      final f = g.types['User']!.fields.firstWhere((f) => f.name.token == 'id');
      expect(s.doSerializeField(f, true, true), 'public let id: String');
    });

    test('mutable non-nullable field uses `var`', () {
      final f = g.types['User']!.fields.firstWhere((f) => f.name.token == 'id');
      expect(s.doSerializeField(f, false, true), 'public var id: String');
    });

    test('nullable field gets `= nil` default', () {
      final f = g.types['User']!.fields.firstWhere((f) => f.name.token == 'name');
      expect(s.doSerializeField(f, true, true), 'public let name: String? = nil');
    });

    test('deprecated field is prefixed with @available', () {
      final f = g.types['User']!.fields.firstWhere((f) => f.name.token == 'legacy');
      expect(s.doSerializeField(f, true, true),
          '@available(*, deprecated, message: "unused")\npublic let legacy: String? = nil');
    });

    test('reserved-word field name is renamed via codeName (default -> default_)', () {
      final f = g.types['User']!.fields.firstWhere((f) => f.name.token == 'default');
      expect(f.codeName, 'default_');
      expect(s.doSerializeField(f, true, true), 'public let default_: String');
    });
  });
}
