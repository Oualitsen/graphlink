import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

/// The `@glMapsTo`-generated `toXxx()`/`fromXxx()` methods synthesize a
/// `default<Field>` parameter name (for a target field the source input
/// leaves nullable/absent) by capitalizing the field's *wire* name
/// (`f.targetField.name.token.firstUp` / `f.sourceField!.name.token.firstUp`)
/// instead of its already-normalized `codeName`. Everywhere else in the same
/// generated method (the required/auto-mapped params, the assignment
/// targets) correctly uses `codeName`. Under a naming convention that changes
/// casing (e.g. snake_case wire names -> lowerCamelCase codeName), this
/// produces an inconsistent, wrongly-cased parameter name: `role_name` (wire)
/// -> `defaultRole_name` instead of the expected `defaultRoleName` (from
/// codeName `roleName`).
void main() {
  final camelConvention = NamingConvention(
    field: (s) => s.toLowerCamelCase(),
    enumValue: (s) => s.toLowerCamelCase(),
  );

  const schema = '''
    type User {
      id: ID!
      username: String!
      role_name: String!
    }

    input CreateUserInput @glMapsTo(type: "User") {
      username: String!
      role_name: String
    }

    type Query { noop: String }
  ''';

  test('toXxx() default param name uses the field codeName, not the wire name', () {
    final g = GLParser(
        naming: camelConvention,
        autoGenerateQueries: true,
        generateAllFieldsFragments: true,
        mode: CodeGenerationMode.server);
    g.parse(schema);

    final input = g.inputs['CreateUserInput']!;
    final out = DartSerializer(g, importPrefix: '').serializeInputDefinition(input);
    final lines = out.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    expect(lines, contains('required String defaultRoleName'));
    expect(out, isNot(contains('defaultRole_name')));
  });
}
