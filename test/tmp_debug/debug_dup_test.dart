import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/java_spring_server_serializer.dart';

void main() {
  final GLParser g = GLParser(mode: CodeGenerationMode.server);
  g.parse('''
  directive @glRepository(
    glType: String!
    glIdType: String!
    glImport: String = "org.springframework.data.mongodb.repository.MongoRepository"
    glClass: String = "MongoRepository"
    glOnClient: Boolean = false
    glOnServer: Boolean = true
) on INTERFACE

  directive @glQuery(
    value: String!
    glClass: String = "@Query"
    glImport: String = "org.springframework.data.mongodb.repository.Query"
    glOnClient: Boolean = false
    glOnServer: Boolean = true
    glAnnotation: Boolean = true
) on FIELD_DEFINITION

  type Clinic {
    name: String
  }

  interface ClinicRepository @glRepository(glIdType: "String", glType: "Clinic") {
    findByZipCodeAndPhoneNumber( zipCode: String,  phoneNumber: String): [Clinic!]! @glQuery(value: "{ 'address.zipCode': ?0, 'phoneNumber': ?1 }")
}
''');

  var repo = g.repositories["ClinicRepository"]!;
  var field = repo.getFieldByName("findByZipCodeAndPhoneNumber")!;
  print('before serializer creation: directives=${field.getDirectives().map((d) => d.token).toList()}');

  var serializer = JavaSpringServerSerializer(g, packageName: "com.myorg");
  print('after serializer creation: directives=${field.getDirectives().map((d) => d.token).toList()}');

  var serialized = serializer.serializeRepository(repo);
  print('after serializeRepository: directives=${field.getDirectives().map((d) => d.token).toList()}');
  print(serialized);
}
