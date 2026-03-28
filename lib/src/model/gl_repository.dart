import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';

class GLRepository extends GLInterfaceDefinition {
  GLRepository({
    required super.name,
    required super.nameDeclared,
    required super.fields,
    required super.directives,
    required super.interfaceNames,
    required super.extension,
  }) : super();

  static GLRepository of(GLInterfaceDefinition iface) {
    return GLRepository(
      name: iface.tokenInfo,
      nameDeclared: iface.nameDeclared,
      fields: iface.fields,
      directives: iface.getDirectives(),
      interfaceNames: iface.interfaceNames,
      extension: iface.extension,
    );
  }

  @override
  Set<GLToken> getImportDependecies(GLParser g) {
    var result = {...super.getImportDependecies(g)};
    var repoDir = getDirectiveByName(glRepository)!;
    var token1 = _addDepency(g, repoDir.getArgValueAsString(glType));
    var token2 = _addDepency(g, repoDir.getArgValueAsString(glIdType));
    result.addAll([if (token1 != null) token1, if (token2 != null) token2]);
    return result;
  }

  @override
  Set<String> getImports(GLParser g) {
    var result = {...super.getImports(g)};
    var repoDir = getDirectiveByName(glRepository)!;
    result.addAll(_extractImports(repoDir.getArgValueAsString(glType), g));
    result.addAll(_extractImports(repoDir.getArgValueAsString(glIdType), g));
    return result;
  }

  Set<String> _extractImports(String? key, GLParser g) {
    if (key != null) {
      var token = g.getTokenByKey(key);
      if (token is GLDirectivesMixin) {
        return GLTokenWithFields.extractImports(
            token as GLDirectivesMixin, g.mode,
            skipOwnImports: true);
      }
    }
    return {};
  }

  GLToken? _addDepency(GLParser g, String? key) {
    if (key == null) {
      return null;
    }
    var repoTypeToken = g.getTokenByKey(key);
    if (filterDependecy(repoTypeToken, g)) {
      return repoTypeToken;
    }
    return null;
  }
}
