import 'dart:convert';

import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_openapi_extension.dart';
import 'package:graphlink/src/serializers/openapi_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
type Item { id: ID! name: String }
enum Reason { A B }
type NotFound @glError(status: 404) { id: ID }
type Conflict @glError(status: 409, value: "CONFLICT") { reason: Reason! }
type Gone @glError(status: 409, value: "GONE") { }
type Limited @glError(field: "error.kind", value: "rate") { retryAfter: Int! }
type Query {
  item(id: ID!): Item! @glRest(path: "/items/{id}") @glThrows(errors: [NotFound, Conflict, Gone, Limited])
  plain(id: ID!): Item! @glRest(path: "/plain/{id}")
}
''';

Map<String, dynamic> _spec() {
  final parser = GLParser()..parse(_schema);
  return jsonDecode(const OpenApiSerializer().serialize(parser.buildOpenApiDocument(const OpenApiConfig())))
      as Map<String, dynamic>;
}

void main() {
  final spec = _spec();
  final responses = (spec['paths']['/items/{id}']['get']['responses'] as Map).cast<String, dynamic>();
  final schemas = (spec['components']['schemas'] as Map).cast<String, dynamic>();

  test('an error with a status becomes a response of that status', () {
    expect(responses['404']['content']['application/json']['schema'], {r'$ref': '#/components/schemas/NotFound'});
  });

  test('it replaces the shared response of the same status', () {
    expect(responses['404'], isNot(contains(r'$ref')));
  });

  test('two errors on one status are a oneOf', () {
    final schema = responses['409']['content']['application/json']['schema'];
    expect(schema['oneOf'], [
      {r'$ref': '#/components/schemas/Conflict'},
      {r'$ref': '#/components/schemas/Gone'},
    ]);
    expect(responses['409']['description'], 'Conflict, Gone');
  });

  test('an error without a status is the default response', () {
    expect(responses['default']['content']['application/json']['schema'], {r'$ref': '#/components/schemas/Limited'});
  });

  test('the shared responses stay for the rest', () {
    expect(responses.keys, containsAll(['200', '400', '500']));
  });

  test('its schema has its fields, the message and the discriminator', () {
    expect(schemas['Conflict']['properties']['code'], {'type': 'string', 'const': 'CONFLICT'});
    expect(schemas['Conflict']['properties']['reason'], {r'$ref': '#/components/schemas/Reason'});
    expect(schemas['Conflict']['properties']['message'], {'type': 'string'});
    expect(schemas['Conflict']['required'], containsAll(['reason', 'code']));
  });

  test('a status-only error has no discriminator', () {
    expect(schemas['NotFound']['properties'].keys, containsAll(['id', 'message']));
    expect(schemas['NotFound']['properties'], isNot(contains('code')));
  });

  test('a nested discriminator path becomes nested properties', () {
    expect(schemas['Limited']['properties']['error']['properties']['kind'], {'type': 'string', 'const': 'rate'});
    expect(schemas['Limited']['properties']['error']['required'], ['kind']);
  });

  test('an operation without @glThrows gets none of them', () {
    final plain = (spec['paths']['/plain/{id}']['get']['responses'] as Map).keys;
    expect(plain, isNot(contains('409')));
    expect(plain, isNot(contains('default')));
  });
}
