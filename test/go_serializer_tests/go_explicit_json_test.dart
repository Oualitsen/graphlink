import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/go/go_serializer.dart';
import 'package:test/test.dart';

GLParser _parser(String schema) => GLParser(naming: NamingConvention.go, reservedWords: goReservedWords)..parse(schema);

Iterable<String> lines(String s) => s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

String _input(String schema, String name) {
  final g = _parser(schema);
  return GoSerializer(g).doSerializeInputDefinition(g.inputs[name]!);
}

String _type(String schema, String name) {
  final g = _parser(schema);
  return GoSerializer(g).doSerializeTypeDefinition(g.types[name] ?? g.interfaces[name]!);
}

void main() {
  group('input', () {
    final out = _input('input UserInput { username: String agen: Int class: String! }', 'UserInput');

    test('ToJson sets the wire keys in declaration order', () {
      expect(lines(out), containsAllInOrder([
        'func (v UserInput) ToJson() (JsonObject, error) {',
        'm := NewJsonObject()',
        'm.Set("username", v.Username)',
        'm.Set("agen", v.Agen)',
        'm.Set("class", v.Class)',
        'return m, nil',
      ]));
    });

    test('FromJson reads the wire keys with a decoder per type', () {
      expect(lines(out), containsAllInOrder([
        'func UserInputFromJson(m map[string]any) (UserInput, error) {',
        'var v UserInput',
        'var err error',
        'if v.Username, err = glPtr(glString)(m["username"]); err != nil {',
        'return UserInput{}, glFieldError("UserInput", "username", err)',
        'if v.Agen, err = glPtr(glInt)(m["agen"]); err != nil {',
        'if v.Class, err = glString(m["class"]); err != nil {',
        'return v, nil',
      ]));
    });

    test('an input has no typename', () {
      expect(out, isNot(contains('__typename')));
    });

    test('the standard JSON hooks delegate to the explicit methods', () {
      expect(lines(out), containsAllInOrder([
        'func (v UserInput) MarshalJSON() ([]byte, error) {',
        'm, err := v.ToJson()',
        'return m.MarshalJSON()',
      ]));
      expect(lines(out), containsAllInOrder([
        'func (v *UserInput) UnmarshalJSON(data []byte) error {',
        'value, err := glParseJson(data)',
        'decoded, err := glObject(UserInputFromJson)(value)',
      ]));
    });
  });

  group('type', () {
    const schema = '''
      scalar Long
      enum Role { ADMIN USER }
      type Address { zip: String }
      type User {
        id: ID!
        role: Role!
        maybeRole: Role
        score: Float!
        big: Long!
        address: Address
        addresses: [Address!]!
        tags: [String!]
        grid: [[Role]]
      }
      type Query { user: User }
    ''';
    final out = _type(schema, 'User');

    test('plain fields are set directly and converted ones go through encoders', () {
      expect(lines(out), containsAllInOrder([
        'm.Set("id", v.Id)',
        'if value, err = glEncEnum[Role](v.Role); err != nil {',
        'm.Set("role", value)',
      ]));
      expect(out, contains('glEncPtr(glEncEnum[Role])(v.MaybeRole)'));
      expect(out, contains('glEncPtr(glEncObject[Address])(v.Address)'));
      expect(out, contains('glEncList(glEncObject[Address])(v.Addresses)'));
      expect(out, contains('m.Set("tags", v.Tags)'));
    });

    test('nested lists compose their element encoders', () {
      expect(out, contains('glEncList(glEncList(glEncPtr(glEncEnum[Role])))(v.Grid)'));
    });

    test('FromJson picks the decoder from the Go type', () {
      expect(lines(out), containsAll([
        'if v.Role, err = RoleFromJson(m["role"]); err != nil {',
        'if v.MaybeRole, err = glPtr(RoleFromJson)(m["maybeRole"]); err != nil {',
        'if v.Score, err = glFloat64(m["score"]); err != nil {',
        'if v.Big, err = glInt64(m["big"]); err != nil {',
        'if v.Address, err = glPtr(glObject(AddressFromJson))(m["address"]); err != nil {',
        'if v.Addresses, err = glList(glObject(AddressFromJson))(m["addresses"]); err != nil {',
        'if v.Tags, err = glNilable(glList(glString))(m["tags"]); err != nil {',
      ]));
    });

    test('a nullable list of nullable enums nests the wrappers', () {
      expect(out, contains('glNilable(glList(glNilable(glList(glPtr(RoleFromJson)))))(m["grid"])'));
    });

    test('a type with no fields declares no error variable', () {
      final empty = _type('type Empty { a: Int } type Query { e: Empty }', 'Empty');
      expect(empty, contains('var err error'));
    });
  });

  group('typename', () {
    test('types set it first', () {
      final out = _type('type Query { u: User } interface Node { id: ID! } type User implements Node { id: ID! }', 'User');
      expect(lines(out), containsAllInOrder([
        'm := NewJsonObject()',
        'm.Set("__typename", "User")',
        'm.Set("id", v.Id)',
      ]));
    });
  });

  group('@oneOf', () {
    test('ToJson only sets the members that are present', () {
      final out = _input('input Pet @oneOf { cat: String dog: [String!] }', 'Pet');
      expect(lines(out), containsAllInOrder([
        'if v.Cat != nil {',
        'm.Set("cat", v.Cat)',
        'if v.Dog != nil {',
        'm.Set("dog", v.Dog)',
      ]));
    });
  });

  group('defaults', () {
    test('a non-null field with a default tolerates a missing key', () {
      final out = _input('input D { a: Int! = 3 b: String! }', 'D');
      expect(out, contains('v.A, err = glNilable(glInt)(m["a"])'));
      expect(out, contains('v.B, err = glString(m["b"])'));
    });
  });

  group('enum', () {
    test('FromJson, ToJson and the standard hooks', () {
      final g = _parser('enum Role { ADMIN USER }');
      final out = GoSerializer(g).doSerializeEnumDefinition(g.enums['Role']!);
      expect(lines(out), containsAll([
        'func (v Role) ToJson() (string, error) {',
        'func RoleFromJson(value any) (Role, error) {',
        'func (v Role) MarshalJSON() ([]byte, error) {',
        'func (v *Role) UnmarshalJSON(data []byte) error {',
      ]));
    });
  });

  group('interface', () {
    const schema = 'interface Node { id: ID! } type User implements Node { id: ID! } type Post implements Node { id: ID! }';

    test('FromJson dispatches on the typename and the wrapper keeps the raw entry point', () {
      final out = _type(schema, 'Node');
      expect(lines(out), containsAllInOrder([
        'func NodeFromJson(value any) (Node, error) {',
        'if value == nil {',
        'return nil, glErrNull',
        'm, ok := value.(map[string]any)',
        'switch glStringOf(m["__typename"]) {',
        'case "User":',
        'return UserFromJson(m)',
        'case "Post":',
        'return PostFromJson(m)',
      ]));
      expect(out, contains('func unmarshalNode(data json.RawMessage) (Node, error) {'));
    });

    test('every implementation can be encoded through the interface', () {
      final out = _type(schema, 'Node');
      expect(out, contains('ToJson() (JsonObject, error)'));
    });
  });
}
