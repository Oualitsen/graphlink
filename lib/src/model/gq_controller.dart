import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_service.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';

class GQController extends GQService {
  final String serviceName;
  GQController({
    required this.serviceName,
    required super.name,
    required super.nameDeclared,
    required super.fields,
    required super.interfaceNames,
    required super.directives,
  });

  static GQController ofService(GQService service) {
    var ctrl = GQController(
      serviceName: service.token,
      name: "${service.token}Controller".toToken(),
      nameDeclared: service.nameDeclared,
      fields: [],
      interfaceNames: {},
      directives: [],
    );
    for (var f in service.fields) {
      ctrl.addField(f);
      ctrl.setFieldType(f.name.token, service.getTypeByFieldName(f.name.token)!);
    }
    return ctrl;
  }

  @override
  Set<GQToken> getImportDependecies(GQGrammar g) {
    var result = {...super.getImportDependecies(g)};
    result.add(g.services[serviceName]!);
    return result;
  }
}
