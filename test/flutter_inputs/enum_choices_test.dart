import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/dart/dart_serializer.dart';
import 'package:graphlink/src/serializers/dart/flutter_inputs/flutter_inputs_serializer.dart';
import 'package:test/test.dart';

const schema = '''
enum Role { ADMIN USER }
input AccountInput { role: Role! roles: [Role!] }
type Query { x: String }
''';

String form({required bool tolerant, FlutterConfig config = const FlutterConfig(generateInputs: true)}) {
  final g = GLParser(naming: NamingConvention.dart, reservedWords: dartReservedWords, tolerantEnums: tolerant)
    ..parse(schema);
  return FlutterInputsSerializer(g, DartSerializer(g, importPrefix: ''), config, 'pkg')
      .serializeInputForm(g.inputs['AccountInput']!);
}

void main() {
  test('choices list the declared values, never the fallback', () {
    final out = form(tolerant: true);
    expect(out, contains('[Role.admin, Role.user].map('));
    expect(out, isNot(contains('Role.values')));
    expect(out, isNot(contains('unknownValue__')));
  });

  test('choices are the same without a fallback', () {
    expect(form(tolerant: false), contains('[Role.admin, Role.user].map('));
  });
}
