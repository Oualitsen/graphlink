import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/spring_server_serializer.dart';
import 'package:test/test.dart';

void main() {
  final typeMapping = {
    "ID": "String",
    "String": "String",
    "Float": "Double",
    "Int": "Integer",
    "Boolean": "Boolean",
  };

  test('batch: true with field arguments throws', () {
    final g = GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);
    g.parse('''
      type Query { getUser: User }
      type User {
        name: String
        vehicles(year: Int, category: String): [Vehicle!]! @glSkipOnServer(batch: true)
      }
      type Vehicle {
        id: String
      }
    ''');
    expect(
      () => SpringServerSerializer(g),
      throwsA(isA<ParseException>()),
    );
  });

  test('schema mapping with arguments generates correct controller and service',
      () {
    final g = GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);
    g.parse('''
      type Query { getUser: User }
      type User {
        name: String
        vehicles(year: Int, category: String): [Vehicle!]! @glSkipOnServer(batch: false)
      }
      type Vehicle {
        id: String
      }
    ''');

    final serializer = SpringServerSerializer(g);
    final ctrl = g.controllers[g.controllerMappingName('User')]!;
    final service = g.services[g.serviceMappingName('User')]!;

    final controllerCode = serializer.serializeController(ctrl, 'com.example');
    final serviceCode = serializer.serializeService(service, 'com.example');

    // controller: @SchemaMapping with @Argument params and correct service call
    expect(controllerCode, contains('@SchemaMapping(typeName="User", field="vehicles")'));
    expect(controllerCode, contains('public CompletableFuture<List<Vehicle>> userVehicles(User value, @Argument Integer year, @Argument String category)'));
    expect(controllerCode, contains('return CompletableFuture.supplyAsync(() -> userSchemaMappingsService.userVehicles(value, year, category));'));
    expect(controllerCode, contains('import org.springframework.graphql.data.method.annotation.Argument'));

    // service: no @Argument annotation
    expect(serviceCode, contains('List<Vehicle> userVehicles(User value, Integer year, String category);'));
    expect(serviceCode, isNot(contains('@Argument')));
  });
}
