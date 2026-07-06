import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';

void main() {
  final GLParser g = GLParser(mode: CodeGenerationMode.server);
  g.parse('''
  type PersonCar @glSkipOnServer(mapTo: "Person") {
    person: Person!
    car: Car
  }
  type Person  {
    name: String
  }
  type Car {
    make: String
  }
  type Query {
    findPerson: [PersonCar!]! @glServiceName(name: "MainService")
  }
''');
  var mappingService = g.services[g.serviceMappingName("PersonCar")]!;
  for (var f in mappingService.getSerializableFields(g.mode)) {
    print('field ${f.name.token} type=${f.type.runtimeType} token=${f.type.token}');
    if (f.type is GLMapType) {
      var m = f.type as GLMapType;
      print('  keyType=${m.keyType.token} valueType=${m.valueType.token}');
    }
    var token = g.getTokenByKey(f.type.token);
    print('  resolvedToken=$token filterDependecy=${mappingService.filterDependecy(token, g)}');
  }
  print('---deps---');
  print(mappingService.getImportDependecies(g).map((e) => e.token));
}
