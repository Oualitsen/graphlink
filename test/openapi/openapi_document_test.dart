import 'dart:convert';

import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/scalar_codec.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_openapi_extension.dart';
import 'package:graphlink/src/serializers/openapi_serializer.dart';
import 'package:test/test.dart';

const _markers = '''
scalar Void @glVoid
scalar Download @glDownload
directive @glUpload on SCALAR
scalar Upload @glUpload
''';

Map<String, dynamic> _spec(String schema, {Map<String, GLScalarCodec> codecs = const {}, OpenApiConfig? config}) {
  final parser = GLParser(scalarCodecs: codecs)..parse('$_markers$schema');
  final document = parser.buildOpenApiDocument(config ?? const OpenApiConfig());
  return jsonDecode(const OpenApiSerializer().serialize(document)) as Map<String, dynamic>;
}

Map<String, dynamic> _op(Map<String, dynamic> spec, String path, String method) =>
    (spec['paths'][path][method] as Map).cast<String, dynamic>();

List<Map<String, dynamic>> _params(Map<String, dynamic> op) =>
    ((op['parameters'] ?? const []) as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _param(Map<String, dynamic> op, String name) => _params(op).firstWhere((p) => p['name'] == name);

Map<String, dynamic> _schemas(Map<String, dynamic> spec) => (spec['components']['schemas'] as Map).cast<String, dynamic>();

Map<String, dynamic> _ok(Map<String, dynamic> op, String mediaType) => op['responses']['200']['content'][mediaType]['schema'];

const _item = 'type Item { id: ID! name: String }\n';

void main() {
  group('document', () {
    test('openapi 3.1, info and servers come from the config', () {
      final spec = _spec('$_item type Query { item: Item @glRest(path: "/item") }',
          config: const OpenApiConfig(title: 'Shop', version: '2.0.0', serverUrl: '/api'));
      expect(spec['openapi'], '3.1.0');
      expect(spec['info'], {'title': 'Shop', 'version': '2.0.0'});
      expect(spec['servers'], [
        {'url': '/api'}
      ]);
    });

    test('operations are grouped by path and keyed by lower-case method', () {
      final spec = _spec('''$_item
        type Query { item(id: ID!): Item @glRest(path: "/items/{id}") }
        type Mutation { removeItem(id: ID!): Void @glRest(path: "/items/{id}", method: DELETE) }''');
      expect((spec['paths']['/items/{id}'] as Map).keys, unorderedEquals(['get', 'delete']));
      expect(_op(spec, '/items/{id}', 'get')['operationId'], 'item');
      expect(_op(spec, '/items/{id}', 'delete')['operationId'], 'removeItem');
    });

    test('no REST operation yields an empty document', () {
      final spec = _spec('$_item type Query { item: Item }');
      expect(spec['paths'], isEmpty);
      expect(_schemas(spec), isEmpty);
    });

    test('only types reachable from REST operations are emitted', () {
      final spec = _spec('''$_item type Other { x: Int }
        type Query { item: Item @glRest(path: "/item") other: Other }''');
      expect(_schemas(spec).keys, unorderedEquals(['Item', 'RestError']));
    });
  });

  group('parameters', () {
    test('path parameters are required and keep the placeholder', () {
      final op = _op(_spec('$_item type Query { item(id: ID!): Item @glRest(path: "/items/{id}") }'), '/items/{id}', 'get');
      expect(_param(op, 'id'), {'name': 'id', 'in': 'path', 'required': true, 'schema': {'type': 'string'}});
    });

    test('query and header parameters follow nullability and defaults', () {
      final op = _op(_spec('''$_item type Query {
        items(
          q: String! @glRestParam,
          page: Int @glRestParam,
          size: Int! = 20 @glRestParam,
          token: String! @glRestHeader(name: "X-Token")
        ): [Item!]! @glRest(path: "/items")
      }'''), '/items', 'get');
      expect(_param(op, 'q')['required'], isTrue);
      expect(_param(op, 'page')['required'], isFalse);
      expect(_param(op, 'size')['required'], isFalse);
      expect(_param(op, 'size')['schema'], {'type': 'integer', 'format': 'int32', 'default': 20});
      final token = _param(op, 'X-Token');
      expect(token['in'], 'header');
      expect(token['required'], isTrue);
    });

    test('a list query argument repeats its key', () {
      final op = _op(_spec('$_item type Query { items(tags: [String!] @glRestParam): [Item!]! @glRest(path: "/items") }'), '/items', 'get');
      expect(_param(op, 'tags'), {
        'name': 'tags',
        'in': 'query',
        'required': false,
        'schema': {
          'type': 'array',
          'items': {'type': 'string'}
        },
        'style': 'form',
        'explode': true,
      });
    });

    test('a spread input becomes one parameter per field', () {
      final op = _op(_spec('''$_item
        input Filter { tag: String minQty: Int! colors: [String!] }
        type Query { items(filter: Filter @glRestParam(encoding: SPREAD)): [Item!]! @glRest(path: "/items") }'''), '/items', 'get');
      expect(_params(op).map((p) => p['name']), unorderedEquals(['tag', 'minQty', 'colors']));
      expect(_param(op, 'tag')['required'], isFalse);
      expect(_param(op, 'minQty')['required'], isFalse, reason: 'the spread argument itself is optional');
      expect(_param(op, 'colors')['style'], 'form');
    });

    test('a JSON-encoded query input carries content instead of schema', () {
      final spec = _spec('''$_item
        input Filter { tag: String }
        type Query { items(filter: Filter! @glRestParam(encoding: JSON)): [Item!]! @glRest(path: "/items") }''');
      final param = _param(_op(spec, '/items', 'get'), 'filter');
      expect(param.containsKey('schema'), isFalse);
      expect(param['content']['application/json']['schema'], {r'$ref': '#/components/schemas/Filter'});
      expect(_schemas(spec).containsKey('Filter'), isTrue);
    });

    test('a list header uses the simple style', () {
      final op = _op(_spec('''$_item type Query {
        items(ids: [String!]! @glRestHeader(name: "X-Ids")): [Item!]! @glRest(path: "/items") }'''), '/items', 'get');
      expect(_param(op, 'X-Ids')['style'], 'simple');
    });
  });

  group('request bodies', () {
    const types = '''$_item
      input ItemInput { name: String! qty: Int }
      enum Color { RED GREEN }''';

    test('a JSON body references its input', () {
      final spec = _spec('$types type Mutation { addItem(input: ItemInput! @glRestBody): Item @glRest(path: "/items") }');
      final body = _op(spec, '/items', 'post')['requestBody'];
      expect(body['required'], isTrue);
      expect(body['content']['application/json']['schema'], {r'$ref': '#/components/schemas/ItemInput'});
      expect(_schemas(spec)['ItemInput'], {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'qty': {
            'type': ['integer', 'null'],
            'format': 'int32'
          },
        },
        'required': ['name'],
      });
    });

    test('an optional body is not required', () {
      final spec = _spec('$types type Mutation { addItem(input: ItemInput @glRestBody): Item @glRest(path: "/items") }');
      expect(_op(spec, '/items', 'post')['requestBody']['required'], isFalse);
    });

    test('a list body is an array', () {
      final spec = _spec('$types type Mutation { addItems(input: [ItemInput!]! @glRestBody): [Item!]! @glRest(path: "/items") }');
      final schema = _op(spec, '/items', 'post')['requestBody']['content']['application/json']['schema'];
      expect(schema, {
        'type': 'array',
        'items': {r'$ref': '#/components/schemas/ItemInput'}
      });
    });

    test('form fields become properties of a urlencoded body', () {
      final spec = _spec('''$types type Mutation {
        addItem(name: String! @glRestField, qty: Int @glRestField, color: Color @glRestField): Item @glRest(path: "/items") }''');
      final content = _op(spec, '/items', 'post')['requestBody']['content'];
      final schema = content['application/x-www-form-urlencoded']['schema'];
      expect(schema['required'], ['name']);
      expect((schema['properties'] as Map).keys, unorderedEquals(['name', 'qty', 'color']));
      expect(schema['properties']['color'], {r'$ref': '#/components/schemas/Color'});
    });

    test('multipart parts map uploads to binary', () {
      final spec = _spec('''$types type Mutation {
        addFile(title: String! @glRestPart, file: Upload! @glRestPart, extras: [Upload!] @glRestPart): Item @glRest(path: "/files") }''');
      final schema = _op(spec, '/files', 'post')['requestBody']['content']['multipart/form-data']['schema'];
      expect(schema['properties']['file'], {'type': 'string', 'format': 'binary'});
      expect(schema['properties']['extras'], {
        'type': 'array',
        'items': {'type': 'string', 'format': 'binary'}
      });
      expect(schema['required'], unorderedEquals(['title', 'file']));
    });

    test('a raw upload body uses its content type', () {
      final spec = _spec('''$types type Mutation {
        putFile(file: Upload! @glRestBody): Item @glRest(path: "/raw", contentType: "image/png") }''');
      final content = _op(spec, '/raw', 'post')['requestBody']['content'];
      expect(content['image/png']['schema'], {'type': 'string', 'format': 'binary'});
    });
  });

  group('responses', () {
    test('json', () {
      final op = _op(_spec('$_item type Query { item: Item! @glRest(path: "/item") }'), '/item', 'get');
      expect(_ok(op, 'application/json'), {r'$ref': '#/components/schemas/Item'});
      expect(op['responses'].containsKey('204'), isFalse);
    });

    test('a nullable result also allows no content', () {
      final op = _op(_spec('$_item type Query { item: Item @glRest(path: "/item") }'), '/item', 'get');
      expect(_ok(op, 'application/json'), {r'$ref': '#/components/schemas/Item'});
      expect(op['responses'].containsKey('204'), isTrue);
    });

    test('a list of nullable elements', () {
      final op = _op(_spec('$_item type Query { items: [Item]! @glRest(path: "/items") }'), '/items', 'get');
      expect(_ok(op, 'application/json'), {
        'type': 'array',
        'items': {
          'oneOf': [
            {r'$ref': '#/components/schemas/Item'},
            {'type': 'null'}
          ]
        },
      });
    });

    test('text', () {
      final op = _op(_spec('type Query { hello: String! @glRest(path: "/hello", response: TEXT) }'), '/hello', 'get');
      expect(_ok(op, 'text/plain'), {'type': 'string'});
    });

    test('binary download uses the accept media type', () {
      final op = _op(_spec('type Query { file: Download! @glRest(path: "/file", accept: "application/pdf") }'), '/file', 'get');
      expect(_ok(op, 'application/pdf'), {'type': 'string', 'format': 'binary'});
    });

    test('void is a 204 without content', () {
      final op = _op(_spec('type Mutation { ping: Void @glRest(path: "/ping") }'), '/ping', 'post');
      expect(op['responses']['204'], {'description': 'No content'});
      expect(op['responses'].containsKey('200'), isFalse);
    });

    test('responsePath wraps the schema in nested objects', () {
      final op = _op(_spec('$_item type Query { items: [Item!]! @glRest(path: "/items", responsePath: "data.items") }'), '/items', 'get');
      expect(_ok(op, 'application/json'), {
        'type': 'object',
        'properties': {
          'data': {
            'type': 'object',
            'properties': {
              'items': {
                'type': 'array',
                'items': {r'$ref': '#/components/schemas/Item'}
              },
            },
            'required': ['items'],
          },
        },
        'required': ['data'],
      });
    });

    test('error responses are shared references to one error schema', () {
      final spec = _spec('$_item type Query { item(id: ID!): Item @glRest(path: "/items/{id}") }');
      final responses = _op(spec, '/items/{id}', 'get')['responses'];
      expect(responses['400'], {r'$ref': '#/components/responses/400'});
      expect(responses['404'], {r'$ref': '#/components/responses/404'});
      expect(responses['500'], {r'$ref': '#/components/responses/500'});
      final shared = spec['components']['responses'];
      expect(shared.keys, unorderedEquals(['400', '404', '405', '500']));
      expect(shared['400']['content']['application/json']['schema'], {r'$ref': '#/components/schemas/RestError'});
      expect(_schemas(spec)['RestError']['required'], ['message']);
    });

    test('an operation without inputs gets no 400 and no 404', () {
      final responses = _op(_spec('$_item type Query { item: Item @glRest(path: "/item") }'), '/item', 'get')['responses'];
      expect(responses.containsKey('400'), isFalse);
      expect(responses.containsKey('404'), isFalse);
    });
  });

  group('types', () {
    test('scalars, lists and nullability', () {
      final spec = _spec('''
        type Thing { id: ID! s: String n: Int! f: Float b: Boolean tags: [String!]! maybe: [Int] }
        type Query { thing: Thing! @glRest(path: "/thing") }''');
      final thing = _schemas(spec)['Thing'];
      expect(thing['properties'], {
        'id': {'type': 'string'},
        's': {
          'type': ['string', 'null']
        },
        'n': {'type': 'integer', 'format': 'int32'},
        'f': {
          'type': ['number', 'null']
        },
        'b': {
          'type': ['boolean', 'null']
        },
        'tags': {
          'type': 'array',
          'items': {'type': 'string'}
        },
        'maybe': {
          'type': ['array', 'null'],
          'items': {
            'type': ['integer', 'null'],
            'format': 'int32'
          }
        },
      });
      expect(thing['required'], ['id', 'n', 'tags']);
    });

    test('enums list their wire values', () {
      final spec = _spec('''enum Color { RED GREEN }
        type Thing { color: Color! other: Color }
        type Query { thing: Thing! @glRest(path: "/thing") }''');
      expect(_schemas(spec)['Color'], {
        'type': 'string',
        'enum': ['RED', 'GREEN']
      });
    });

    test('Long is an int64', () {
      final spec = _spec('''scalar Long
        type Thing { big: Long! }
        type Query { thing: Thing! @glRest(path: "/thing") }''');
      expect(_schemas(spec)['Thing']['properties']['big'], {'type': 'integer', 'format': 'int64'});
    });

    test('a custom scalar with a codec uses its json type and known format', () {
      final spec = _spec('''scalar DateTime
        scalar Money
        type Thing { at: DateTime! price: Money! }
        type Query { thing: Thing! @glRest(path: "/thing") }''', codecs: {
        'DateTime': const GLScalarCodec(type: 'DateTime', jsonType: 'String'),
        'Money': const GLScalarCodec(type: 'double', jsonType: 'Double'),
      });
      final props = _schemas(spec)['Thing']['properties'];
      expect(props['at'], {'type': 'string', 'format': 'date-time'});
      expect(props['price'], {'type': 'number'});
    });

    test('a custom scalar without a codec is any, named in its description', () {
      final spec = _spec('''scalar Blob
        type Thing { data: Blob! }
        type Query { thing: Thing! @glRest(path: "/thing") }''');
      expect(_schemas(spec)['Thing']['properties']['data'], {'description': "Custom scalar 'Blob'"});
    });

    test('nested types and inputs are collected transitively', () {
      final spec = _spec('''type Owner { name: String! }
        type Pet { owner: Owner! }
        type Query { pet: Pet! @glRest(path: "/pet") }''');
      expect(_schemas(spec).keys, unorderedEquals(['Pet', 'Owner', 'RestError']));
    });

    test('a recursive type terminates', () {
      final spec = _spec('''type Node { next: Node children: [Node!]! }
        type Query { node: Node! @glRest(path: "/node") }''');
      expect(_schemas(spec).keys, unorderedEquals(['Node', 'RestError']));
    });
  });

  group('interfaces and unions', () {
    const pets = '''
      interface Pet @glRestDiscriminator(field: "kind", values: {Dog: "dog", Cat: "cat"}) { id: ID! }
      type Dog implements Pet { id: ID! barks: Boolean }
      type Cat implements Pet { id: ID! lives: Int }''';

    test('an interface with a discriminator is a oneOf with a mapping', () {
      final spec = _spec('$pets type Query { pet: Pet! @glRest(path: "/pet") }');
      expect(_schemas(spec)['Pet'], {
        'oneOf': [
          {r'$ref': '#/components/schemas/Dog'},
          {r'$ref': '#/components/schemas/Cat'}
        ],
        'discriminator': {
          'propertyName': 'kind',
          'mapping': {'dog': '#/components/schemas/Dog', 'cat': '#/components/schemas/Cat'},
        },
      });
    });

    test('implementations carry the discriminator as a required const', () {
      final dog = _schemas(_spec('$pets type Query { pet: Pet! @glRest(path: "/pet") }'))['Dog'];
      expect(dog['properties']['kind'], {'type': 'string', 'const': 'dog'});
      expect(dog['required'], contains('kind'));
    });

    test('a declared discriminator field is replaced by the const, not duplicated', () {
      final spec = _spec('''
        interface Pet @glRestDiscriminator(field: "kind") { id: ID! }
        type Dog implements Pet { id: ID! kind: String! }
        type Cat implements Pet { id: ID! }
        type Query { pet: Pet! @glRest(path: "/pet") }''');
      final dog = _schemas(spec)['Dog'];
      expect(dog['properties']['kind'], {'type': 'string', 'const': 'Dog'});
      expect((dog['required'] as List).where((r) => r == 'kind'), hasLength(1));
    });

    test('a union takes the same path', () {
      final spec = _spec('''
        type Dog { id: ID! }
        type Cat { id: ID! }
        union Hit @glRestDiscriminator(field: "type", values: {Dog: "dog", Cat: "cat"}) = Dog | Cat
        type Query { search: [Hit!]! @glRest(path: "/search") }''');
      final schemas = _schemas(spec);
      expect(schemas['Hit']['discriminator']['propertyName'], 'type');
      expect(schemas['Hit']['oneOf'], hasLength(2));
      expect(schemas['Cat']['properties']['type'], {'type': 'string', 'const': 'cat'});
    });
  });

  group('@glRestNullable', () {
    test('the copy is its own schema with every field nullable', () {
      final spec = _spec('''
        type Product { id: ID! name: String! }
        type Query { product: Product! @glRest(path: "/product") @glRestNullable }''');
      final copy = _schemas(spec)['ProductRest'];
      expect(copy, isNotNull);
      expect(copy['properties']['id'], {
        'type': ['string', 'null']
      });
      expect(copy.containsKey('required'), isFalse);
      expect(_schemas(spec).containsKey('Product'), isFalse);
    });
  });
}
