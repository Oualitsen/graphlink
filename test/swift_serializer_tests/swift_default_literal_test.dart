import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/token_info.dart';
import 'package:graphlink/src/serializers/swift_serializer.dart';
import 'package:test/test.dart';

SwiftSerializer _serializer(GLParser g) => SwiftSerializer(g, importPrefix: 'GraphLinkGenerated');

void main() {
  group('serializeDefaultLiteral', () {
    late GLParser g;
    late SwiftSerializer s;

    setUp(() {
      g = GLParser()..parse('''
        enum Role { admin user }
        input AddressInput { city: String! }
      ''');
      s = _serializer(g);
    });

    GLType stringType() => g.inputs['AddressInput']!.fields.first.type;

    test('null value', () {
      expect(s.serializeDefaultLiteral(stringType(), null), 'nil');
    });

    test('int for a non-float type', () {
      expect(s.serializeDefaultLiteral(stringType(), 3), '3');
    });

    test('int coerced to a float type emits a Double literal', () {
      final floatType = GLType(TokenInfo.ofString('Float'), false);
      expect(s.serializeDefaultLiteral(floatType, 3), '3.0');
    });

    test('NaN/Infinity use static members, not bare literals', () {
      final floatType = GLType(TokenInfo.ofString('Float'), false);
      expect(s.serializeDefaultLiteral(floatType, double.nan), 'Double.nan');
      expect(s.serializeDefaultLiteral(floatType, double.infinity), 'Double.infinity');
      expect(s.serializeDefaultLiteral(floatType, double.negativeInfinity), '-Double.infinity');
    });

    test('bool', () {
      expect(s.serializeDefaultLiteral(stringType(), true), 'true');
    });

    test('quoted string literal has quotes stripped then re-added', () {
      expect(s.serializeDefaultLiteral(stringType(), '"hello"'), '"hello"');
    });

    test('list literal', () {
      final listType = GLListType(GLType(TokenInfo.ofString('String'), false), false);
      expect(s.serializeDefaultLiteral(listType, ['"a"', '"b"']), '["a", "b"]');
    });

    test('enum default resolves to a fully-qualified case reference', () {
      final roleType = GLType(TokenInfo.ofString('Role'), false);
      expect(s.serializeDefaultLiteral(roleType, 'admin'), 'Role.admin');
    });
  });
}
