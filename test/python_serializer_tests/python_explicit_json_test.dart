import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:test/test.dart';

GLParser _parser(String schema) =>
    GLParser(naming: NamingConvention.python, reservedWords: pythonReservedWords)..parse(schema);

String _input(String schema, String name) {
  final g = _parser(schema);
  return PythonSerializer(g).doSerializeInputDefinition(g.inputs[name]!);
}

String _type(String schema, String name) {
  final g = _parser(schema);
  return PythonSerializer(g).doSerializeTypeDefinition(g.types[name] ?? g.interfaces[name]!);
}

Iterable<String> lines(String s) => s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

void main() {
  group('input', () {
    final out = _input('input UserInput { username: String agen: Int first_name: String! }', 'UserInput');

    test('to_json builds the wire object from the code names', () {
      expect(lines(out), containsAllInOrder([
        'def to_json(self) -> Dict[str, Any]:',
        'return {',
        '"username": self.username,',
        '"agen": self.agen,',
        '"first_name": self.first_name',
        '}',
      ]));
    });

    test('from_json reads the wire keys and builds the model', () {
      expect(lines(out), containsAllInOrder([
        '@classmethod',
        'def from_json(cls, json: Dict[str, Any]) -> "UserInput":',
        'return cls(',
        'username=json.get("username"),',
        'agen=json.get("agen"),',
        'first_name=json["first_name"]',
        ')',
      ]));
    });

    test('a missing required key is reported with the type and the field before anything is built', () {
      expect(lines(out), containsAllInOrder([
        'def from_json(cls, json: Dict[str, Any]) -> "UserInput":',
        'for key in ("first_name",):',
        'if key not in json:',
        "raise ValueError(f'Cannot decode UserInput: missing required field \"{key}\"')",
        'return cls(',
      ]));
    });

    test('a type with only optional fields has no check', () {
      final optional = _input('input O { a: String b: Int }', 'O');
      expect(optional, isNot(contains('missing required field')));
    });

    test('a field with a default is not required', () {
      final withDefault = _input('input D { a: Int! = 3 b: String! }', 'D');
      expect(withDefault, contains('for key in ("b",):'));
      expect(lines(withDefault), contains('a=json.get("a", 3),'));
    });

    test('an input has no typename', () {
      expect(out, isNot(contains('__typename')));
    });

    test('nothing is left to pydantic hooks', () {
      expect(out, isNot(contains('model_validator')));
      expect(out, isNot(contains('model_serializer')));
      expect(out, isNot(contains('GL_TYPENAME')));
    });
  });

  group('reserved words', () {
    final out = _input('input I { class: String! return: Int! from: String }', 'I');

    test('the wire key stays and the code name gets the suffix', () {
      expect(lines(out), containsAll([
        '"class": self.class_,',
        '"return": self.return_,',
        '"from": self.from_',
        'class_=json["class"],',
        'return_=json["return"],',
        'from_=json.get("from")',
      ]));
    });
  });

  group('type', () {
    const schema = '''
      enum Role { ADMIN USER }
      interface Node { id: ID! }
      type Address { zip: String }
      type User implements Node {
        id: ID!
        role: Role!
        maybeRole: Role
        score: Float!
        address: Address
        addresses: [Address!]!
        grid: [[Role]]
        names: [String!]
      }
      type Query { user: User }
    ''';
    final out = _type(schema, 'User');

    test('to_json starts with the typename', () {
      expect(lines(out), containsAllInOrder([
        'def to_json(self) -> Dict[str, Any]:',
        'return {',
        '"__typename": "User",',
        '"id": self.id,',
      ]));
    });

    test('enums and nested types are converted by their own methods', () {
      expect(lines(out), containsAll([
        '"role": self.role.to_json(),',
        '"maybeRole": (None if self.maybe_role is None else self.maybe_role.to_json()),',
        '"address": (None if self.address is None else self.address.to_json()),',
        '"addresses": [e0.to_json() for e0 in self.addresses],',
      ]));
    });

    test('lists of lists are converted element by element', () {
      expect(out, contains('[(None if e1 is None else e1.to_json()) for e1 in e0]'));
    });

    test('plain lists are passed through', () {
      expect(lines(out), contains('"names": self.names'));
    });

    test('from_json converts enums, nested types and floats', () {
      expect(lines(out), containsAll([
        'role=Role.from_json(json["role"]),',
        'maybe_role=(None if json.get("maybeRole") is None else Role.from_json(json.get("maybeRole"))),',
        'score=float(json["score"]),',
        'address=(None if json.get("address") is None else Address.from_json(json.get("address"))),',
        'addresses=[Address.from_json(e0) for e0 in json["addresses"]],',
        'names=json.get("names")',
      ]));
    });

    test('nested types are imported where from_json runs, because the module only imports them for type checking', () {
      expect(lines(out), containsAllInOrder([
        'def from_json(cls, json: Dict[str, Any]) -> "User":',
        'from ..types.address import Address',
        'return cls(',
      ]));
    });

    test('a self reference needs no import', () {
      final tree = _type('type Tree { id: ID! child: Tree } type Query { t: Tree }', 'Tree');
      expect(tree, isNot(contains('import Tree')));
      expect(lines(tree), contains('child=(None if json.get("child") is None else Tree.from_json(json.get("child")))'));
    });
  });

  group('@oneOf', () {
    test('to_json leaves out the members that are not set', () {
      final out = _input('input Pet @oneOf { cat: String dog: String }', 'Pet');
      expect(lines(out), containsAllInOrder([
        'def to_json(self) -> Dict[str, Any]:',
        'return {k: v for k, v in {',
        '"cat": self.cat,',
        '"dog": self.dog',
        '}.items() if v is not None}',
      ]));
    });
  });

  group('interface', () {
    const schema = 'interface Node { id: ID! } type User implements Node { id: ID! } type Post implements Node { id: ID! }';

    test('from_json dispatches on __typename and rejects unknown ones', () {
      final out = _type(schema, 'Node');
      expect(lines(out), containsAllInOrder([
        'def from_json(cls, json: Dict[str, Any]) -> "Node":',
        'if cls is Node and "__typename" in json:',
        'typename = json["__typename"]',
        'target = _node_implementations().get(typename)',
        'if target is None:',
        'raise ValueError(f"Invalid type {typename}. {typename} does not implement Node or not defined")',
        'return target.from_json(json)',
        'return cls(',
        'id=json["id"]',
        ')',
      ]));
    });

    test('an interface has its own to_json, without a typename', () {
      final out = _type(schema, 'Node');
      expect(lines(out), containsAllInOrder([
        'def to_json(self) -> Dict[str, Any]:',
        'return {',
        '"id": self.id',
        '}',
      ]));
    });

    test('a synthetic implementation is returned directly', () {
      final g = GLParser(naming: NamingConvention.python, reservedWords: pythonReservedWords, generateAllFieldsFragments: true)
        ..parse(r'''
          type Query { node(id: ID!): Node }
          interface Node { id: ID! }
          type Article implements Node { id: ID! title: String! }
          query q($id: ID!) { node(id: $id) { id } }
        ''');
      final synthetic = g.projectedInterfaces.values.firstWhere((i) => i.syntheticImplementation != null);
      final out = PythonSerializer(g).serializeSyntheticInterfaceFromJson(synthetic);
      expect(lines(out), containsAllInOrder([
        '@classmethod',
        'if cls is ${synthetic.codeName}:',
        'return ${synthetic.syntheticImplementation!.codeName}.from_json(json)',
      ]));
    });
  });
}
