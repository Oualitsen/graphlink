import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_schema_mapping.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_token.dart';

class GLController extends GLService {
  final GLParser parser;
  final String serviceName;
  GLController({
    required this.serviceName,
    required super.name,
    required super.nameDeclared,
    required super.fields,
    required super.interfaceNames,
    required super.directives,
    required this.parser,
  });

  static GLController ofService(GLService service, GLParser parser) {
    var ctrl = GLController(
      serviceName: service.token,
      name: "${service.token}Controller".toToken(),
      nameDeclared: service.nameDeclared,
      fields: [],
      interfaceNames: {},
      directives: [],
      parser: parser,
    );
    for (var f in service.fields) {
      var validationDirective = f.getDirectiveByName(glValidate);
      if (validationDirective == null || !validationDirective.generated) {
        var typeToken = f.type.token;
        GLField targetField;
        if(parser.types.containsKey(typeToken) || parser.interfaces.containsKey(typeToken)) {
          var type = parser.getTokenByKey(f.type.token)! as GLTypeDefinition;
          targetField = f.ofType(f.type.ofNewName(type.serverProjectionName.toToken()));
        } else {
          targetField = f;
        }
        ctrl.addField(targetField);
        ctrl.setFieldType(
            f.name.token, service.getTypeByFieldName(f.name.token)!);
      }
    }
    return ctrl;
  }

  @override
  void addMapping(GLSchemaMapping mapping) {
    // @TODO we need to check if service is going to use projection on this type!
    String newTypeName = mapping.type.token;
    
    String newFieldTypeName = mapping.field.type.token;
    if(parser.interfaces.containsKey(newFieldTypeName) || parser.types.containsKey(newFieldTypeName)) {
      newFieldTypeName = GLTypeDefinition.getServerProjectionName(newFieldTypeName);
    }
    super.addMapping(mapping.ofNewTypes(newTypeName, newFieldTypeName, mapping.key));
  }


  @override
  Set<GLToken> getImportDependecies(GLParser g) {
    var result = {...super.getImportDependecies(g)};
    if(g.services.containsKey(serviceName)) {
      result.add(g.services[serviceName]!);
    }
    return result;
  }
}
