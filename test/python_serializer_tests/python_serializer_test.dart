import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:test/test.dart';

GLParser _parser(String schema, {bool tolerantEnums = false}) =>
    GLParser(naming: NamingConvention.python, reservedWords: pythonReservedWords, tolerantEnums: tolerantEnums)
      ..parse(schema);

PythonSerializer _serializer(GLParser g, {bool immutableTypeFields = true}) =>
    PythonSerializer(g, immutableTypeFields: immutableTypeFields);

Iterable<String> lines(String s) => s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

void main() {
  group('enum', () {
    test('is a str-backed Enum with SCREAMING_SNAKE members keeping the wire value', () {
      final g = _parser('enum Status { inProgress done }');
      final out = _serializer(g).doSerializeEnumDefinition(g.enums['Status']!);
      expect(lines(out), containsAllInOrder([
        'class Status(str, Enum):',
        'IN_PROGRESS = "inProgress"',
        'DONE = "done"',
        'def to_json(self) -> str:',
        'return self.value',
      ]));
    });

    test('tolerant enums add an unknown member that is returned for unrecognized values', () {
      final g = _parser('enum Status { active }', tolerantEnums: true);
      final out = _serializer(g).doSerializeEnumDefinition(g.enums['Status']!);
      expect(lines(out), containsAllInOrder([
        'def _missing_(cls, value: object) -> "Status":',
        'return cls.unknownValue__',
      ]));
      expect(out, contains('cannot be serialized'));
    });

    test('strict enums have no fallback', () {
      final g = _parser('enum Status { active }');
      final out = _serializer(g).doSerializeEnumDefinition(g.enums['Status']!);
      expect(out, isNot(contains('_missing_')));
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

    test('is an immutable pydantic model', () {
      expect(lines(out), containsAllInOrder([
        'class CreateUserInput(GraphLinkModel):',
        'model_config = ConfigDict(frozen=True)',
      ]));
    });

    test('mutable models drop frozen', () {
      final g = _parser('input I { a: String! }');
      final mutable = _serializer(g, immutableTypeFields: false).doSerializeInputDefinition(g.inputs['I']!);
      expect(mutable, contains('model_config = ConfigDict()'));
    });

    test('snake_case field keeps the wire name as alias', () {
      expect(lines(out), contains('first_name: str = Field(alias="firstName")'));
    });

    test('scalar and enum defaults are plain defaults, nullable fields default to None', () {
      expect(lines(out), containsAll([
        'age: Optional[int] = 18',
        'role: Optional[Role] = Role.USER',
        'address: Optional[AddressInput] = None',
      ]));
    });

    test('list defaults use a factory so instances never share state', () {
      expect(lines(out), contains('tags: Optional[List[str]] = Field(default_factory=lambda: ["a", "b"])'));
    });
  });

  group('type', () {
    test('required and nullable fields', () {
      final g = _parser('type Query { user: User } type User { id: ID! scores: [Int!] address: Address } type Address { zip: String }');
      final out = _serializer(g).doSerializeTypeDefinition(g.types['User']!);
      expect(lines(out), containsAllInOrder([
        'class User(GraphLinkModel):',
        'id: str',
        'scores: Optional[List[int]] = None',
        'address: Optional[Address] = None',
      ]));
    });

    test('nullableFieldsRequired makes nullable fields required', () {
      final g = GLParser(naming: NamingConvention.python, nullableFieldsRequired: true)..parse('type User { name: String }');
      final out = _serializer(g).doSerializeTypeDefinition(g.types['User']!);
      expect(lines(out), contains('name: Optional[str]'));
    });

    test('types implementing an interface inherit from it and carry their typename', () {
      final g = _parser('interface Node { id: ID! } type User implements Node { id: ID! name: String! }');
      final out = _serializer(g).doSerializeTypeDefinition(g.types['User']!);
      expect(lines(out), containsAllInOrder([
        'class User(Node):',
        'GL_TYPENAME: ClassVar[Optional[str]] = "User"',
      ]));
    });

    test('@glEqualsHashcode overrides equality and hash on the identity fields', () {
      final g = _parser('type User @glEqualsHashcode(fields: ["id"]) { id: ID! name: String! }');
      final out = _serializer(g).doSerializeTypeDefinition(g.types['User']!);
      expect(lines(out), containsAll([
        'def __eq__(self, other: object) -> bool:',
        'return (self.id,) == (other.id,)',
        'def __hash__(self) -> int:',
        'return hash((self.id,))',
      ]));
    });
  });

  group('interface', () {
    late String out;
    setUp(() {
      final g = _parser('interface Node { id: ID! } type User implements Node { id: ID! } type Post implements Node { id: ID! }');
      out = _serializer(g).doSerializeTypeDefinition(g.interfaces['Node']!);
    });

    test('dispatches on __typename through a wrap validator', () {
      expect(lines(out), containsAllInOrder([
        'class Node(GraphLinkModel):',
        '@model_validator(mode="wrap")',
        'def _dispatch_by_typename(cls, data: Any, handler: Any) -> Any:',
        'if cls is Node and isinstance(data, dict) and "__typename" in data:',
        'target = _node_implementations().get(typename)',
      ]));
    });

    test('unknown typenames raise instead of silently building the abstract type', () {
      expect(out, contains('raise ValueError(f"Invalid type {typename}.'));
    });

    test('implementations are imported lazily to avoid import cycles', () {
      expect(lines(out), contains('def _node_implementations() -> Dict[str, Any]:'));
      expect(out, contains('from ..types.user import User'));
      expect(out, contains('from ..types.post import Post'));
    });
  });

  group('module', () {
    test('model files import enums and base interfaces eagerly, other types for type checking only', () {
      final g = _parser('''
        enum Role { admin }
        interface Node { id: ID! }
        type Address { city: String }
        type User implements Node { id: ID! role: Role! address: Address }
      ''');
      final out = _serializer(g).serializeTypeDefinition(g.types['User']!);
      expect(lines(out), containsAllInOrder([
        'from __future__ import annotations',
        'from ..enums.role import Role',
        'from ..interfaces.node import Node',
        'if TYPE_CHECKING:',
        'from ..types.address import Address',
      ]));
    });

    test('file names are snake_case modules, reserved words get a suffix', () {
      final g = _parser('type UserProfile { id: ID } type Import { id: ID }');
      final s = _serializer(g);
      expect(s.getFileNameFor(g.types['UserProfile']!), 'user_profile.py');
      expect(s.getFileNameFor(g.types['Import']!), 'import_.py');
    });
  });

  group('naming', () {
    test('keywords and pydantic attributes are escaped', () {
      final g = _parser('type T { class: String from: String json: String }');
      final out = _serializer(g).doSerializeTypeDefinition(g.types['T']!);
      expect(lines(out), containsAll([
        'class_: Optional[str] = Field(default=None, alias="class")',
        'from_: Optional[str] = Field(default=None, alias="from")',
        'json_: Optional[str] = Field(default=None, alias="json")',
      ]));
    });

    test('acronyms are not split letter by letter', () {
      final g = _parser('type T { HTTPStatus: Int getHTMLParser: String }');
      final out = _serializer(g).doSerializeTypeDefinition(g.types['T']!);
      expect(lines(out), containsAll([
        'http_status: Optional[int] = Field(default=None, alias="HTTPStatus")',
        'get_html_parser: Optional[str] = Field(default=None, alias="getHTMLParser")',
      ]));
    });
  });
}
