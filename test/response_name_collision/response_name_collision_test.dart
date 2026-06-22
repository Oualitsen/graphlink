import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

const schema = '''
type Query {
  vulnerability(id: ID!): Vulnerability
}

type Vulnerability {
  id: ID!
  response: VulnerabilityResponse
}

# Declared type whose name collides with the auto-generated
# `vulnerability` query wrapper (`<Field>Response`).
type VulnerabilityResponse {
  statusCode: Int
}
''';

void main() {
  test('auto response wrapper is renamed when it collides with a declared type',
      () {
    final g = GLParser(
      generateAllFieldsFragments: true,
      autoGenerateQueries: true,
      defaultAlias: 'data',
    );

    g.parse(schema);

    // `vulnerability` would default to `VulnerabilityResponse`, which clashes
    // with the declared type, so it falls back to `<Field><Operation>Response`.
    final wrapper = g.queries['vulnerability']!.getGeneratedTypeDefinition();
    expect(wrapper.token, 'VulnerabilityQueryResponse');

    // The user-declared type keeps its own name, untouched.
    expect(g.projectedTypes.containsKey('VulnerabilityResponse'), isTrue);
  });
}
