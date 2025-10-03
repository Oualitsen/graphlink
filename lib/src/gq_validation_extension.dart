import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_enum_definition.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_fragment.dart';
import 'package:retrofit_graphql/src/model/gq_input_type_definition.dart';
import 'package:retrofit_graphql/src/model/gq_interface_definition.dart';
import 'package:retrofit_graphql/src/model/gq_queries.dart';
import 'package:retrofit_graphql/src/model/gq_repository.dart';
import 'package:retrofit_graphql/src/model/gq_scalar_definition.dart';
import 'package:retrofit_graphql/src/model/gq_schema.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/model/gq_union.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';

extension GqValidationExtension on GQGrammar {
  void validateInputReferences() {
    inputs.values.forEach(_validateInputRef);
  }

  void _validateInputRef(GQInputDefinition def) {
    for (var field in def.fields) {
      var typeToken = field.type.token;
      if (!scalars.containsKey(typeToken) && !inputs.containsKey(typeToken) && !enums.containsKey(typeToken)) {
        throw ParseException("$typeToken is not a scalar, input or enum", info: field.name);
      }
    }
  }

  void validateTypeReferences() {
    [...types.values, ...interfaces.values].forEach(_validateTypeRef);
  }

  void _validateTypeRef(GQTypeDefinition def) {
    for (var field in def.fields) {
      var typeToken = field.type.token;
      if (!scalars.containsKey(typeToken) &&
          !types.containsKey(typeToken) &&
          !interfaces.containsKey(typeToken) &&
          !unions.containsKey(typeToken) &&
          !enums.containsKey(typeToken)) {
        throw ParseException("$typeToken is not a scalar, enum, type, interface or union", info: field.name);
      }
      for (var arg in field.arguments) {
        var argToken = arg.type.token;
        if (!scalars.containsKey(argToken) &&
            !inputs.containsKey(argToken) &&
            !enums.containsKey(argToken)) {
          throw ParseException("$argToken is not a scalar, enum, or input", info: field.name);
        }
      }
    }
  }

  void validateProjections() {
    validateFragmentProjections();
    validateQueryDefinitionProjections();
  }

  void validateFragmentProjections() {
    fragments.forEach((key, fragment) {
      fragment.block.projections.forEach((key, projection) {
        validateProjection(projection, fragment.onTypeName, fragment.token);
      });
    });
  }

  void validateProjection(GQProjection projection, TokenInfo onTypeNameToken, String? fragmentName) {
    final typeName = onTypeNameToken.token;
    var type = getType(onTypeNameToken);
    if (projection is GQInlineFragmentsProjection) {
      //handl for interface
      projection.inlineFragments.map((e) => e.onTypeName).map((e) => getType(e)).forEach((type) {
        if (!type.containsInteface(typeName) && type.token != typeName) {
          throw ParseException("Type '${type.tokenInfo}' does not implement '${typeName}'", info: onTypeNameToken);
        }
      });

      for (var inlineFrag in projection.inlineFragments) {
        inlineFrag.block.projections.forEach((key, proj) {
          validateProjection(proj, inlineFrag.onTypeName, null);
        });
      }
      return;
    }
    if (projection.isFragmentReference) {
      GQFragmentDefinitionBase fragment = getFragment(projection.token, projection.tokenInfo, typeName);
      if (fragment.onTypeName.token != type.token && !type.containsInteface(fragment.onTypeName.token)) {
        throw ParseException("Fragment ${fragment.tokenInfo} cannot be applied to type ${type.tokenInfo}",
            info: fragment.tokenInfo);
      }
      if (projection.token == allFields) {
        projection.fragmentName = '${allFields}_$typeName';
      }
    } else {
      var requiresProjection = fieldRequiresProjection(projection.tokenInfo, onTypeNameToken, projection.tokenInfo);

      if (requiresProjection && projection.block == null) {
        throw ParseException(
            "Field '${projection.tokenInfo}' of type '$typeName' must have a selection of subfield ${fragmentName == null ? "" : "Fragment: '$fragmentName'"}",
            info: projection.tokenInfo);
      }
      if (!requiresProjection && projection.block != null) {
        throw ParseException(
            "Field '${projection.tokenInfo}' of type '$typeName' should not have a selection of subfields ${fragmentName == null ? "" : "Fragment: '$fragmentName'"}",
            info: projection.tokenInfo);
      }
    }
    if (projection.block != null) {
      var myType = getTypeFromFieldName(projection.actualName, typeName, projection.tokenInfo);
      for (var p in projection.block!.projections.values) {
        validateProjection(p, myType.tokenInfo, null);
      }
    }
  }

  void checkIfDefined(TokenInfo typeNameToken) {
    var typeName = typeNameToken.token;
    if (types.containsKey(typeName) ||
        interfaces.containsKey(typeName) ||
        enums.containsKey(typeName) ||
        scalars.containsKey(typeName)) {
      return;
    }
    throw ParseException("Type $typeName is not defined", info: typeNameToken);
  }

  bool fieldRequiresProjection(TokenInfo fieldNameToken, TokenInfo onTypeName, TokenInfo info) {
    checkIfDefined(onTypeName);
    GQType type = getFieldType(fieldNameToken, onTypeName.token);
    return typeRequiresProjection(type);
  }

  bool typeRequiresProjection(GQType type) {
    final name = type.inlineType.token;
    return types.containsKey(name) || interfaces.containsKey(name) || unions.containsKey(name);
  }

  bool inputTypeRequiresProjection(GQType type) {
    return inputs[type.token] != null;
  }

  void checkFragmentRefs() {
    fragments.forEach((key, typedFragment) {
      var refs = typedFragment.block.getFragmentReferences();
      for (var ref in refs) {
        getFragment(ref.fragmentName!, ref.tokenInfo, typedFragment.onTypeName.token);
      }
    });
  }

  void checkFragmentDefinition(GQFragmentDefinitionBase fragment) {
    if (fragments.containsKey(fragment.token)) {
      throw ParseException("Fragment ${fragment.tokenInfo} has already been declared", info: fragment.tokenInfo);
    }
  }

  void checkQueryDefinition(TokenInfo tokenInfo) {
    if (queries.containsKey(tokenInfo.token)) {
      throw ParseException("Query ${tokenInfo.token} has already been declared", info: tokenInfo);
    }
  }

  void checkInputDefinition(GQInputDefinition input) {
    if (inputs.containsKey(input.declaredName)) {
      throw ParseException("Input ${input.tokenInfo} has already been declared", info: input.tokenInfo);
    }
  }

  void checkUnitionDefinition(GQUnionDefinition union) {
    if (unions.containsKey(union.token)) {
      throw ParseException("Union ${union.tokenInfo} has already been declared", info: union.tokenInfo);
    }
  }

  void validateQueryDefinitionProjections() {
    getAllElements().forEach((element) {
      var inlineType = element.returnType.inlineType;
      var requiresProjection = typeRequiresProjection(inlineType);
      //check if projection should be applied
      if (requiresProjection && element.block == null) {
        throw ParseException("A projection is need on ${inlineType.tokenInfo}", info: inlineType.tokenInfo);
      } else if (!requiresProjection && element.block != null) {
        throw ParseException("A projection is not need on ${inlineType.tokenInfo}", info: inlineType.tokenInfo);
      }

      if (element.block != null) {
        //validate projections with return type
        validateQueryProjection(element);
      }
    });
  }

  void validateQueryProjection(GQQueryElement element) {
    var type = element.returnType;
    GQFragmentBlockDefinition? block = element.block;
    if (block == null) {
      return;
    }
    block.projections.forEach((key, projection) {
      var inlineType = type.inlineType;
      validateProjection(projection, inlineType.tokenInfo, null);
    });
  }

  void checkRepository(GQInterfaceDefinition interface) {
    var repo = interface.getDirectiveByName(gqRepository)!;
    var typeName = repo.getArgValueAsString(gqType);
    if (typeName == null) {
      throw ParseException("$gqType is required on $gqRepository directive", info: repo.tokenInfo);
    }

    var idType = repo.getArgValueAsString(gqIdType);
    if (idType == null) {
      throw ParseException("$gqIdType is required on $gqRepository directive", info: repo.tokenInfo);
    }

    var type = types[typeName];
    if (type == null) {
      throw ParseException("Type '$typeName' referenced by directive '$gqRepository' is not defined or skipped",
          info: repo.tokenInfo);
    }
  }

  void checkSacalarDefinition(GQScalarDefinition scalar) {
    if (scalars.containsKey(scalar.token)) {
      throw ParseException("Scalar ${scalar.token} has already been declared", info: scalar.tokenInfo);
    }
  }

  void checkDirectiveDefinition(TokenInfo name) {
    if (directiveDefinitions.containsKey(name.token)) {
      throw ParseException("Directive $name has already been declared", info: name);
    }
  }

  void checkInterfaceDefinition(GQInterfaceDefinition interface) {
    if (interfaces.containsKey(interface.token)) {
      throw ParseException("Interface ${interface.tokenInfo} has already been declared", info: interface.tokenInfo);
    }
  }

  void checkTypeDefinition(GQTypeDefinition type) {
    if (types.containsKey(type.token)) {
      throw ParseException("Type ${type.tokenInfo} has already been declared", info: type.tokenInfo);
    }
  }

  bool isNonProjectableType(String token) {
    return isEnum(token) || isScalar(token);
  }

  bool isProjectableType(String token) {
    return !isNonProjectableType(token);
  }

  bool isEnum(String token) {
    return enums.containsKey(token);
  }

  bool isInput(String token) {
    return inputs.containsKey(token);
  }

  bool isScalar(String token) {
    return scalars.containsKey(token);
  }

  void addDiectiveValue(GQDirectiveValue value) {
    directiveValues.add(value);
  }

  void addScalarDefinition(GQScalarDefinition scalar) {
    checkSacalarDefinition(scalar);
    scalars[scalar.token] = scalar;
  }

  void addDirectiveDefinition(GQDirectiveDefinition directive) {
    checkDirectiveDefinition(directive.name);
    directiveDefinitions[directive.name.token] = directive;
  }

  void addFragmentDefinition(GQFragmentDefinitionBase fragment) {
    checkFragmentDefinition(fragment);
    fragments[fragment.token] = fragment;
  }

  void addUnionDefinition(GQUnionDefinition union) {
    checkUnitionDefinition(union);
    unions[union.token] = union;
  }

  void addInputDefinition(GQInputDefinition input) {
    checkInputDefinition(input);
    inputs[input.declaredName] = input;
  }

  void addTypeDefinition(GQTypeDefinition type) {
    var queryTypes = GQQueryType.values.map((e) => schema.getByQueryType(e)).toList();
    if (queryTypes.contains(type.token)) {
      if (types.containsKey(type.token)) {
        merge(getType(type.tokenInfo), type);
        return;
      }
    }
    checkTypeDefinition(type);
    types[type.token] = type;
  }

  static void merge(GQTypeDefinition dest, GQTypeDefinition orig) {
    for (var field in orig.fields) {
      dest.addField(field);
    }
  }

  void addInterfaceDefinition(GQInterfaceDefinition interface) {
    checkInterfaceDefinition(interface);
    interfaces[interface.token] = interface;
  }

  void addEnumDefinition(GQEnumDefinition enumDefinition) {
    checmEnumDefinition(enumDefinition);
    enums[enumDefinition.token] = enumDefinition;
  }

  void addQueryDefinition(GQQueryDefinition definition) {
    checkQueryDefinition(definition.tokenInfo);
    queries[definition.token] = definition;
  }

  void addQueryDefinitionSkipIfExists(GQQueryDefinition definition) {
    if (queries.containsKey(definition.token)) {
      logger.i("${definition.type} ${definition.tokenInfo} is already defined, skipping generation");
      return;
    }
    queries[definition.token] = definition;
  }

  void handleRepositories([bool check = true]) {
    interfaces.forEach((k, v) {
      var repo = v.getDirectiveByName(gqRepository);
      if (repo != null) {
        if (check) {
          checkRepository(v);
        }
        repositories[k] = GQRepository.of(v);
      }
    });
    interfaces.removeWhere((k, _) => repositories.containsKey(k));
  }

  List<GQField> getUnionFields(GQUnionDefinition def) {
    var fields = <String, int>{};
    var result = <GQField>[];
    def.typeNames.map((e) => getType(e)).expand((e) => e.getFields()).forEach((e) {
      var key = e.name.token;
      if (fields.containsKey(key)) {
        fields[key] = fields[key]! + 1;
      } else {
        fields[key] = 1;
      }
      if (fields[key] == def.typeNames.length) {
        result.add(e);
      }
    });
    return result;
  }

  void defineSchema(GQSchema schema) {
    if (schemaInitialized) {
      throw ParseException("A schema has already been defined", info: schema.tokenInfo);
    }
    schemaInitialized = true;
    this.schema = schema;
  }

  GQTypeDefinition? getTypeByName(String name) {
    return types[name] ?? interfaces[name];
  }

  GQTypeDefinition getType(TokenInfo info) {
    var name = info.token;
    final type = getTypeByName(name);
    if (type == null) {
      throw ParseException("No type or interface '$name' defined", info: info);
    }
    return type;
  }

  GQFragmentDefinitionBase? getFragmentByName(String name, [String? typeName]) {
    String fragmentName;
    if (name == allFields && typeName != null) {
      fragmentName = '${allFields}_$typeName';
    } else {
      fragmentName = name;
    }
    return fragments[fragmentName];
  }

  GQFragmentDefinitionBase getFragment(String name, TokenInfo info, [String? typeName]) {
    var frag = getFragmentByName(name, typeName);
    if (frag == null) {
      throw ParseException("Fragment '$name' is not defined", info: info);
    }
    return frag;
  }

  GQInterfaceDefinition getInterface(String name, TokenInfo info) {
    final type = interfaces[name];
    if (type == null) {
      throw ParseException("Interface $name is not found", info: info);
    }
    return type;
  }

  void checkInterfaceInheritance() {
    var myTypes = <String, Set<GQTypeDefinition>>{};
    types.values.where((type) => type.interfaceNames.isNotEmpty).forEach((t) {
      for (var ifname in t.interfaceNames) {
        var myType = myTypes[ifname.token] ?? <GQTypeDefinition>{};
        myType.add(t);
        myTypes[ifname.token] = myType;
      }
    });
    for (var interface in interfaces.values) {
      var typeSet = myTypes[interface.token];
      if (typeSet != null) {
        for (var type in typeSet) {
          for (var f in interface.fields) {
            var typeField = type.getFieldByName(f.name.token);
            if (typeField == null) {
              throw ParseException(
                  "Type ${type.tokenInfo} implements ${interface.tokenInfo} but does not declare field ${f.name}",
                  info: type.tokenInfo);
            }
          }
        }
      }
    }
  }
}
