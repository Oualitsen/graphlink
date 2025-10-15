import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';
import 'package:retrofit_graphql/src/model/gq_controller.dart';
import 'package:retrofit_graphql/src/model/gq_directives_mixin.dart';
import 'package:retrofit_graphql/src/model/gq_interface_definition.dart';
import 'package:retrofit_graphql/src/model/gq_queries.dart';
import 'package:retrofit_graphql/src/model/gq_shcema_mapping.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';

class GQService extends GQInterfaceDefinition {
  final Map<String, GQQueryType> _fieldType = {};
  final Map<String, GQSchemaMapping> _mappings = {};

  GQService(
      {required super.name,
      required super.nameDeclared,
      required super.fields,
      required super.directives,
      required super.interfaceNames});

  void setFieldType(String fieldName, GQQueryType type) {
    _fieldType[fieldName] = type;
  }

  GQQueryType? getTypeByFieldName(String fieldName) {
    return _fieldType[fieldName];
  }

  void addMapping(GQSchemaMapping mapping) {
    var m = _mappings[mapping.key];
    if (m == null || (!m.batch && mapping.batch)) {
      _mappings[mapping.key] = mapping;
    }
  }

  List<GQSchemaMapping> get mappings => _mappings.values.toList();
  List<GQSchemaMapping> get serviceMapping => _mappings.values.where((e) => !e.forbid && !e.identity).toList();

  @override
  Set<GQToken> getImportDependecies(GQGrammar g) {
    var mappings = this is GQController ? this.mappings : serviceMapping;
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

  GQToken? _getMappedTo(GQGrammar g, GQToken? token) {
    if (token is GQDirectivesMixin) {
      var mappedTo = (token as GQDirectivesMixin).getDirectiveByName(gqSkipOnServer)?.getArgValueAsString(gqMapTo);
      if (filterDependecy(g.types[mappedTo], g)) {
        return g.types[mappedTo];
      }
    }
    return null;
  }

  List<GQToken> _getTokenFields(GQToken? typeToken, GQGrammar g) {
    if (typeToken == null || typeToken is! GQTypeDefinition) {
      return [];
    }
    // check fields
    var result = <GQToken>[];
    // get all fields that are skipped on server

    var fields = typeToken.fields.where((f) => f.getDirectiveByName(gqSkipOnServer) != null);
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
}
