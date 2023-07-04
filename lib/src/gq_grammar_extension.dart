import 'dart:io';

import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_graphql_service.dart';
import 'package:retrofit_graphql/src/model/gq_schema.dart';
import 'package:retrofit_graphql/src/model/gq_enum_definition.dart';
import 'package:retrofit_graphql/src/model/gq_fragment.dart';
import 'package:retrofit_graphql/src/model/gq_input_type_definition.dart';
import 'package:retrofit_graphql/src/model/gq_interface.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/model/gq_union.dart';
import 'package:retrofit_graphql/src/model/gq_queries.dart';
import 'package:retrofit_graphql/src/utils.dart';

const String inputsFileName = "inputs.gq";
const String allFieldsFragmentsFileName = "allFieldsFragments";
const String enumsFileName = "enums.gq";
const String typesFileName = "types.gq";
const String clientFileName = "client.gq";

const fileHeadComment = """
// GENERATED CODE - DO NOT MODIFY BY HAND.

// ignore_for_file: camel_case_types, constant_identifier_names, unused_import, non_constant_identifier_names
""";

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

  String generateEnums() {
    return """
$fileHeadComment
 ${enums.values.toList().map((e) => e.toDart(this)).join("\n")}
 """;
  }

  String generateInputs() {
    var inputs =
        this.inputs.values.toList().map((e) => e.toDart(this)).join("\n");
    return """
$fileHeadComment
  import 'package:json_annotation/json_annotation.dart';
  import '$enumsFileName.dart';
  part '$inputsFileName.g.dart';

$inputs
""";
  }

  String generateTypes() {
    var data =
        projectedTypes.values.toSet().map((e) => e.toDart(this)).join("\n");

    return """
$fileHeadComment
 import 'package:json_annotation/json_annotation.dart';
 import '$enumsFileName.dart';
  part '$typesFileName.g.dart';

$data

""";
  }

  String generateClient() {
    var data = service.toDart(this);
    return """
$fileHeadComment
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
      validateProjection(projection, inlineType.token, null);
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
    var type = getType(typeName);
    if (projection.isFragmentReference) {
      var fragment = getFragment(projection.token);

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
    if (projection.block != null) {
      var myType = getTypeFromFieldName(projection.actualName, typeName);
      for (var p in projection.block!.projections.values) {
        validateProjection(p, myType.token, null);
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
      getType(type.inlineType.token);
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
          arguments: [],
          directives: [],
        );
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
    var fragMap = <String, GQFragmentDefinitionBase>{};
    allFieldsFragments.forEach((key, value) {
      fragMap[key] = value.fragment;
    });
    allFieldsFragments.forEach((key, value) {
      value.fragment.updateDepencies(fragMap);
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
    final fragment = fragments[name] ?? allFieldsFragments[name]?.fragment;
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
    types.forEach((key, typeDefinition) {
      if (![schema.mutation, schema.query, schema.subscription].contains(key)) {
        allFieldsFragments[allFieldsFragmentName(key)] = GQTypedFragment(
            GQFragmentDefinition(
                allFieldsFragmentName(key),
                typeDefinition.token,
                GQFragmentBlockDefinition(typeDefinition.fields
                    .map((field) => GQProjection(
                        fragmentName: null,
                        token: field.name,
                        alias: null,
                        isFragmentReference: false,
                        block: createAllFieldBlock(field),
                        directives: []))
                    .toList()),
                []),
            typeDefinition);
      }
    });
  }

  static String allFieldsFragmentName(String token) {
    return "_all_fields_$token";
  }

  GQFragmentBlockDefinition? createAllFieldBlock(GQField field) {
    if (!typeRequiresProjection(field.type)) {
      return null;
    }
    return GQFragmentBlockDefinition([
      GQProjection(
          fragmentName: allFieldsFragmentName(field.type.inlineType.token),
          token: allFieldsFragmentName(field.type.inlineType.token),
          alias: null,
          isFragmentReference: true,
          block: null,
          directives: [])
    ]);
  }

  void createProjectedTypes() {
    //create for queries, mutations and subscriptions
    getAllElements().where((e) => e.block != null).forEach((element) {
      var newType = createProjectedTypeForQuery(element);
      element.projectedTypeKey = newType.token;
    });

    getAllElements()
        .where((e) => e.projectedTypeKey != null)
        .forEach((element) {
      element.projectedType = projectedTypes[element.projectedTypeKey!]!;
    });

    queries.forEach((key, query) {
      var projectedType = query.getGeneratedTypeDefinition();
      if (projectedTypes.containsKey(projectedType.token)) {
        throw ParseException(
            "Type ${projectedType.token} has already been defined, please rename it");
      }
      projectedTypes[projectedType.token] = projectedType;
    });
  }

  GQTypeDefinition createProjectedTypeForQuery(GQQueryElement element) {
    var type = element.returnType;
    var block = element.block!;
    var onType = getType(type.inlineType.token);

    var name = generateName(onType.token, block, element.directives);
    var newType = GQTypeDefinition(
        name: name.value,
        nameDeclared: name.declared,
        fields: applyProjection(onType.fields, block.projections),
        interfaceNames: onType.interfaceNames,
        directives: onType.directives);
    return addToProjectedType(newType);
  }

  GQTypeDefinition createProjectedTypeWithProjectionBlock(GQField field,
      GQTypeDefinition nonProjectedType, GQFragmentBlockDefinition block,
      [List<GQDirectiveValue> fieldDirectives = const []]) {
    var fields = [...nonProjectedType.fields];
    var projections = {...block.projections};
    var name = generateName(nonProjectedType.token, block, fieldDirectives);
    block.projections.values
        .where((element) => element.isFragmentReference)
        .map((e) => (fragments[e.fragmentName!] ??
            allFieldsFragments[e.fragmentName!]?.fragment)!)
        .forEach((frag) {
      projections.addAll(frag.block.projections);
    });

    var result = GQTypeDefinition(
        name: name.value,
        nameDeclared: name.declared,
        fields: applyProjection(fields, projections),
        interfaceNames: {},
        directives: []);

    return addToProjectedType(result);
  }

  GQTypeDefinition addToProjectedType(GQTypeDefinition definition) {
    if (definition.nameDeclared) {
      var type = projectedTypes[definition.token];
      if (type == null) {
        var similarDefinitions = findSimilarTo(definition);
        if (similarDefinitions.isNotEmpty) {
          similarDefinitions
              .where((element) => !element.nameDeclared)
              .forEach((e) {
            projectedTypes[e.token] = definition;
          });
        }

        projectedTypes[definition.token] = definition;
        return definition;
      } else {
        if (type.isSimilarTo(definition, this)) {
          return type;
        } else {
          throw ParseException(
              "You have names two object the same name '${definition.token}' but have diffrent fields. ${definition.token}_1.fields are: [${type.serializeFields(this)}], ${definition.token}_2.fields are: [${definition.serializeFields(this)}]. Please consider renaming one of them");
        }
      }
    }

    var similarDeinitions = findSimilarTo(definition);
    if (similarDeinitions.isNotEmpty) {
      return similarDeinitions.first;
    }
    projectedTypes[definition.token] = definition;
    return definition;
  }

  List<GQTypeDefinition> findSimilarTo(GQTypeDefinition definition) {
    return projectedTypes.values
        .where((element) => element.isSimilarTo(definition, this))
        .toList();
  }

  GeneratedTypeName generateName(String originalName,
      GQFragmentBlockDefinition block, List<GQDirectiveValue> directives) {
    String? name = getNameValueFromDirectives(directives);
    if (name != null) {
      return GeneratedTypeName(name, true);
    }
    name = "${originalName}_${block.uniqueName}";

    String? indexedName;
    int nameIndex = 0;
    if (projectedTypes.containsKey(name)) {
      indexedName = "${name}_${++nameIndex}";
    }
    while (projectedTypes.containsKey(indexedName)) {
      indexedName = "${name}_${++nameIndex}";
    }
    return GeneratedTypeName(indexedName ?? name, false);
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
        result.add(
            applyProjectionToField(field, projection, projection.directives));
      }
    }

    return result;
  }

  GQField applyProjectionToField(GQField field, GQProjection projection,
      [List<GQDirectiveValue> fieldDirectives = const []]) {
    final String fieldName = projection.alias ?? field.name;
    var block = projection.block;
    if (block != null) {
      //we should create another type here ...
      var generatedType = createProjectedTypeWithProjectionBlock(
        field,
        getType(field.type.token),
        block,
        fieldDirectives,
      );
      var fieldInlineType =
          GQType(generatedType.token, field.type.nullable, isScalar: false);

      return GQField(
        name: fieldName,
        type: createTypeFrom(field.type, fieldInlineType),
        arguments: field.arguments,
        directives: projection.directives,
      );
    }

    return GQField(
      name: fieldName,
      type: createTypeFrom(field.type, field.type),
      arguments: field.arguments,
      directives: projection.directives,
    );
  }

  GQType createTypeFrom(GQType orig, GQType inline) {
    if (orig is GQListType) {
      return GQListType(createTypeFrom(orig.type, inline), orig.nullable);
    }
    return GQType(inline.token, inline.nullable, isScalar: inline.isScalar);
  }

  String getLangType(String typeName) {
    var result = typeMap[typeName];
    if (result == null) {
      throw ParseException("Unknown type $typeName");
    }
    return result;
  }
}

class GeneratedTypeName {
  // the generated name value
  final String value;
  //true if the name has been declared using @gqTypeName directive
  final bool declared;

  GeneratedTypeName(this.value, this.declared);
}
