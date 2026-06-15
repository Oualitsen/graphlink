import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
  interface IAnimal {
    id: ID!
    name: String!
    description: String
  }

  type Animal implements IAnimal @glServerLenient {
    id: ID!
    name: String!
    description: String
    age: Int
  }

  input AddAnimalInput {
    name: String!
    description: String
    age: Int
    yearOfBirth: Int!
  }

  type Query {
    getAnimal(id: ID!): Animal
  }
''';

GLParser _clientParser() {
  final g = GLParser(
    mode: CodeGenerationMode.client,
    generateAllFieldsFragments: true,
    autoGenerateQueries: true,
  );
  g.parse(_schema);
  return g;
}

GLParser _serverParser() {
  final g = GLParser(mode: CodeGenerationMode.server);
  g.parse(_schema);
  return g;
}

void main() {
  group('jspecify — client mode', () {
    late GLParser g;
    late JavaSerializer serializer;

    setUp(() {
      g = _clientParser();
      serializer = JavaSerializer(g, importPrefix: 'com.example', jspecify: true);
    });

    test('type: imports are emitted', () {
      final output = serializer.serializeTypeDefinition(g.projectedTypes['Animal']!);
      expect(output, contains('import org.jspecify.annotations.NonNull;'));
      expect(output, contains('import org.jspecify.annotations.Nullable;'));
    });

    test('type: fields get @NonNull / @Nullable', () {
      final output = serializer.serializeTypeDefinition(g.projectedTypes['Animal']!);
      expect(output, stringContainsInOrder([
        '@NonNull', 'private String id',
        '@NonNull', 'private String name',
        '@Nullable', 'private String description',
        '@Nullable', 'private Integer age',
      ]));
    });

    test('type: getters get @NonNull / @Nullable', () {
      final output = serializer.serializeTypeDefinition(g.projectedTypes['Animal']!);
      expect(output, stringContainsInOrder([
        '@NonNull', 'public String getId',
        '@NonNull', 'public String getName',
        '@Nullable', 'public String getDescription',
        '@Nullable', 'public Integer getAge',
      ]));
    });

    test('type: setters get @NonNull / @Nullable (mutable fields)', () {
      final mutableSerializer = JavaSerializer(
        g,
        importPrefix: 'com.example',
        jspecify: true,
        immutableTypeFields: false,
      );
      final output = mutableSerializer.serializeTypeDefinition(g.projectedTypes['Animal']!);
      expect(output, stringContainsInOrder([
        'public void setId(@NonNull String id)',
        'public void setName(@NonNull String name)',
        'public void setDescription(@Nullable String description)',
        'public void setAge(@Nullable Integer age)',
      ]));
    });

    test('interface: fields get @NonNull / @Nullable', () {
      final iAnimal = g.projectedInterfaces['IAnimal']!;
      final output = serializer.serializeInterface(iAnimal, getters: true);
      expect(output, stringContainsInOrder([
        '@NonNull', 'String getId',
        '@NonNull', 'String getName',
        '@Nullable', 'String getDescription',
      ]));
    });

    test('input: imports are emitted', () {
      final output = serializer.serializeInputDefinition(g.inputs['AddAnimalInput']!);
      expect(output, contains('import org.jspecify.annotations.NonNull;'));
      expect(output, contains('import org.jspecify.annotations.Nullable;'));
    });

    test('input: fields get @NonNull / @Nullable', () {
      final output = serializer.serializeInputDefinition(g.inputs['AddAnimalInput']!);
      expect(output, stringContainsInOrder([
        '@NonNull', 'private final String name',
        '@Nullable', 'private final String description',
        '@Nullable', 'private final Integer age',
      ]));
    });

    test('input: getters get @NonNull / @Nullable', () {
      final output = serializer.serializeInputDefinition(g.inputs['AddAnimalInput']!);
      expect(output, stringContainsInOrder([
        '@NonNull', 'public String getName',
        '@Nullable', 'public String getDescription',
        '@Nullable', 'public Integer getAge',
      ]));
    });

    test('primitive types are not annotated', () {
      // fresh parser so applyJspecifyAnnotations runs with the primitive type map
      final freshG = _clientParser();
      final primitiveSerializer = JavaSerializer(
        freshG,
        importPrefix: 'com.example',
        jspecify: true,
        typeMapOverrides: {'Int': 'int'},
      );
      final input = freshG.inputs['AddAnimalInput']!;
      final output = primitiveSerializer.serializeInputDefinition(input);
      print(output);
      // age maps to primitive int — no annotation
      expect(output, contains('private final int yearOfBirth'));
      final yearOfBirth = input.getFieldByName('yearOfBirth')!;
      expect(yearOfBirth.getDirectives().length, 0);
      // name still gets @NonNull (String is a reference type)
      expect(output, stringContainsInOrder(['@NonNull', 'private final String name']));
    });

    test('builder: fields get @NonNull / @Nullable', () {
      final output = serializer.serializeTypeDefinition(g.projectedTypes['Animal']!);
      expect(output, stringContainsInOrder([
        'static class Builder',
        '@NonNull', 'private String id',
        '@NonNull', 'private String name',
        '@Nullable', 'private String description',
        '@Nullable', 'private Integer age',
      ]));
    });

    test('builder: setter arguments get @NonNull / @Nullable', () {
      final output = serializer.serializeTypeDefinition(g.projectedTypes['Animal']!);
      expect(output, stringContainsInOrder([
        'static class Builder',
        'public Builder id(@NonNull String id)',
        'public Builder name(@NonNull String name)',
        'public Builder description(@Nullable String description)',
        'public Builder age(@Nullable Integer age)',
      ]));
    });
  });

  group('jspecify — records', () {
    test('input record: components get @NonNull / @Nullable', () {
      final g = _clientParser();
      final serializer = JavaSerializer(
        g,
        importPrefix: 'com.example',
        jspecify: true,
        inputsAsRecords: true,
      );
      final output = serializer.serializeInputDefinition(g.inputs['AddAnimalInput']!);
      expect(output, stringContainsInOrder([
        '@NonNull String name',
        '@Nullable String description',
        '@Nullable Integer age',
      ]));
    });

    test('input record: primitive components are not annotated', () {
      final g = _clientParser();
      final serializer = JavaSerializer(
        g,
        importPrefix: 'com.example',
        jspecify: true,
        inputsAsRecords: true,
        typeMapOverrides: {'Int': 'int'},
      );
      final output = serializer.serializeInputDefinition(g.inputs['AddAnimalInput']!);
      expect(output, contains('int yearOfBirth'));
      expect(output, isNot(contains('@NonNull int yearOfBirth')));
      expect(output, isNot(contains('@Nullable int yearOfBirth')));
    });

    test('type record: components get @NonNull / @Nullable', () {
      final g = _clientParser();
      final serializer = JavaSerializer(
        g,
        importPrefix: 'com.example',
        jspecify: true,
        typesAsRecords: true,
      );
      final output = serializer.serializeTypeDefinition(g.projectedTypes['Animal']!);
      expect(output, stringContainsInOrder([
        '@NonNull String id',
        '@NonNull String name',
        '@Nullable String description',
        '@Nullable Integer age',
      ]));
    });

    test('type record: server mode all components are @Nullable', () {
      final g = _serverParser();
      final serializer = JavaSerializer(
        g,
        importPrefix: 'com.example',
        jspecify: true,
        typesAsRecords: true,
      );
      final output = serializer.serializeTypeDefinition(g.getTypeByName('Animal')!);
      expect(output, isNot(contains('@NonNull')));
      expect(output, stringContainsInOrder([
        '@Nullable String id',
        '@Nullable String name',
        '@Nullable String description',
        '@Nullable Integer age',
      ]));
    });
  });

  group('jspecify — server mode', () {
    late GLParser g;
    late JavaSerializer serializer;

    setUp(() {
      g = _serverParser();
      serializer = JavaSerializer(
        g,
        importPrefix: 'com.example',
        jspecify: true,
        immutableTypeFields: false,
      );
    });

    test('type: all fields are @Nullable (forceFieldNullable)', () {
      final output = serializer.serializeTypeDefinition(g.getTypeByName('Animal')!);
      expect(output, contains('import org.jspecify.annotations.Nullable;'));
      expect(output, isNot(contains('@NonNull')));
      expect(output, stringContainsInOrder([
        '@Nullable', 'String id',
        '@Nullable', 'String name',
        '@Nullable', 'String description',
        '@Nullable', 'Integer age',
      ]));
    });

    test('type: getters are all @Nullable in server mode', () {
      final output = serializer.serializeTypeDefinition(g.getTypeByName('Animal')!);
      expect(output, stringContainsInOrder([
        '@Nullable', 'public String getId',
        '@Nullable', 'public String getName',
        '@Nullable', 'public String getDescription',
        '@Nullable', 'public Integer getAge',
      ]));
    });

    test('type: setters are all @Nullable in server mode', () {
      final output = serializer.serializeTypeDefinition(g.getTypeByName('Animal')!);
      expect(output, stringContainsInOrder([
        'public void setId(@Nullable String id)',
        'public void setName(@Nullable String name)',
        'public void setDescription(@Nullable String description)',
        'public void setAge(@Nullable Integer age)',
      ]));
    });

    test('input: respects actual nullability (not forced)', () {
      final output = serializer.serializeInputDefinition(g.inputs['AddAnimalInput']!);
      expect(output, contains('import org.jspecify.annotations.NonNull;'));
      expect(output, contains('import org.jspecify.annotations.Nullable;'));
      expect(output, stringContainsInOrder([
        '@NonNull', 'private final String name',
        '@Nullable', 'private final String description',
        '@Nullable', 'private final Integer age',
      ]));
    });
  });
}
