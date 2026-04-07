import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_controller.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_shcema_mapping.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';

class GLService extends GLInterfaceDefinition {
  final Map<String, GLQueryType> _fieldType = {};
  final Map<String, GLSchemaMapping> _mappings = {};

  GLService(
      {required super.name,
      required super.nameDeclared,
      required super.fields,
      required super.directives,
      required super.interfaceNames})
      : super(extension: false);

  void setFieldType(String fieldName, GLQueryType type) {
    _fieldType[fieldName] = type;
  }

  GLQueryType? getTypeByFieldName(String fieldName) {
    return _fieldType[fieldName];
  }

  void addMapping(GLSchemaMapping mapping) {
    var m = _mappings[mapping.key];
    if (m == null || m.batch == null || (m.batch == false && m.batch == true)) {
      _mappings[mapping.key] = mapping;
    }
  }

  List<GLSchemaMapping> get mappings => _mappings.values.toList();
  List<GLSchemaMapping> get serviceMapping =>
      _mappings.values.where((e) => !e.forbid && !e.identity).toList();

  @override
  Set<GLToken> getImportDependecies(GLParser g) {
    var mappings = this is GLController ? this.mappings : serviceMapping;
    if (mappings.isEmpty) {
      return super.getImportDependecies(g);
    }
    var result = {...super.getImportDependecies(g)};

    for (var m in mappings) {
      var typeToken = g.getTokenByKey(m.type.token);

      if (filterDependecy(typeToken, g)) {
        result.add(typeToken!);
      } else {
        result.addAll(_getTokenFields(typeToken, g));
      }
      var fieldToken = g.getTokenByKey(m.field.type.token);
      if (filterDependecy(fieldToken, g)) {
        result.add(fieldToken!);
      }
      for (var arg in m.field.arguments) {
        var argToken = g.getTokenByKey(arg.type.token);
        if (filterDependecy(argToken, g)) {
          result.add(argToken!);
        }
      }

      var mappedToToken = _getMappedTo(g, typeToken);
      if (mappedToToken != null) {
        result.add(mappedToToken);
      }
    }
    return result;
  }

  GLToken? _getMappedTo(GLParser g, GLToken? token) {
    if (token is GLDirectivesMixin) {
      var mappedTo = (token as GLDirectivesMixin)
          .getDirectiveByName(glSkipOnServer)
          ?.getArgValueAsString(glMapTo);
      if (filterDependecy(g.types[mappedTo], g)) {
        return g.types[mappedTo];
      }
    }
    return null;
  }

  List<GLToken> _getTokenFields(GLToken? typeToken, GLParser g) {
    if (typeToken == null || typeToken is! GLTypeDefinition) {
      return [];
    }
    // check fields
    var result = <GLToken>[];
    // get all fields that are skipped on server

    var fields = typeToken.fields
        .where((f) => f.getDirectiveByName(glSkipOnServer) != null);
    for (var f in fields) {
      var token = g.getTokenByKey(f.type.token);
      if (filterDependecy(token, g)) {
        result.add(token!);
      } else {
        result.addAll(_getTokenFields(token, g));
      }
    }
    return result;
  }

  static String getValidationMethodName(String methodName) {
    return '${glValidateMethodPrefix}${methodName.firstUp}';
  }

  @override
  Set<String> getImports(GLParser g) {
    var result =  [...super.getImports(g)];
    if(this is! GLController) {
      result.removeWhere((e) => e.startsWith('org.springframework.graphql.data.method.annotation'));
    }
    return result.toSet();
  }
}
