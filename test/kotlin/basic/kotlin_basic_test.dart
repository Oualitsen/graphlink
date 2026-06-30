import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:test/test.dart';

KotlinSerializer _serializer(GLParser g, {bool inputsAsDataClass = true, bool typesAsDataClass = true}) =>
    KotlinSerializer(
      g,
      importPrefix: 'com.example',
      generateJsonMethods: true,
      inputsAsDataClass: inputsAsDataClass,
      typesAsDataClass: typesAsDataClass,
    );

/// Trims every line so indentation never breaks containsAllInOrder checks.
Iterable<String> lines(String s) => s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

void main() {
  // ── Enum ──────────────────────────────────────────────────────────────────

  group('enum', () {
    late GLParser g;
    setUp(() {
      g = GLParser()..parse('enum Status { active inactive }');
    });

    test('values', () {
      final out = _serializer(g).serializeEnumDefinition(g.enums['Status']!);
      expect(lines(out), containsAllInOrder(['enum class Status {', 'active, inactive;']));
    });

    test('toJson', () {
      final out = _serializer(g).serializeEnumDefinition(g.enums['Status']!);
      expect(lines(out), contains('fun toJson(): String = name'));
    });

    test('fromJson — nullable return', () {
      final out = _serializer(g).serializeEnumDefinition(g.enums['Status']!);
      expect(lines(out), contains('fun fromJson(value: String?): Status? = value?.let { valueOf(it) }'));
    });
  });

  // ── Input — data class ─────────────────────────────────────────────────────

  group('input data class', () {
    late GLParser g;
    late String out;

    setUp(() {
      g = GLParser()..parse('''
        scalar Long
        enum Role { admin user }
        input AddressInput { city: String! }
        input CreateUserInput {
          id: ID
          name: String!
          age: Int!
          score: Float
          active: Boolean!
          bigNum: Long
          role: Role
          role2: Role!
          address: AddressInput
          tags: [String!]!
          roles: [Role!]!
          optRoles: [Role]
        }
      ''');
      out = _serializer(g).doSerializeInputDefinition(g.inputs['CreateUserInput']!);
    });

    test('class keyword is data class', () {
      expect(lines(out), contains('data class CreateUserInput('));
    });

    test('non-nullable fields use val without default', () {
      expect(lines(out), contains('val name: String,'));
      expect(lines(out), contains('val age: Int,'));
      expect(lines(out), contains('val active: Boolean,'));
    });

    test('nullable fields have = null default', () {
      expect(lines(out), contains('val id: String? = null,'));
      expect(lines(out), contains('val score: Double? = null,'));
      expect(lines(out), contains('val role: Role? = null,'));
    });

    test('nested input field', () {
      expect(lines(out), contains('val address: AddressInput? = null,'));
    });

    test('list fields', () {
      expect(lines(out), contains('val tags: List<String>,'));
      expect(lines(out), contains('val roles: List<Role>,'));
      expect(lines(out), contains('val optRoles: List<Role?>? = null,'));
    });

    test('toJson emits mapOf with all keys', () {
      expect(lines(out), containsAllInOrder([
        'fun toJson(): Map<String, Any?> = mapOf(',
        '"id" to id,',
        '"name" to name,',
        '"role" to role?.toJson(),',
        '"role2" to role2.toJson(),',
        '"address" to address?.toJson(),',
        '"tags" to tags,',
        '"roles" to roles.map { e0 -> e0.toJson() },',
        '"optRoles" to optRoles?.map { e0 -> e0?.toJson() },',
      ]));
    });

    test('fromJson in companion object', () {
      expect(lines(out), containsAllInOrder([
        'companion object {',
        'fun fromJson(map: Map<String, Any?>): CreateUserInput = CreateUserInput(',
        'id = map["id"] as? String,',
        'name = map["name"] as String,',
        'age = (map["age"] as Number).toInt(),',
        'score = (map["score"] as? Number)?.toDouble(),',
        'active = map["active"] as Boolean,',
        'bigNum = (map["bigNum"] as? Number)?.toLong(),',
        'role = (map["role"] as? String)?.let { Role.fromJson(it) },',
        'role2 = Role.fromJson(map["role2"] as String)!!,',
        'address = (map["address"] as? Map<*, *>)?.let { AddressInput.fromJson(it as Map<String, Any?>) },',
        'tags = (map["tags"] as List<*>).map { e0 -> e0 as String },',
        'roles = (map["roles"] as List<*>).map { e0 -> Role.fromJson(e0 as String)!! },',
      ]));
    });

    test('no equals/hashCode in data class', () {
      expect(out, isNot(contains('override fun equals')));
      expect(out, isNot(contains('override fun hashCode')));
    });
  });

  // ── Input — open class ─────────────────────────────────────────────────────

  group('input open class', () {
    late GLParser g;
    late String out;

    setUp(() {
      g = GLParser()..parse('''
        input CreateUserInput {
          name: String!
          email: String!
          age: Int
        }
      ''');
      out = _serializer(g, inputsAsDataClass: false).doSerializeInputDefinition(g.inputs['CreateUserInput']!);
    });

    test('class keyword is open class', () {
      expect(lines(out), contains('open class CreateUserInput('));
    });

    test('fields use var', () {
      expect(lines(out), contains('var name: String,'));
      expect(lines(out), contains('var email: String,'));
      expect(lines(out), contains('var age: Int? = null,'));
    });

    test('has explicit equals', () {
      expect(lines(out), containsAllInOrder([
        'override fun equals(other: Any?): Boolean {',
        'if (other !is CreateUserInput) return false',
        'return name == other.name && email == other.email && age == other.age',
      ]));
    });

    test('has explicit hashCode', () {
      expect(lines(out), contains('override fun hashCode(): Int = Objects.hash(name, email, age)'));
    });
  });

  // ── Type — data class ──────────────────────────────────────────────────────

  group('type data class', () {
    late GLParser g;
    late String out;

    setUp(() {
      g = GLParser()..parse('''
        enum Role { admin user }
        type Address { city: String! }
        type User {
          id: ID!
          name: String!
          email: String
          role: Role!
          address: Address
          tags: [String!]!
        }
      ''');
      out = _serializer(g).doSerializeTypeDefinition(g.types['User']!);
    });

    test('class keyword is data class', () {
      expect(lines(out), contains('data class User('));
    });

    test('non-nullable fields', () {
      expect(lines(out), contains('val id: String,'));
      expect(lines(out), contains('val name: String,'));
    });

    test('nullable fields have default null', () {
      expect(lines(out), contains('val email: String? = null,'));
      expect(lines(out), contains('val address: Address? = null,'));
    });

    test('toJson emits all fields', () {
      expect(lines(out), containsAllInOrder([
        'fun toJson(): Map<String, Any?> = mapOf(',
        '"id" to id,',
        '"name" to name,',
        '"email" to email,',
        '"role" to role.toJson(),',
        '"address" to address?.toJson(),',
        '"tags" to tags,',
      ]));
    });

    test('fromJson parses all fields', () {
      expect(lines(out), containsAllInOrder([
        'fun fromJson(map: Map<String, Any?>): User = User(',
        'id = map["id"] as String,',
        'name = map["name"] as String,',
        'email = map["email"] as? String,',
        'role = Role.fromJson(map["role"] as String)!!,',
        'address = (map["address"] as? Map<*, *>)?.let { Address.fromJson(it as Map<String, Any?>) },',
      ]));
    });
  });

  // ── Type — open class ──────────────────────────────────────────────────────

  group('type open class', () {
    late GLParser g;
    late String out;

    setUp(() {
      g = GLParser()..parse('''
        type User {
          id: ID!
          name: String!
        }
      ''');
      out = _serializer(g, typesAsDataClass: false).doSerializeTypeDefinition(g.types['User']!);
    });

    test('class keyword is open class', () {
      expect(lines(out), contains('open class User('));
    });

    test('fields use var', () {
      expect(lines(out), contains('var id: String,'));
      expect(lines(out), contains('var name: String,'));
    });

    test('has explicit equals and hashCode', () {
      expect(lines(out), contains('override fun equals(other: Any?): Boolean {'));
      expect(lines(out), contains('override fun hashCode(): Int = Objects.hash(id, name)'));
    });
  });

  // ── Interface ──────────────────────────────────────────────────────────────

  group('interface declaration', () {
    late GLParser g;
    late String out;

    setUp(() {
      g = GLParser()..parse('''
        interface Node {
          id: ID!
        }
        type User implements Node {
          id: ID!
          name: String!
        }
      ''');
      out = _serializer(g).doSerializeTypeDefinition(g.interfaces['Node']!);
    });

    test('emits interface keyword', () {
      expect(lines(out), contains('interface Node {'));
    });

    test('fields are val property declarations', () {
      expect(lines(out), contains('val id: String'));
    });

    test('companion object with fromJson', () {
      expect(lines(out), containsAllInOrder([
        'companion object {',
        'fun fromJson(map: Map<String, Any?>): Node = when (map["__typename"] as String) {',
        '"User" -> User.fromJson(map)',
      ]));
      expect(out, contains('else -> throw IllegalArgumentException'));
    });
  });

  // ── Type implementing interface ────────────────────────────────────────────

  group('type implementing interface', () {
    late GLParser g;

    setUp(() {
      g = GLParser()..parse('''
        interface Node {
          id: ID!
        }
        interface Named {
          name: String!
        }
        type User implements Node & Named {
          id: ID!
          name: String!
          email: String
        }
      ''');
    });

    test('data class has override val for interface fields', () {
      final out = _serializer(g).doSerializeTypeDefinition(g.types['User']!);
      expect(lines(out), contains('override val id: String,'));
      expect(lines(out), contains('override val name: String,'));
      expect(lines(out), contains('val email: String? = null,'));
    });

    test('implements clause lists all interfaces', () {
      final out = _serializer(g).doSerializeTypeDefinition(g.types['User']!);
      expect(out, contains('Node'));
      expect(out, contains('Named'));
    });

    test('open class uses override var for interface fields', () {
      final out = _serializer(g, typesAsDataClass: false).doSerializeTypeDefinition(g.types['User']!);
      expect(lines(out), contains('override var id: String,'));
      expect(lines(out), contains('override var name: String,'));
    });
  });

  // ── Interface with multiple implementors ──────────────────────────────────

  group('interface fromJson dispatches on __typename', () {
    late GLParser g;
    late String out;

    setUp(() {
      g = GLParser()..parse('''
        interface Animal {
          id: ID!
        }
        type Dog implements Animal {
          id: ID!
          breed: String!
        }
        type Cat implements Animal {
          id: ID!
          color: String!
        }
      ''');
      out = _serializer(g).doSerializeTypeDefinition(g.interfaces['Animal']!);
    });

    test('when branches for all implementors', () {
      expect(lines(out), contains('"Dog" -> Dog.fromJson(map)'));
      expect(lines(out), contains('"Cat" -> Cat.fromJson(map)'));
    });

    test('else branch throws', () {
      expect(out, contains('else -> throw IllegalArgumentException'));
    });
  });
}
