import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/serializers/swift_serializer.dart';
import 'package:test/test.dart';

SwiftSerializer _serializer(GLParser g) => SwiftSerializer(g, importPrefix: 'GraphLinkGenerated');

/// Trims every line so indentation never breaks containsAllInOrder checks.
Iterable<String> lines(String s) => s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

void main() {
  group('enum', () {
    late GLParser g;
    setUp(() {
      g = GLParser()..parse('enum Status { active inactive }');
    });

    test('declaration is a String, Sendable raw-value enum', () {
      final out = _serializer(g).doSerializeEnumDefinition(g.enums['Status']!);
      expect(lines(out), contains('public enum Status: String, Sendable {'));
    });

    test('cases carry explicit raw values', () {
      final out = _serializer(g).doSerializeEnumDefinition(g.enums['Status']!);
      expect(lines(out), containsAllInOrder([
        'case active = "active"',
        'case inactive = "inactive"',
      ]));
    });

    test('toJson returns rawValue', () {
      final out = _serializer(g).doSerializeEnumDefinition(g.enums['Status']!);
      expect(lines(out), containsAllInOrder([
        'public func toJson() -> String {',
        'return rawValue',
        '}',
      ]));
    });

    test('fromJson force-unwraps rawValue init', () {
      final out = _serializer(g).doSerializeEnumDefinition(g.enums['Status']!);
      expect(lines(out), containsAllInOrder([
        'public static func fromJson(_ value: String) -> Status {',
        'return Status(rawValue: value)!',
        '}',
      ]));
    });
  });

  group('enum with a Swift-reserved-word value', () {
    test('case name is renamed via codeName, raw value is the plain wire token', () {
      final g = GLParser(reservedWords: swiftReservedWords)..parse('enum SortOrder { default ascending }');
      final out = _serializer(g).doSerializeEnumDefinition(g.enums['SortOrder']!);
      expect(lines(out), contains('case default_ = "default"'));
      expect(lines(out), contains('case ascending = "ascending"'));
    });
  });

  group('enum with a deprecated value', () {
    test('emits @available above the case', () {
      final g = GLParser()..parse('''
        enum Status {
          active
          inactive @deprecated(reason: "removed in v2")
        }
      ''');
      final out = _serializer(g).doSerializeEnumDefinition(g.enums['Status']!);
      expect(lines(out), containsAllInOrder([
        '@available(*, deprecated, message: "removed in v2")',
        'case inactive = "inactive"',
      ]));
    });
  });
}
