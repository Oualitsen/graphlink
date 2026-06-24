import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';

/// `@glMapsTo` generates `toX()` / `fromX()` methods mapping between two
/// generated Kotlin classes via named arguments. A keyword field (`object`)
/// must be emitted as the sanitized `object_` on both sides.
void main() {
  const schema = '''
    type Address { object: String! city: String! }
    input CreateAddressInput @glMapsTo(type: "Address") { object: String! city: String! }
    type Query { noop: String }
  ''';

  String _out() {
    final g = GLParser(
      reservedWords: kotlinReservedWords,
      mode: CodeGenerationMode.server,
    )..parse(schema);
    return KotlinSerializer(g, importPrefix: "", generateJsonMethods: true)
        .serializeInputDefinition(g.inputs['CreateAddressInput']!);
  }

  test("toAddress() maps the keyword field via the sanitized identifier", () {
    expect(_out(), contains("object_ = object_"));
  });

  test("fromAddress() maps the keyword field via the sanitized identifier", () {
    expect(_out(), contains("object_ = address.object_"));
  });
}
