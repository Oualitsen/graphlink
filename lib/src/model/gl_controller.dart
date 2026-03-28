import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_token.dart';

class GLController extends GLService {
  final String serviceName;
  GLController({
    required this.serviceName,
    required super.name,
    required super.nameDeclared,
    required super.fields,
    required super.interfaceNames,
    required super.directives,
  });

  static GLController ofService(GLService service) {
    var ctrl = GLController(
      serviceName: service.token,
      name: "${service.token}Controller".toToken(),
      nameDeclared: service.nameDeclared,
      fields: [],
      interfaceNames: {},
      directives: [],
    );
    for (var f in service.fields) {
      var validationDirective = f.getDirectiveByName(glValidate);
      if (validationDirective == null || !validationDirective.generated) {
        ctrl.addField(f);
        ctrl.setFieldType(
            f.name.token, service.getTypeByFieldName(f.name.token)!);
      }
    }
    return ctrl;
  }

  @override
  Set<GLToken> getImportDependecies(GLParser g) {
    var result = {...super.getImportDependecies(g)};
    result.add(g.services[serviceName]!);
    return result;
  }
}
