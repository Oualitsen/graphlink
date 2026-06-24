import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// `@glMapsTo` / `@glMapField` generate `toX()` / `fromX()` methods that map
/// between two generated Dart classes. Every name in those methods is a Dart
/// identifier (named constructor arg or property access), never a wire string,
/// so a keyword field (`default`) must use the sanitized `default_` on both
/// the source input and the target type.
void main() {
  const schema = '''
    type Address {
      default: String!
      city: String!
    }

    input CreateAddressInput @glMapsTo(type: "Address") {
      default: String!
      city: String!
    }

    type Query { noop: String }
  ''';

  List<String> _lines() {
    final g = GLParser(
      reservedWords: dartReservedWords,
      mode: CodeGenerationMode.server,
    )..parse(schema);
    final input = g.inputs['CreateAddressInput']!;
    final out = DartSerializer(g, importPrefix: "")
        .serializeInputDefinition(input);
    return out.split('\n').map((l) => l.trim()).toList();
  }

  test("toAddress() maps the keyword field via the sanitized identifier", () {
    expect(_lines(), contains('return Address(default_: default_, city: city);'));
  });

  test("fromAddress() maps the keyword field via the sanitized identifier", () {
    expect(_lines(),
        contains(
            'return CreateAddressInput(default_: address.default_, city: address.city);'));
  });
}
