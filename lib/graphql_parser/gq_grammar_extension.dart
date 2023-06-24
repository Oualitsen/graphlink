import 'dart:io';

import 'package:retrofit_graphql/graphql_parser/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/graphql_parser/gq_grammar.dart';
import 'package:retrofit_graphql/graphql_parser/model/gq_field.dart';
import 'package:retrofit_graphql/graphql_parser/model/gq_graphql_service.dart';
import 'package:retrofit_graphql/graphql_parser/model/gq_schema.dart';
import 'package:retrofit_graphql/graphql_parser/model/gq_enum_definition.dart';
import 'package:retrofit_graphql/graphql_parser/model/gq_fragment.dart';
import 'package:retrofit_graphql/graphql_parser/model/gq_input_type_definition.dart';
import 'package:retrofit_graphql/graphql_parser/model/gq_interface.dart';
import 'package:retrofit_graphql/graphql_parser/model/gq_token.dart';
import 'package:retrofit_graphql/graphql_parser/model/gq_type.dart';
import 'package:retrofit_graphql/graphql_parser/model/gq_type_definition.dart';
import 'package:retrofit_graphql/graphql_parser/model/gq_union.dart';
import 'package:retrofit_graphql/graphql_parser/model/gq_queries.dart';

const String inputsFileName = "inputs.gq";
const String allFieldsFragmentsFileName = "allFieldsFragments";
const String enumsFileName = "enums.gq";
const String typesFileName = "types.gq";
const String clientFileName = "client.gq";

extension GQGrammarExtension on GQGrammar {
  bool isNonProjectableType(String token) {
    return scalars.contains(token) || enums.containsKey(token);
  }

  void addScalarDefinition(String scalar) {
    checkSacalarDefinition(scalar);
    scalars.add(scalar);
  }

  void checkSacalarDefinition(String scalar) {
    if (scalars.contains(scalar)) {
      throw ParseException("Scalar $scalar has already been declared");
    }
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
    inputs[input.token] = input;
  }

  void addTypeDefinition(GQTypeDefinition type) {
    checkTypeDefinition(type);
    types[type.token] = type;
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
    checkQueryDefinition(definition.token);
    queries[definition.token] = definition;
  }

  void saveAllFieldsFragmentFile(String destFolder) {
    var file = File("$destFolder/$allFieldsFragmentsFileName.graphql");

    var allFieldsFragmentsContent = allFieldsFragments.values
        .toList()
        .map((e) => e.fragment.serialize())
        .join("\n");
    file.writeAsStringSync(allFieldsFragmentsContent);
  }

  String generateEnums(GQGrammar g) {
    return enums.values.toList().map((e) => e.toDart(g)).join("\n");
  }

  String generateInputs(GQGrammar g) {
    var inputs = this.inputs.values.toList().map((e) => e.toDart(g)).join("\n");
    return """
  import 'package:json_annotation/json_annotation.dart';
  import '$enumsFileName.dart';
  part '$inputsFileName.g.dart';

$inputs
""";
  }

  String generateTypes(GQGrammar g) {
    var data =
        projectedTypes.values.toList().map((e) => e.toDart(g)).join("\n");
    var data2 = queries.values
        .toList()
        .map((e) => e.getGeneratedTypeDefinition().toDart(g))
        .join("\n");
    return """
 import 'package:json_annotation/json_annotation.dart';
 import '$enumsFileName.dart';
  part '$typesFileName.g.dart';

$data

$data2  

""";
  }

  String generateClient(GQGrammar g) {
    var data = service.toDart(g);
    return """
import '$enumsFileName.dart';
import '$inputsFileName.dart';
import '$typesFileName.dart';
$data
""";
  }

  fillQueryElementArgumentTypes(
      GQQueryElement element, GQQueryDefinition query) {
    for (var arg in element.arguments) {
      var list = query.arguments.where((a) => a.token == arg.value).toList();
      if (list.isEmpty) {
        throw ParseException(
            "Could not find argument ${arg.value} on query ${query.token}");
      }
      arg.type = list.first.type;
    }
  }

  fillQueryElementsReturnType() {
    queries.forEach((name, queryDefinition) {
      for (var element in queryDefinition.elements) {
        element.returnType = getTypeFromFieldName(
            element.token, schema.getByQueryType(queryDefinition.type));
        fillQueryElementArgumentTypes(element, queryDefinition);
      }
    });
  }

  generateGQClient() {
    service = GQGraphqlService(queries.values.toList());
  }

  void checmEnumDefinition(GQEnumDefinition enumDefinition) {
    if (enums.containsKey(enumDefinition.token)) {
      throw ParseException(
          "Enum ${enumDefinition.token} has already been declared");
    }
  }

  void checkInterfaceDefinition(GQInterfaceDefinition interface) {
    if (interfaces.containsKey(interface.token)) {
      throw ParseException(
          "Interface ${interface.token} has already been declared");
    }
  }

  void checkTypeDefinition(GQTypeDefinition type) {
    if (types.containsKey(type.token)) {
      throw ParseException("Type ${type.token} has already been declared");
    }
  }

  void checkIfDefined(String typeName) {
    if (types.containsKey(typeName) ||
        interfaces.containsKey(typeName) ||
        enums.containsKey(typeName) ||
        scalars.contains(typeName)) {
      return;
    }
    throw ParseException("Type $typeName is not defined");
  }

  void checkInputDefinition(GQInputDefinition input) {
    if (inputs.containsKey(input.token)) {
      throw ParseException("Input ${input.token} has already been declared");
    }
  }

  void checkUnitionDefinition(GQUnionDefinition union) {
    if (unions.containsKey(union.token)) {
      throw ParseException("Union ${union.token} has already been declared");
    }
  }

  void checkFragmentRefs() {
    fragments.forEach((key, typedFragment) {
      var refs = typedFragment.block.getFragmentReferences();
      for (var ref in refs) {
        var referencedFragment = fragments[ref.fragmentName!]!;
        logger.i(
            "${referencedFragment.onTypeName} typedFrag = ${typedFragment.onTypeName}");
      }
    });
  }

  void checkFragmentDefinition(GQFragmentDefinitionBase fragment) {
    if (fragments.containsKey(fragment.token)) {
      throw ParseException(
          "Fragment ${fragment.token} has already been declared");
    }
  }

  void checkQueryDefinition(String token) {
    if (queries.containsKey(token)) {
      throw ParseException("Query $token has already been declared");
    }
  }

  void checkType(String name) {
    bool b = scalars.contains(name) ||
        unions.containsKey(name) ||
        types.containsKey(name) ||
        inputs.containsKey(name) ||
        interfaces.containsKey(name) ||
        enums.containsKey(name);
    if (!b) {
      throw ParseException("Type $name undefined");
    }
  }

  void checkInput(String inputName) {
    if (!inputs.containsKey(inputName)) {
      throw ParseException("Input $inputName undefined");
    }
  }

  void checkInterface(String interface) {
    if (!interfaces.containsKey(interface)) {
      throw ParseException("Interface $interface undefined");
    }
  }

  void defineSchema(GQSchema schema) {
    if (schemaInitialized) {
      throw ParseException("A schema has already been defined");
    }
    schemaInitialized = true;
    this.schema = schema;
  }

  void checkScalar(String scalarName) {
    if (!scalars.contains(scalarName)) {
      throw ParseException("Scalar $scalarName was not declared");
    }
  }

  void validateProjections() {
    validateFragmentProjections();
    validateQueryDefinitionProjections();
  }

  List<GQQueryElement> getAllElements() {
    return queries.values.expand((q) => q.elements).toList();
  }

  void validateQueryDefinitionProjections() {
    getAllElements().forEach((element) {
      var inlineType = element.returnType.inlineType;
      var requiresProjection = typeRequiresProjection(inlineType);
      //check if projection should be applied
      if (requiresProjection && element.block == null) {
        throw ParseException("A projection is need on ${inlineType.token}");
      } else if (!requiresProjection && element.block != null) {
        throw ParseException("A projection is not need on ${inlineType.token}");
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
      var declaredType = getType(inlineType.token);
      if (projection.isFragmentReference) {
        var fragment = getFragment(projection.token);

        if (fragment.onTypeName != declaredType.token &&
            !declaredType.interfaceNames.contains(fragment.onTypeName)) {
          throw ParseException(
              "Fragment ${fragment.token} cannot be applied to type ${type.token}");
        }
        element.fragmentReferences.add(fragment);
      } else {
        var list = declaredType.fields.where((f) => f.name == projection.token);
        if (list.isEmpty) {
          throw ParseException(
              "Cannot find field '${projection.token}' in type '${inlineType.token}'");
        }
      }
    });
  }

  void validateFragmentProjections() {
    fragments.forEach((key, fragment) {
      fragment.block.projections.forEach((key, projection) {
        validateProjection(projection, fragment.onTypeName, fragment.token);
      });
    });
  }

  void validateProjection(
      GQProjection projection, String typeName, String? fragmentName) {
    if (projection.isFragmentReference) {
      var fragment = getFragment(projection.token);
      var type = getType(typeName);
      if (fragment.onTypeName != type.token &&
          !type.interfaceNames.contains(fragment.onTypeName)) {
        throw ParseException(
            "Fragment ${fragment.token} cannot be applied to type ${type.token}");
      }
    } else {
      var requiresProjection =
          fieldRequiresProjection(projection.token, typeName);
      if (requiresProjection && projection.block == null) {
        throw ParseException(
            "Field '${projection.token}' of type '$typeName' must have a selection of subfield ${fragmentName == null ? "" : "Fragment: '$fragmentName'"}");
      }
      if (!requiresProjection && projection.block != null) {
        throw ParseException(
            "Field '${projection.token}' of type '$typeName' should not have a selection of subfields ${fragmentName == null ? "" : "Fragment: '$fragmentName'"}");
      }
    }
  }

  bool fieldRequiresProjection(String fieldName, String onTypeName) {
    checkIfDefined(onTypeName);
    GQType type = getFieldType(fieldName, onTypeName);
    return typeRequiresProjection(type);
  }

  bool typeRequiresProjection(GQType type) {
    try {
      getType(type.token);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool inputTypeRequiresProjection(GQType type) {
    return inputs[type.token] != null;
  }

  GQType getFieldType(String fieldName, String typeName) {
    var onType = getType(typeName);

    var result = onType.fields.where((element) => element.name == fieldName);
    if (result.isEmpty && fieldName != GQGrammar.typename) {
      throw ParseException(
          "Could not find field '$fieldName' on type '$typeName'");
    } else {
      if (result.isNotEmpty) {
        return result.first.type;
      } else {
        return GQType(getLangType("String"), false);
      }
    }
  }

  void updateFragmentAllTypesDependecies() {
    fragments.forEach((key, fragment) {
      fragment.block.projections.values
          .where((projection) => projection.block == null)
          .forEach((projection) {
        if (projection.isFragmentReference) {
          var fragmentRef = getFragment(projection.token);
          fragment.dependecies.add(fragmentRef);
        } else {
          var type = getType(fragment.onTypeName);
          var field = findFieldByName(projection.token, type);
          if (types.containsKey(field.type.token)) {
            fragment.dependecies
                .add(allFieldsFragments[field.type.token]!.fragment);
          }
        }
      });
    });
  }

  GQField findFieldByName(String fieldName, GQTokenWithFields dataType) {
    var filtered = dataType.fields.where((f) => f.name == fieldName);
    if (filtered.isEmpty) {
      if (fieldName == GQGrammar.typename) {
        return GQField(
            name: fieldName,
            type: GQType(getLangType("String"), false),
            arguments: []);
      } else {
        throw ParseException(
            "Could not find field '$fieldName' on type ${dataType.token}");
      }
    }
    return filtered.first;
  }

  GQType getTypeFromFieldName(String fieldName, String typeName) {
    var type = getType(typeName);

    var fields =
        type.fields.where((element) => element.name == fieldName).toList();
    if (fields.isEmpty) {
      throw ParseException(
          "$typeName does not declare a field with name $fieldName");
    }
    return fields.first.type;
  }

  void updateFragmentDependencies() {
    fragments.forEach((key, value) {
      value.updateDepencies(fragments);
    });
  }

  GQTypeDefinition getType(String name) {
    final type = types[name] ?? interfaces[name];
    if (type == null) {
      throw ParseException("No type or interface '$name' defined");
    }
    return type;
  }

  GQFragmentDefinitionBase getFragment(String name) {
    final fragment = fragments[name];
    if (fragment == null) {
      throw ParseException("Fragment '$name' was not found");
    }
    return fragment;
  }

  GQInterfaceDefinition getInterface(String name) {
    final type = interfaces[name];
    if (type == null) {
      throw ParseException("Interface $name was not found");
    }
    return type;
  }

  void fillTypedFragments() {
    fragments.forEach((key, fragment) {
      checkIfDefined(fragment.onTypeName);
      typedFragments[key] =
          GQTypedFragment(fragment, getType(fragment.onTypeName));
    });
  }

  void createAllFieldsFragments() {
    types.forEach((key, value) {
      if (![schema.mutation, schema.query, schema.subscription].contains(key)) {
        allFieldsFragments[key] = GQTypedFragment(
            GQFragmentDefinition(
                key,
                value.token,
                GQFragmentBlockDefinition(value.fields
                    .map((e) => GQProjection(
                        fragmentName: null,
                        token: e.name,
                        alias: null,
                        isFragmentReference: false,
                        block: null,
                        directives: []))
                    .toList()),
                []),
            value);
      }
    });
  }

  void createProjectedTypes() {
    typedFragments.forEach((key, value) {
      createProjectedType(value.fragment, value.onType);
    });

    //create for queries, mutations and subscriptions
    getAllElements().where((e) => e.block != null).forEach((element) {
      var newType =
          createProjectedTypeForQuery(element.returnType, element.block!);
      element.projectedType = newType;
    });
  }

  GQTypeDefinition createProjectedTypeForQuery(
      GQType type, GQFragmentBlockDefinition block) {
    var onType = getType(type.inlineType.token);
    var name = generateName(onType.token, block);
    var newType = GQTypeDefinition(
        name: name,
        fields: applyProjection(onType.fields, block.projections),
        interfaceNames: onType.interfaceNames,
        directives: onType.directives);

    projectedTypes[name] = newType;
    return newType;
  }

  void createProjectedType(
      GQFragmentDefinitionBase fragment, GQTypeDefinition onType) {
    var name = "${fragment.token}_on_${onType.token}";

    var newType = GQTypeDefinition(
        name: name,
        fields: applyProjection(onType.fields, fragment.block.projections),
        interfaceNames: onType.interfaceNames,
        directives: onType.directives);
    projectedTypes[name] = newType;
  }

  GQTypeDefinition createProjectedTypeWithProjectionBlock(
      GQTypeDefinition nonProjectedType, GQFragmentBlockDefinition block) {
    var fields = [...nonProjectedType.fields];
    var projections = {...block.projections};
    var name = generateName(nonProjectedType.token, block);
    block.projections.values
        .where((element) => element.isFragmentReference)
        .map((e) => fragments[e.fragmentName!]!)
        .forEach((frag) {
      projections.addAll(frag.block.projections);
    });

    var result = GQTypeDefinition(
        name: name,
        fields: applyProjection(fields, projections),
        interfaceNames: {},
        directives: []);

    projectedTypes[name] = result;
    return result;
  }

  String generateName(String originalName, GQFragmentBlockDefinition block) {
    var name = "${originalName}_${block.uniqueName}";
    String? indexedName;
    int nameIndex = 0;
    if (projectedTypes.containsKey(name)) {
      indexedName = "${name}_${++nameIndex}";
    }
    while (projectedTypes.containsKey(indexedName)) {
      indexedName = "${name}_${++nameIndex}";
    }
    return indexedName ?? name;
  }

  List<GQField> applyProjection(
      List<GQField> src, Map<String, GQProjection> p) {
    var result = <GQField>[];
    var projections = {...p};

    p.values
        .where((element) => element.isFragmentReference)
        .map((e) => e.fragmentName!)
        .map((fragName) => getFragment(fragName))
        .forEach((fragment) {
      projections.addAll(fragment.block.projections);
    });

    for (var field in src) {
      var projection = projections[field.name];
      if (projection != null) {
        result.add(applyProjectionToField(field, projection));
      }
    }

    return result;
  }

  GQField applyProjectionToField(GQField field, GQProjection projection) {
    final String fieldName = projection.alias ?? field.name;

    if (projection.block != null) {
      //we should create another type here ...
      var generatedType = createProjectedTypeWithProjectionBlock(
          getType(field.type.token), projection.block!);
      return GQField(
        name: fieldName,
        type: GQType(generatedType.token, field.type.nullable, isScalar: false),
        arguments: field.arguments,
      );
    }

    return GQField(
      name: fieldName,
      type: field.type,
      arguments: field.arguments,
    );
  }

  String getLangType(String typeName) {
    var result = typeMap[typeName];
    if (result == null) {
      throw ParseException("Unknown type $typeName");
    }
    return result;
  }
}
