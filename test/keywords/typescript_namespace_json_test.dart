import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

void main() {
  group('TypeScript namespace toJson/fromJson', () {
    test('enum: toJson returns value, fromJson switches on wire name', () {
      const schema = '''
        enum Action {
          return
          cancel
        }
      ''';

      final g = GLParser(reservedWords: typescriptReservedWords);
      g.parse(schema);

      final def = g.enums['Action']!;
      final serializer = TypeScriptSerializer(g, importPrefix: '');
      final out = serializer.serializeEnumDefinition(def);
      print(out);

      // Enum constants keep wire name as string value (TS doesn't sanitize)
      expect(out, contains("return = 'return'"));
      expect(out, contains("cancel = 'cancel'"));

      // Namespace is emitted
      expect(out, contains('export namespace Action'));

      // toJson: trivial passthrough
      expect(out, contains('toJson(value: Action): string'));
      expect(out, contains('return value;'));

      // fromJson: switch dispatches on wire string
      expect(out, contains('fromJson(value: string): Action'));
      expect(out, contains('case "return":'));
      expect(out, contains('case "cancel":'));
      expect(out, contains('return Action.return;'));
      expect(out, contains('return Action.cancel;'));
      expect(out, contains('throw new Error(`Invalid Action: \${value}`)'));
    });

    test('type: namespace with scalar, enum, nested type, list, nullable fields', () {
      const schema = '''
        enum Role { admin user }
        type Address { street: String! city: String! }
        type User {
          id: ID!
          name: String
          role: Role!
          nullableRole: Role
          address: Address!
          nullableAddress: Address
          tags: [String!]!
          nullableTags: [String!]
        }
      ''';

      final g = GLParser(reservedWords: typescriptReservedWords);
      g.parse(schema);

      final def = g.types['User']!;
      final serializer = TypeScriptSerializer(g, importPrefix: '');
      final out = serializer.doSerializeTypeDefinition(def);
      print(out);
      // Interface still emitted
      expect(out, contains('export interface User'));

      // Namespace wraps toJson and fromJson
      expect(out, contains('export namespace User'));
      expect(out, contains('toJson(obj: User): Record<string, unknown>'));
      expect(out, contains('fromJson(json: Record<string, unknown>): User'));

      // Scalar non-nullable: no transformation in toJson
      expect(out, contains('"id": obj.id'));
      // Scalar nullable: type assertion in fromJson
      expect(out, contains('"name": obj.name'));
      expect(out, contains('name: json["name"] as string | null'));

      // Enum non-nullable toJson and fromJson
      expect(out, contains('"role": Role.toJson(obj.role)'));
      expect(out, contains('role: Role.fromJson(json["role"] as string)'));

      // Enum nullable: null guard
      expect(out, contains('obj.nullableRole != null ? Role.toJson(obj.nullableRole) : null'));
      expect(out, contains('json["nullableRole"] != null ? Role.fromJson(json["nullableRole"] as string) : null'));

      // Nested type non-nullable
      expect(out, contains('"address": Address.toJson(obj.address)'));
      expect(out, contains('address: Address.fromJson(json["address"] as Record<string, unknown>)'));

      // Nested type nullable
      expect(out, contains('obj.nullableAddress != null ? Address.toJson(obj.nullableAddress) : null'));
      expect(out, contains('json["nullableAddress"] != null ? Address.fromJson(json["nullableAddress"] as Record<string, unknown>) : null'));

      // List non-nullable
      expect(out, contains('"tags": obj.tags.map((e0) => e0)'));
      expect(out, contains('tags: (json["tags"] as unknown[]).map((e0) => e0 as string)'));

      // List nullable
      expect(out, contains('obj.nullableTags != null ? obj.nullableTags.map((e0) => e0) : null'));
      expect(out, contains('json["nullableTags"] != null ? (json["nullableTags"] as unknown[]).map((e0) => e0 as string) : null'));
    });

    test('input: namespace emitted alongside interface', () {
      const schema = '''
        input CreateUserInput {
          name: String!
          age: Int
        }
      ''';

      final g = GLParser(reservedWords: typescriptReservedWords);
      g.parse(schema);

      final def = g.inputs['CreateUserInput']!;
      final serializer = TypeScriptSerializer(g, importPrefix: '');
      final out = serializer.doSerializeInputDefinition(def);

      expect(out, contains('export interface CreateUserInput'));
      expect(out, contains('export namespace CreateUserInput'));
      expect(out, contains('toJson(obj: CreateUserInput): Record<string, unknown>'));
      expect(out, contains('fromJson(json: Record<string, unknown>): CreateUserInput'));

      expect(out, contains('"name": obj.name'));
      expect(out, contains('name: json["name"] as string'));
      expect(out, contains('"age": obj.age'));
      expect(out, contains('age: json["age"] as number | null'));
    });

    test('union interface: fromJson dispatches on __typename', () {
      const schema = '''
        interface Animal { name: String! }
        type Dog implements Animal { name: String! }
        type Cat implements Animal { name: String! }
      ''';

      final g = GLParser(reservedWords: typescriptReservedWords);
      g.parse(schema);

      final def = g.interfaces['Animal']!;
      final serializer = TypeScriptSerializer(g, importPrefix: '');
      final out = serializer.doSerializeTypeDefinition(def);

      expect(out, contains('export type Animal = Dog | Cat'));
      expect(out, contains('export namespace Animal'));
      expect(out, contains('fromJson(json: Record<string, unknown>): Animal'));
      expect(out, contains('json["__typename"] as string'));
      expect(out, contains('case "Dog":'));
      expect(out, contains('return Dog.fromJson(json)'));
      expect(out, contains('case "Cat":'));
      expect(out, contains('return Cat.fromJson(json)'));
      expect(out, contains('throw new Error(`Unknown Animal: \${json["__typename"]}`)'));
    });

  });

  group('nested list serialization', () {
    test('[[Item]!] — nullable outer list of non-null inner lists of nullable type', () {
      const schema = '''
        type Item { id: ID! }
        type Report {
          matrix: [[Item]!]
        }
      ''';

      final g = GLParser(reservedWords: typescriptReservedWords);
      g.parse(schema);

      final def = g.types['Report']!;
      final serializer = TypeScriptSerializer(g, importPrefix: '');
      final out = serializer.doSerializeTypeDefinition(def);

      print(out);

      // toJson: outer null guard → inner map → element null guard + Item.toJson
      expect(out, contains(
        'obj.matrix != null ? obj.matrix.map((e0) => e0.map((e1) => e1 != null ? Item.toJson(e1) : null)) : null',
      ));
      // fromJson: outer null guard → cast outer → inner map → cast inner → element null guard + Item.fromJson
      expect(out, contains(
        'json["matrix"] != null ? (json["matrix"] as unknown[]).map((e0) => (e0 as unknown[]).map((e1) => e1 != null ? Item.fromJson(e1 as Record<string, unknown>) : null)) : null',
      ));
    });
  });
}
