import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/go/go_serializer.dart';
import 'package:test/test.dart';

GLParser _parser(String schema, {bool tolerantEnums = false}) =>
    GLParser(naming: NamingConvention.go, reservedWords: goReservedWords, tolerantEnums: tolerantEnums)..parse(schema);

GoSerializer _serializer(GLParser g) => GoSerializer(g, packageName: 'generated');

Iterable<String> lines(String s) => s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

void main() {
  group('enum', () {
    test('is a string type with prefixed constants keeping the wire value', () {
      final g = _parser('enum Status { inProgress done }');
      final out = _serializer(g).doSerializeEnumDefinition(g.enums['Status']!);
      expect(lines(out), containsAllInOrder([
        'type Status string',
        'StatusInProgress Status = "inProgress"',
        'StatusDone Status = "done"',
        'func (v Status) MarshalJSON() ([]byte, error) {',
        'func (v *Status) UnmarshalJSON(data []byte) error {',
      ]));
    });

    test('strict enums reject unknown wire values', () {
      final g = _parser('enum Status { active }');
      final out = _serializer(g).doSerializeEnumDefinition(g.enums['Status']!);
      expect(out, contains('return fmt.Errorf("invalid Status: %s", s)'));
      expect(out, isNot(contains('UnknownValue')));
    });

    test('tolerant enums fall back to the unknown member and refuse to serialize it', () {
      final g = _parser('enum Status { active }', tolerantEnums: true);
      final out = _serializer(g).doSerializeEnumDefinition(g.enums['Status']!);
      expect(out, contains('StatusUnknownValue__ Status = "unknownValue__"'));
      expect(lines(out), containsAllInOrder(['*v = StatusUnknownValue__', 'return nil']));
      expect(out, contains('cannot be serialized'));
    });
  });

  group('input', () {
    late String out;
    setUp(() {
      final g = _parser('''
        enum Role { admin user }
        input AddressInput { city: String! }
        input CreateUserInput {
          firstName: String!
          age: Int = 18
          role: Role = user
          tags: [String!] = ["a", "b"]
          address: AddressInput
        }
      ''');
      out = _serializer(g).doSerializeInputDefinition(g.inputs['CreateUserInput']!);
    });

    test('fields are exported with the wire name in the json tag', () {
      expect(out, contains('FirstName string `json:"firstName"`'));
      expect(out, contains('Address *AddressInput `json:"address"`'));
    });

    test('nullable scalars are pointers, nullable lists stay slices', () {
      expect(out, contains('Age *int `json:"age"`'));
      expect(out, contains('Tags []string `json:"tags"`'));
    });

    test('defaults are applied by a New constructor', () {
      expect(lines(out), containsAllInOrder([
        'func NewCreateUserInput() CreateUserInput {',
        'return CreateUserInput{',
        'Age: Ptr[int](18),',
        'Role: Ptr[Role](RoleUser),',
        'Tags: []string{"a", "b"},',
      ]));
    });
  });

  group('inputs without defaults', () {
    test('have no constructor', () {
      final g = _parser('input A { x: Int! }');
      expect(_serializer(g).doSerializeInputDefinition(g.inputs['A']!), isNot(contains('func New')));
    });
  });

  group('type', () {
    test('required object fields are values, nullable ones pointers', () {
      final g = _parser('''
        type Query { a: A }
        type A { b: B! c: B list: [B!]! maybe: [B] }
        type B { id: ID! }
      ''');
      final out = _serializer(g).doSerializeTypeDefinition(g.types['A']!);
      expect(out, contains('B B `json:"b"`'));
      expect(out, contains('C *B `json:"c"`'));
      expect(out, contains('List []B `json:"list"`'));
      expect(out, contains('Maybe []*B `json:"maybe"`'));
    });

    test('a type that implements an interface gets a typename marshaller and the interface markers', () {
      final g = _parser('''
        type Query { s: Shape }
        interface Shape { id: ID! kind: String }
        type Circle implements Shape { id: ID! kind: String radius: Int! }
      ''');
      final out = _serializer(g).doSerializeTypeDefinition(g.types['Circle']!);
      expect(out, contains('func (v Circle) IsShape() {'));
      expect(out, contains('func (v Circle) GetId() string {'));
      expect(out, contains('func (v Circle) GetKind() *string {'));
      expect(lines(out), containsAllInOrder([
        'func (v Circle) MarshalJSON() ([]byte, error) {',
        'type alias Circle',
        'Typename string `json:"__typename"`',
      ]));
    });

    test('a getter matches the interface signature when the type narrows nullability', () {
      final g = _parser('''
        type Query { s: Shape }
        interface Shape { kind: String }
        type Circle implements Shape { kind: String! }
      ''');
      final out = _serializer(g).doSerializeTypeDefinition(g.types['Circle']!);
      expect(lines(out), containsAllInOrder([
        'func (v Circle) GetKind() *string {',
        'copied := v.Kind',
        'return &copied',
      ]));
    });
  });

  group('interface', () {
    late String out;
    setUp(() {
      final g = _parser('''
        type Query { s: Shape }
        interface Shape { id: ID! }
        type Circle implements Shape { id: ID! }
        type Square implements Shape { id: ID! }
      ''');
      out = _serializer(g).doSerializeTypeDefinition(g.interfaces['Shape']!);
    });

    test('is a Go interface with a marker and getters', () {
      expect(lines(out), containsAllInOrder(['type Shape interface {', 'IsShape()', 'GetId() string']));
    });

    test('dispatches on __typename and rejects unknown types', () {
      expect(lines(out), containsAllInOrder([
        'func unmarshalShape(data json.RawMessage) (Shape, error) {',
        'switch probe.Typename {',
        'case "Circle":',
        'case "Square":',
      ]));
      expect(out, contains('does not implement Shape or not defined'));
    });
  });

  group('union', () {
    test('is a marker interface implemented by every member', () {
      final g = _parser('''
        type Query { m: Media }
        union Media = Photo | Video
        type Photo { url: String! }
        type Video { url: String! }
      ''');
      final serializer = _serializer(g);
      expect(serializer.doSerializeTypeDefinition(g.interfaces['Media']!), contains('type Media interface {'));
      expect(serializer.doSerializeTypeDefinition(g.types['Photo']!), contains('func (v Photo) IsMedia() {'));
    });
  });

  group('polymorphic fields', () {
    test('a struct with interface-typed fields decodes them through the dispatch function', () {
      final g = _parser('''
        type Query { box: Box }
        interface Shape { id: ID! }
        type Circle implements Shape { id: ID! }
        type Box { shape: Shape! shapes: [Shape!]! }
      ''');
      final out = _serializer(g).doSerializeTypeDefinition(g.types['Box']!);
      expect(lines(out), containsAllInOrder([
        'func (v *Box) UnmarshalJSON(data []byte) error {',
        'type alias Box',
        'v.Shape, err = unmarshalShape(aux.Shape)',
      ]));
      expect(out, contains('glDecodeList(r, unmarshalShape)'));
    });

    test('plain types need no custom decoder', () {
      final g = _parser('type Query { a: A } type A { id: ID! }');
      expect(_serializer(g).doSerializeTypeDefinition(g.types['A']!), isNot(contains('UnmarshalJSON')));
    });
  });

  group('files', () {
    test('a stem that Go reads as a build constraint is suffixed', () {
      final serializer = _serializer(_parser('type Query { a: Int }'));
      expect(serializer.fileStem('UserLinux'), 'user_linux_gl');
      expect(serializer.fileStem('UserTest'), 'user_test_gl');
      expect(serializer.fileStem('User'), 'user');
    });

    test('imports follow the packages the body uses', () {
      final serializer = _serializer(_parser('type Query { a: Int }'));
      final file = serializer.assembleFile('func f() { _ = json.Marshal; _ = fmt.Sprint; _ = context.Background }');
      expect(file, startsWith('package generated\n'));
      expect(file, contains('"context"'));
      expect(file, contains('"encoding/json"'));
      expect(file, contains('"fmt"'));
      expect(file, isNot(contains('"net/http"')));
    });
  });

  group('@glMapsTo', () {
    late GoSerializer serializer;
    late GLParser g;
    setUp(() {
      g = GLParser(naming: NamingConvention.go, reservedWords: goReservedWords, mode: CodeGenerationMode.server)..parse('''
        type Person { id: ID! firstName: String! email: String! }
        input CreatePersonInput @glMapsTo(type: "Person") {
          fname: String! @glMapField(to: "firstName")
          email: String!
        }
        type Query { noop: String }
      ''');
      serializer = _serializer(g);
    });

    test('generates a To method taking the fields the input lacks', () {
      final out = serializer.doSerializeInputDefinition(g.inputs['CreatePersonInput']!);
      expect(lines(out), containsAllInOrder([
        'func (v CreatePersonInput) ToPerson(id string) Person {',
        'return Person{',
        'FirstName: v.Fname,',
        'Id: id,',
      ]));
    });

    test('generates a package-level From function', () {
      final out = serializer.doSerializeInputDefinition(g.inputs['CreatePersonInput']!);
      expect(lines(out), containsAllInOrder([
        'func CreatePersonInputFromPerson(person Person) CreatePersonInput {',
        'Fname: person.FirstName,',
      ]));
    });
  });
}
