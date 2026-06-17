import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
enum Role { ADMIN USER }

input Address {
  city: String!
  zip: String!
}

input CreateUserInput {
  name: String!
  address: Address = {city: "Paris", zip: "75000"}
  contacts: [Address] = [{city: "Lyon", zip: "69000"}, {city: "Nice", zip: "06000"}]
  matrix: [[Address]] = [[{city: "Paris", zip: "75000"}], [{city: "Lyon", zip: "69000"}]]
}
''';

GLParser _parser() {
  final g = GLParser(identityFields: ['id'], mode: CodeGenerationMode.client);
  g.parse(_schema);
  return g;
}

void main() {
  group('Dart — nested input object defaults', () {
    test('generates correct constructor defaults', () {
      final g = _parser();
      final out = DartSerializer(g, importPrefix: '').serializeInputDefinition(g.inputs['CreateUserInput']!);
      print('=== Dart CreateUserInput ===\n$out');

      expect(out, contains("this.address = const Address(city: 'Paris', zip: '75000')"));
      expect(out, contains("this.contacts = const [Address(city: 'Lyon', zip: '69000'), Address(city: 'Nice', zip: '06000')]"));
      expect(out, contains("this.matrix = const [[Address(city: 'Paris', zip: '75000')], [Address(city: 'Lyon', zip: '69000')]]"));
    });
  });

  group('Kotlin — nested input object defaults', () {
    test('generates correct constructor defaults', () {
      final g = _parser();
      final out = KotlinSerializer(g, importPrefix: '').serializeInputDefinition(g.inputs['CreateUserInput']!);
      print('=== Kotlin CreateUserInput ===\n$out');

      expect(out, contains('address: Address? = Address(city = "Paris", zip = "75000")'));
      expect(out, contains('contacts: List<Address?>? = listOf(Address(city = "Lyon", zip = "69000"), Address(city = "Nice", zip = "06000"))'));
      expect(out, contains('matrix: List<List<Address?>?>? = listOf(listOf(Address(city = "Paris", zip = "75000")), listOf(Address(city = "Lyon", zip = "69000")))'));
    });
  });

  group('TypeScript — nested input object defaults', () {
    test('generates companion const with nested object defaults', () {
      final g = _parser();
      final out = TypeScriptSerializer(g, importPrefix: '').serializeInputDefinition(g.inputs['CreateUserInput']!);
      print('=== TypeScript CreateUserInput ===\n$out');

      expect(out, contains('address: { city: "Paris", zip: "75000" }'));
      expect(out, contains('contacts: [{ city: "Lyon", zip: "69000" }, { city: "Nice", zip: "06000" }]'));
      expect(out, contains('matrix: [[{ city: "Paris", zip: "75000" }], [{ city: "Lyon", zip: "69000" }]]'));
    });
  });

  group('Java — nested input object defaults', () {
    test('generates constructor assignments with positional constructor calls', () {
      final g = _parser();
      final out = JavaSerializer(g, importPrefix: '').serializeInputDefinition(g.inputs['CreateUserInput']!);
      print('=== Java CreateUserInput ===\n$out');

      // Fields are final — defaults go in the constructor, not field initializers.
      expect(out, contains('this.address = address != null ? address : new Address("Paris", "75000")'));
      expect(out, contains('Arrays.asList(new Address("Lyon", "69000"), new Address("Nice", "06000"))'));
      expect(out, contains('Arrays.asList(Arrays.asList(new Address("Paris", "75000")), Arrays.asList(new Address("Lyon", "69000")))'));
    });
  });
}
