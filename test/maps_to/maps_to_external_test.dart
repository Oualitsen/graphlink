import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_maps_to_extension.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/dart/dart_serializer.dart';
import 'package:graphlink/src/serializers/go/go_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:graphlink/src/serializers/swift/swift_serializer.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
import 'package:test/test.dart';

String _schema(String import) => '''
type Query { noop: String }

type AddressEntity @glExternal(glClass: "AddressEntity", glImport: "$import") @glMapsTo(type: "Address") {
  street: String!
}

type Address @glMapsTo(type: "AddressEntity") {
  street: String!
}

type UserEntity @glExternal(glClass: "UserEntity", glImport: "$import") @glMapsTo(type: "User") {
  id: ID!
  nick: String
  addresses: [AddressEntity!]!
  home: AddressEntity
}

type User @glMapsTo(type: "UserEntity") {
  id: ID!
  nick: String!
  addresses: [Address!]!
  home: Address
}
''';

GLParser _parse(String import, {bool mapperAsClass = false}) =>
    GLParser(mode: CodeGenerationMode.server, mapperAsClass: mapperAsClass)..parse(_schema(import));

void main() {
  group('core', () {
    test('an external target also sends its generated source to a mapper class', () {
      final g = _parse('x');
      expect(g.mapperClassSources.map((s) => s.token), containsAll(['User', 'Address', 'UserEntity', 'AddressEntity']));
    });

    test('an external type generates no class', () {
      final g = _parse('x');
      expect(g.getSerializableTypes().map((t) => t.token), isNot(contains('UserEntity')));
    });

    test('a mapping that touches an external type is always a mapper class', () {
      final g = _parse('x');
      final java = JavaSerializer(g, importPrefix: 'com.acme');
      expect(java.serializeTypeDefinition(g.types['User']!), isNot(contains('toUserEntity')));
      expect(java.serializeMapperClass(g.types['User']!), isNotNull);
    });

    test('between generated types the default stays inline and has no mapper class', () {
      final g = GLParser(mode: CodeGenerationMode.server)
        ..parse('type Query { noop: String } type A @glMapsTo(type: "B") { id: ID! } type B { id: ID! }');
      final java = JavaSerializer(g, importPrefix: 'com.acme');
      expect(java.serializeTypeDefinition(g.types['A']!), contains('toB()'));
      expect(java.serializeMapperClass(g.types['A']!), isNull);
      expect(g.mapperClassSources, isEmpty);
    });

    test('mapperStyle class moves a generated mapping to a mapper class', () {
      final g = GLParser(mode: CodeGenerationMode.server, mapperAsClass: true)
        ..parse('type Query { noop: String } type A @glMapsTo(type: "B") { id: ID! } type B { id: ID! }');
      final java = JavaSerializer(g, importPrefix: 'com.acme');
      expect(java.serializeTypeDefinition(g.types['A']!), isNot(contains('toB()')));
      expect(java.serializeMapperClass(g.types['A']!)!, contains('public static B toB(A source)'));
    });
  });

  group('Java', () {
    test('external source to generated target', () {
      final g = _parse('com.acme.persistence.UserEntity');
      final out = JavaSerializer(g, importPrefix: 'com.acme').serializeMapperClass(g.types['UserEntity']!)!;
      expect(out, contains('import com.acme.persistence.UserEntity;'));
      expect(out, contains('import com.acme.mappers.AddressEntityMapper;'));
      expect(out, contains('public final class UserEntityMapper'));
      expect(out, contains('public static User toUser(UserEntity source, String defaultNick)'));
      expect(out, contains('.id(source.getId())'));
      expect(out, contains('AddressEntityMapper.toAddress(e0)'));
      expect(out, contains('source.getHome() != null ? AddressEntityMapper.toAddress(source.getHome()) : null'));
      expect(out, contains('.nick(source.getNick() != null ? source.getNick() : defaultNick)'));
    });

    test('generated source to external target uses a no-arg constructor and setters', () {
      final g = _parse('com.acme.persistence.UserEntity');
      final out = JavaSerializer(g, importPrefix: 'com.acme').serializeMapperClass(g.types['User']!)!;
      expect(out, contains('public static UserEntity toUserEntity(User source)'));
      expect(out, contains('UserEntity target = new UserEntity();'));
      expect(out, contains('target.setId(source.getId());'));
      expect(out, contains('return target;'));
    });
  });

  group('Kotlin', () {
    test('external source and external target', () {
      final g = _parse('com.acme.persistence.UserEntity', mapperAsClass: true);
      final kotlin = KotlinSerializer(g, importPrefix: 'com.acme');
      final fromEntity = kotlin.serializeMapperClass(g.types['UserEntity']!)!;
      expect(fromEntity, contains('object UserEntityMapper'));
      expect(fromEntity, contains('fun toUser(source: UserEntity, defaultNick: String): User'));
      expect(fromEntity, contains('nick = source.nick ?: defaultNick'));
      expect(fromEntity, contains('AddressEntityMapper.toAddress(e0)'));
      final toEntity = kotlin.serializeMapperClass(g.types['User']!)!;
      expect(toEntity, contains('fun toUserEntity(source: User): UserEntity = UserEntity().apply'));
      expect(toEntity, contains('id = source.id'));
    });
  });

  group('Dart', () {
    test('external source', () {
      final g = _parse('package:acme/persistence.dart');
      final out = DartSerializer(g, importPrefix: 'p').serializeMapperClass(g.types['UserEntity']!)!;
      expect(out, contains("import 'package:acme/persistence.dart';"));
      expect(out, contains("import 'p/mappers/address_entity_mapper.dart';"));
      expect(out, contains('class UserEntityMapper'));
      expect(out, contains('static User toUser(UserEntity source'));
      expect(out, contains('required String defaultNick'));
      expect(out, contains('AddressEntityMapper.toAddress(source.home!)'));
    });
  });

  group('TypeScript', () {
    test('external source', () {
      final g = _parse("import { UserEntity } from '../../persistence';");
      final out = TypeScriptSerializer(g, importPrefix: '').serializeMapperClass(g.types['UserEntity']!)!;
      expect(out, contains("import { UserEntity } from '../../persistence';"));
      expect(out, contains("import { AddressEntityMapper } from './address-entity-mapper.js';"));
      expect(out, contains('export namespace UserEntityMapper'));
      expect(out, contains('export function toUser(obj: UserEntity, defaultNick: string): User'));
      expect(out, contains('AddressEntityMapper.toAddress(e0)'));
    });
  });

  group('Python', () {
    test('external source', () {
      final g = _parse('from acme.persistence import UserEntity');
      final out = PythonSerializer(g).serializeMapperClass(g.types['UserEntity']!)!;
      expect(out, contains('from acme.persistence import UserEntity'));
      expect(out, contains('from .address_entity_mapper import AddressEntityMapper'));
      expect(out, contains('class UserEntityMapper:'));
      expect(out, contains('@staticmethod'));
      expect(out, contains('def to_user(source: UserEntity, *, default_nick: str) -> User:'));
      expect(out, contains('AddressEntityMapper.to_address(e0) for e0 in source.addresses'));
    });
  });

  group('Go', () {
    test('external source', () {
      final g = _parse('example.com/persistence');
      final out = GoSerializer(g).serializeMapperClass(g.types['UserEntity']!)!;
      expect(out, contains('"example.com/persistence"'));
      expect(out, contains('type UserEntityMapper struct'));
      expect(out, contains('func (UserEntityMapper) ToUser(source UserEntity, defaultNick string) User'));
      expect(out, contains('AddressEntityMapper{}.ToAddress(e0)'));
    });
  });

  group('Swift', () {
    test('external source', () {
      final g = _parse('Persistence');
      final out = SwiftSerializer(g, importPrefix: '').serializeMapperClass(g.types['UserEntity']!)!;
      expect(out, contains('import Persistence'));
      expect(out, contains('public enum UserEntityMapper'));
      expect(out, contains('public static func toUser(_ source: UserEntity, defaultNick: String) -> User'));
      expect(out, contains('nick: source.nick ?? defaultNick'));
      expect(out, contains('AddressEntityMapper.toAddress(e0)'));
    });
  });

  test('every language has a file name for its mapper', () {
    final g = _parse('x');
    final def = g.types['UserEntity']!;
    final serializers = <GLSerializer>[
      JavaSerializer(g, importPrefix: 'a'),
      KotlinSerializer(g, importPrefix: 'a'),
      DartSerializer(g, importPrefix: 'a'),
      TypeScriptSerializer(g, importPrefix: ''),
      PythonSerializer(g),
      GoSerializer(g),
      SwiftSerializer(g, importPrefix: ''),
    ];
    expect(serializers.map((s) => s.getMapperFileName(def)).toList(), [
      'UserEntityMapper.java',
      'UserEntityMapper.kt',
      'user_entity_mapper.dart',
      'user-entity-mapper.ts',
      'user_entity_mapper.py',
      'user_entity_mapper.go',
      'UserEntityMapper.swift',
    ]);
  });
}
