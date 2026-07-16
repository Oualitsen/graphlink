import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/swift_serializer.dart';
import 'package:test/test.dart';

SwiftSerializer _serializer(GLParser g) => SwiftSerializer(g, importPrefix: 'GraphLinkGenerated');

void main() {
  group('serializeFieldDeprecation', () {
    late GLParser g;
    late SwiftSerializer s;

    setUp(() {
      g = GLParser()..parse('''
        type User {
          id: ID!
          name: String! @deprecated(reason: "use fullName instead")
          legacy: String! @deprecated
        }
      ''');
      s = _serializer(g);
    });

    test('non-deprecated field returns empty string', () {
      final f = g.types['User']!.fields.firstWhere((f) => f.name.token == 'id');
      expect(s.serializeFieldDeprecation(f), '');
    });

    test('deprecated field with reason emits @available message', () {
      final f = g.types['User']!.fields.firstWhere((f) => f.name.token == 'name');
      expect(s.serializeFieldDeprecation(f), '@available(*, deprecated, message: "use fullName instead")\n');
    });

    test('deprecated field with no reason falls back to default message', () {
      final f = g.types['User']!.fields.firstWhere((f) => f.name.token == 'legacy');
      expect(s.serializeFieldDeprecation(f), '@available(*, deprecated, message: "No longer supported")\n');
    });
  });

  group('serializeEnumValueDeprecation', () {
    late GLParser g;
    late SwiftSerializer s;

    setUp(() {
      g = GLParser()..parse('''
        enum Status {
          active
          inactive @deprecated(reason: "removed in v2")
        }
      ''');
      s = _serializer(g);
    });

    test('non-deprecated value returns empty string', () {
      final v = g.enums['Status']!.values.firstWhere((v) => v.codeName == 'active');
      expect(s.serializeEnumValueDeprecation(v), '');
    });

    test('deprecated value emits @available message, no trailing newline', () {
      final v = g.enums['Status']!.values.firstWhere((v) => v.codeName == 'inactive');
      expect(s.serializeEnumValueDeprecation(v), '@available(*, deprecated, message: "removed in v2")');
    });
  });
}
