import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';

/// `@glMapsTo` generates `toX()` / `fromX()` methods mapping between two
/// generated Java classes. Builder calls, parameters and positional constructor
/// args are all Java identifiers, so a keyword field (`default`) must be emitted
/// as the sanitized `default_`.
void main() {
  const schema = '''
    type Address { default: String! city: String! }
    input CreateAddressInput @glMapsTo(type: "Address") { default: String! city: String! }
    type Query { noop: String }
  ''';

  String out0({required bool records}) {
    final g = GLParser(
      reservedWords: javaReservedWords,
      mode: CodeGenerationMode.server,
    )..parse(schema);
    return JavaSerializer(g,
            importPrefix: "",
            inputsAsRecords: records,
            typesAsRecords: records)
        .serializeInputDefinition(g.inputs['CreateAddressInput']!);
  }

  test("builder-style mapping uses the sanitized identifier", () {
    final out = out0(records: false);
    // builder setter for the keyword field is `.default_(...)`, never `.default(`.
    expect(out, contains(".default_("));
    expect(out, isNot(contains(".default(")));
  });

  test("record-style mapping uses the sanitized accessor", () {
    final out = out0(records: true);
    // record accessor for the keyword field is `default_()`.
    expect(out, contains("default_()"));
    expect(out, contains("address.default_()"));
  });
}
