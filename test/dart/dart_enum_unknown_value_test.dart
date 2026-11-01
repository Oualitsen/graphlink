import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';

String _enumSource({required bool tolerant}) {
  final g = GLParser(tolerantEnums: tolerant)
    ..parse('enum Gender { male female } type Query { gender: Gender }');
  return DartSerializer(g, importPrefix: '').doSerializeEnumDefinition(g.enums['Gender']!);
}

void main() {
  test('the fallback case throws without an unreachable break after it', () {
    final source = _enumSource(tolerant: true);

    expect(source, contains('throw StateError("Gender.unknownValue__ cannot be serialized");'));
    expect(RegExp(r'throw[^;]*;\s*break;').hasMatch(source), isFalse);
  });

  test('cases that return still carry no break', () {
    expect(RegExp(r'return "[a-z]+";\s*break;').hasMatch(_enumSource(tolerant: true)), isFalse);
  });
}
