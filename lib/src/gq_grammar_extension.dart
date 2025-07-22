import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_argument.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_has_directives.dart';
import 'package:retrofit_graphql/src/model/gq_scalar_definition.dart';
import 'package:retrofit_graphql/src/model/gq_service.dart';
import 'package:retrofit_graphql/src/model/gq_shcema_mapping.dart';
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
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:retrofit_graphql/src/utils.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';

const String allFieldsFragmentsFileName = "allFieldsFragments";

const allFields = '_all_fields';

extension GQGrammarExtension on GQGrammar {
  void handleAnnotations(String Function(GQDirectiveValue value) serializer) {
    if (annotationsProcessed) {
      return;
    }
    annotationsProcessed = true;
    getDirectiveObjects().forEach((elm) {
      var annotations = elm.getAnnotations(mode: mode);
      for (var an in annotations) {
        String serial = serializer(an);
        var dir = GQDirectiveValue.createGqDecorators(
          decorators: [serial],
          applyOnClient: mode == CodeGenerationMode.client,
          applyOnServer: mode == CodeGenerationMode.server,
        );
        elm.addDirective(dir);
      }
    });
  }

  List<GqDirectivesMixin> getDirectiveObjects() {
    var result = [
      ...inputs.values,
      ...types.values,
      ...interfaces.values,
      ...scalars.values,
      ...enums.values,
      ...repositories.values
    ].map((f) => f as GqDirectivesMixin).toList();

    var inputFields = inputs.values.expand((e) => e.fields);
    var interfaceFields = interfaces.values.expand((e) => e.fields);
    var repositoryFields = repositories.values.expand((e) => e.fields);
    var typeFields = types.values.expand((e) => e.fields);
    var enumValues = enums.values.expand((e) => e.values);
    result.addAll([
      ...inputFields,
      ...interfaceFields,
      ...typeFields,
      ...enumValues,
      ...repositoryFields,
    ]);
    var params = <GqDirectivesMixin>[];
    result.whereType<GQField>().where((f) => f.arguments.isNotEmpty).forEach((f) {
      params.addAll(f.arguments);
    });
    result.addAll(params);

    return result;
  }

  void handleGqExternal() {
    [...inputs.values, ...types.values, ...interfaces.values, ...scalars.values, ...enums.values]
        .map((f) => f as GqDirectivesMixin)
        .where((t) => t.getDirectiveByName(gqExternal) != null)
        .forEach((f) {
      f.addDirectiveIfAbsent(GQDirectiveValue.createDirectiveValue(directiveName: gqSkipOnClient));
      f.addDirectiveIfAbsent(GQDirectiveValue.createDirectiveValue(directiveName: gqSkipOnServer));
    });
  }

  List<GQTypeDefinition> getSerializableTypes() {
    final queries = [schema.mutation, schema.query, schema.subscription];
    return types.values.where((type) => !queries.contains(type.token)).where((type) {
      switch (mode) {
        case CodeGenerationMode.client:
          return type.getDirectiveByName(gqSkipOnClient) == null;
        case CodeGenerationMode.server:
          return type.getDirectiveByName(gqSkipOnServer) == null;
      }
    }).toList();
  }

  void skipFieldOfSkipOnServerTypes() {
    types.values.where((t) => t.getDirectiveByName(gqSkipOnServer) != null).forEach((t) {
      for (var f in t.fields) {
        f.addDirectiveIfAbsent(t.getDirectiveByName(gqSkipOnServer)!);
      }
    });
  }

  void handleDirectiveInheritance() {
    var myTypes = <String, Set<GQTypeDefinition>>{};
    types.values.where((type) => type.interfaceNames.isNotEmpty).forEach((t) {
      for (var ifname in t.interfaceNames) {
        var myType = myTypes[ifname] ?? <GQTypeDefinition>{};
        myType.add(t);
        myTypes[ifname] = myType;
      }
    });
    for (var interface in interfaces.values) {
      var typeSet = myTypes[interface.token];
      if (typeSet != null) {
        for (var type in typeSet) {
          for (var f in interface.fields) {
            var typeField = type.getFieldByName(f.name);
            if (typeField == null) {
              throw ParseException(
                  "Type ${type.token} implements ${interface.token} but does not declare field ${f.name}");
            }
            f.getDirectives().forEach((d) => typeField.addDirectiveIfAbsent(d));
          }
        }
      }
    }
  }

  void handleRepositories([bool check = true]) {
    interfaces.forEach((k, v) {
      var repo = v.getDirectiveByName(gqRepository);
      if (repo != null) {
        if (check) {
          checkRepository(v);
        }
        repositories[k] = v;
      }
    });
    interfaces.removeWhere((k, _) => repositories.containsKey(k));
  }

  void checkRepository(GQInterfaceDefinition interface) {
    var repo = interface.getDirectiveByName(gqRepository)!;
    var typeName = repo.getArgValueAsString(gqType);
    if (typeName == null) {
      throw ParseException("$gqType is required on $gqRepository directive");
    }

    var idType = repo.getArgValueAsString(gqIdType);
    if (idType == null) {
      throw ParseException("$gqIdType is required on $gqRepository directive");
    }

    var type = types[typeName];
    if (type == null) {
      throw ParseException(
          "Type '$typeName' referenced by directive '$gqRepository' is not defined or skipped");
    }
  }

  void addSchemaMapping(GQSchemaMapping mapping) {
    var m = schemaMappings[mapping.key];
    if (m == null || (!m.batch && mapping.batch)) {
      schemaMappings[mapping.key] = mapping;
    }
  }

  void generateServices() {
    for (var type in GQQueryType.values) {
      _doGenerateServices(types[schema.getByQueryType(type)]?.fields ?? [], type);
    }
  }

  void _doGenerateServices(List<GQField> fields, GQQueryType type) {
    for (var field in fields) {
      var name = getServiceName(field);
      var service = services[name] ??= GQService(name: name);
      service.addMethod(field, type);
      services.putIfAbsent(name, () => service);
    }
  }

  String getServiceName(GQField field, [String suffix = "Service"]) {
    var serviceName = field.getDirectiveByName(gqServiceName)?.getArgValueAsString(gqServiceNameArg);
    serviceName ??= "${field.type.token.firstUp}$suffix";
    if (suffix.isNotEmpty && !serviceName.endsWith(suffix)) {
      serviceName += suffix;
    }
    return serviceName;
  }

  GQField? _getIdentityField(GQTypeDefinition type) {
    var mapsTo = type.getDirectiveByName(gqSkipOnServer)?.getArgValueAsString(gqMapTo);
    var skipOnServerFields = type.getSkipOnServerFields();
    if (mapsTo != null) {
      var list = skipOnServerFields.where((e) => e.type.token == mapsTo && e.type is! GQListType).toList();
      if (list.length == 1) {
        return list.first;
      }
    }
    return null;
  }

  void genSchemaMappings(List<GQField> queryFields, GQQueryType queryType) {
    for (var field in queryFields) {
      var type = getType(field.type.token);
      var skipOnServerFields = type.getSkipOnServerFields();
      // find the field to make as identity

      GQField? identityField = _getIdentityField(type);

      for (var typeField in skipOnServerFields) {
        var schemaMappings = GQSchemaMapping(
          type: type,
          field: typeField,
          batch: field.type is GQListType,
          serviceName: getServiceName(field),
          queryType: queryType,
          identity: identityField == typeField,
        );
        if (schemaMappings.serviceName == "CarService") {
          print("Car service ");
        }
        addSchemaMapping(schemaMappings);
      }
      type.getSkinOnClientFields().forEach((typeField) {
        addSchemaMapping(GQSchemaMapping(
            type: type,
            field: typeField,
            forbid: true,
            serviceName: getServiceName(field),
            queryType: queryType));
      });
    }
  }

  void generateSchemaMappings() {
    for (var queryType in GQQueryType.values) {
      genSchemaMappings(
          (types[schema.getByQueryType(queryType)]?.fields ?? [])
              .where((f) => types.containsKey(f.type.token))
              .toList(),
          queryType);
    }
  }

  List<GQSchemaMapping> getSchemaByType(GQTypeDefinition def) {
    var result = <GQSchemaMapping>[];
    schemaMappings.forEach((k, v) {
      if (v.type == def) {
        result.add(v);
      }
    });
    return result;
  }

  void setDirectivesDefaulValues() {
    var values = [...directiveValues];
    for (var value in values) {
      var def = directiveDefinitions[value.token];
      if (def != null) {
        value.setDefualtArguments(def.arguments);
      }
    }
  }

  bool isNonProjectableType(String token) {
    return scalars.containsKey(token) || enums.containsKey(token);
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
    directiveDefinitions[directive.name] = directive;
  }

  void checkSacalarDefinition(GQScalarDefinition scalar) {
    if (scalars.containsKey(scalar.token)) {
      throw ParseException("Scalar $scalar has already been declared");
    }
  }

  void checkDirectiveDefinition(String name) {
    if (directiveDefinitions.containsKey(name)) {
      throw ParseException("Directive $name has already been declared");
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

  void addQueryDefinitionSkipIfExists(GQQueryDefinition definition) {
    if (queries.containsKey(definition.token)) {
      logger.i("${definition.type} ${definition.token} is already defined, skipping generation");
      return;
    }
    queries[definition.token] = definition;
  }

  void convertUnionsToInterfaces() {
    //
    unions.forEach((k, union) {
      var interfaceDef = GQInterfaceDefinition(
          name: union.token,
          nameDeclared: false,
          fields: [],
          parentNames: {},
          directives: [],
          interfaceNames: {});
      addInterfaceDefinition(interfaceDef);

      for (var typeName in union.typeNames) {
        var type = getType(typeName);
        type.interfaceNames.add(union.token);
      }
    });
  }

  fillQueryElementArgumentTypes(GQQueryElement element, GQQueryDefinition query) {
    for (var arg in element.arguments) {
      var list = query.arguments.where((a) => a.token == arg.value).toList();
      if (list.isEmpty) {
        throw ParseException("Could not find argument ${arg.value} on query ${query.token}");
      }
      arg.type = list.first.type;
    }
  }

  fillQueryElementsReturnType() {
    queries.forEach((name, queryDefinition) {
      for (var element in queryDefinition.elements) {
        element.returnType = getTypeFromFieldName(element.token, schema.getByQueryType(queryDefinition.type));
        fillQueryElementArgumentTypes(element, queryDefinition);
      }
    });
  }

  void checmEnumDefinition(GQEnumDefinition enumDefinition) {
    if (enums.containsKey(enumDefinition.token)) {
      throw ParseException("Enum ${enumDefinition.token} has already been declared");
    }
  }

  void checkInterfaceDefinition(GQInterfaceDefinition interface) {
    if (interfaces.containsKey(interface.token)) {
      throw ParseException("Interface ${interface.token} has already been declared");
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
        scalars.containsKey(typeName)) {
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
        getFragment(ref.fragmentName!, typedFragment.onTypeName);
      }
    });
  }

  void checkFragmentDefinition(GQFragmentDefinitionBase fragment) {
    if (fragments.containsKey(fragment.token)) {
      throw ParseException("Fragment ${fragment.token} has already been declared");
    }
  }

  void checkQueryDefinition(String token) {
    if (queries.containsKey(token)) {
      throw ParseException("Query $token has already been declared");
    }
  }

  void checkType(String name) {
    bool b = scalars.containsKey(name) ||
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
    if (!scalars.containsKey(scalarName)) {
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

  void validateProjection(GQProjection projection, String typeName, String? fragmentName) {
    var type = getType(typeName);
    if (projection is GQInlineFragmentsProjection) {
      var type = getType(typeName);

      if (type is GQInterfaceDefinition || type is GQUnionDefinition) {
        //handl for interface
        projection.inlineFragments.map((e) => e.onTypeName).map((e) => getType(e)).forEach((type) {
          if (!type.interfaceNames.contains(typeName)) {
            throw ParseException("Type '${type.token}' does not implement '$typeName'");
          }
        });

        for (var inlineFrag in projection.inlineFragments) {
          inlineFrag.block.projections.forEach((key, proj) {
            validateProjection(proj, inlineFrag.onTypeName, null);
          });
        }
      }
      return;
    }
    if (projection.isFragmentReference) {
      GQFragmentDefinitionBase fragment = getFragment(projection.token, typeName);
      if (fragment.onTypeName != type.token && !type.interfaceNames.contains(fragment.onTypeName)) {
        throw ParseException("Fragment ${fragment.token} cannot be applied to type ${type.token}");
      }
      if (projection.token == allFields) {
        projection.fragmentName = '${allFields}_$typeName';
      }
    } else {
      var requiresProjection = fieldRequiresProjection(projection.token, typeName);

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
    final name = type.inlineType.token;
    return types.containsKey(name) || interfaces.containsKey(name) || unions.containsKey(name);
  }

  bool inputTypeRequiresProjection(GQType type) {
    return inputs[type.token] != null;
  }

  GQType getFieldType(String fieldName, String typeName) {
    var onType = getType(typeName);

    var result = onType.fields.where((element) => element.name == fieldName);
    if (result.isEmpty && fieldName != GQGrammar.typename) {
      throw ParseException("Could not find field '$fieldName' on type '$typeName'");
    } else {
      if (result.isNotEmpty) {
        return result.first.type;
      } else {
        return GQType(getLangType("String"), false);
      }
    }
  }

  void updateFragmentAllTypesDependencies() {
    fragments.forEach((key, fragment) {
      fragment.block.projections.values.where((projection) => projection.block == null).forEach((projection) {
        handleFragmentDepenecy(fragment, projection);
      });
    });
  }

  void handleFragmentDepenecy(GQFragmentDefinitionBase fragment, GQProjection projection) {
    if (projection is GQInlineFragmentsProjection) {
      for (var inlineFrag in projection.inlineFragments) {
        inlineFrag.block.projections.forEach((k, proj) {
          if (projection.block == null) {
            handleFragmentDepenecy(fragment, proj);
          }
        });
      }
    } else if (projection.isFragmentReference) {
      var fragmentRef = getFragment(projection.targetToken);
      fragment.addDependecy(fragmentRef);
    } else {
      var type = getType(fragment.onTypeName);
      var field = findFieldByName(projection.token, type);
      if (types.containsKey(field.type.token)) {
        fragment.addDependecy(fragments[field.type.token]!);
      }
    }
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
        throw ParseException("Could not find field '$fieldName' on type ${dataType.token}");
      }
    }
    return filtered.first;
  }

  GQType getTypeFromFieldName(String fieldName, String typeName) {
    var type = getType(typeName);

    var fields = type.fields.where((element) => element.name == fieldName).toList();
    if (fields.isEmpty) {
      throw ParseException("$typeName does not declare a field with name $fieldName");
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

  GQFragmentDefinitionBase getFragment(String name, [String? typeName]) {
    String fragmentName;
    if (name == allFields && typeName != null) {
      fragmentName = '${allFields}_$typeName';
    } else {
      fragmentName = name;
    }
    final fragment = fragments[fragmentName];
    if (fragment == null) {
      throw ParseException("Fragment '$fragmentName' is not defined");
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
      typedFragments[key] = GQTypedFragment(fragment, getType(fragment.onTypeName));
    });
  }

  void createAllFieldsFragments() {
    var allTypes = {...types, ...interfaces};
    allTypes.forEach((key, typeDefinition) {
      if (![schema.mutation, schema.query, schema.subscription].contains(key)) {
        var allFieldsKey = allFieldsFragmentName(key);
        if (fragments[allFieldsKey] != null) {
          throw ParseException("Fragment $allFieldsKey is Already defined");
        }
        if (typeDefinition is GQInterfaceDefinition) {
          var block = createProjectionBlockForInterface(typeDefinition);
          fragments[allFieldsKey] = GQFragmentDefinition(allFieldsKey, typeDefinition.token, block, []);
        } else {
          fragments[allFieldsKey] = GQFragmentDefinition(
              allFieldsKey,
              typeDefinition.token,
              GQFragmentBlockDefinition(typeDefinition
                  .getSerializableFields(this)
                  .map((field) => GQProjection(
                      fragmentName: null,
                      token: field.name,
                      alias: null,
                      block: createAllFieldBlock(field),
                      directives: []))
                  .toList()),
              []);
        }
      }
    });
  }

  static String allFieldsFragmentName(String token) {
    return "${allFields}_$token";
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
        block: null,
        directives: [],
      )
    ]);
  }

  void generateImplementedInterfaces() {
    final projectedTypes = {...this.projectedTypes};
    final interfaceNames = <String>{};
    projectedTypes.forEach((k, type) {
      interfaceNames.addAll(type.interfaceNames);
    });
    interfaceNames.removeAll(projectedTypes.keys);
    for (var name in interfaceNames) {
      var interface = interfaces[name]!;
      var type = GQTypeDefinition(
          name: interface.token,
          nameDeclared: false,
          fields: [],
          interfaceNames: {...interface.interfaceNames, ...interface.parentNames},
          directives: interface.getDirectives(),
          derivedFromType: null);
      // add to projected types without similarity check
      addToProjectedType(type, similarityCheck: false);
    }
  }

  void createProjectedTypes() {
    final allEmenets = getAllElements();
    allEmenets.where((e) => e.block != null).forEach((element) {
      var newType = createProjectedTypeForQuery(element);
      element.projectedTypeKey = newType.token;
    });

    allEmenets.where((e) => e.projectedTypeKey != null).forEach((element) {
      element.projectedType = projectedTypes[element.projectedTypeKey!]!;
    });

    queries.forEach((key, query) {
      var projectedType = query.getGeneratedTypeDefinition();
      if (projectedTypes.containsKey(projectedType.token)) {
        throw ParseException("Type ${projectedType.token} has already been defined, please rename it");
      }
      var def = addToProjectedType(projectedType);
      query.updateTypeDefinition(def);
    });
  }

  GQTypeDefinition createProjectedTypeForQuery(GQQueryElement element) {
    var type = element.returnType;
    var block = element.block!;
    var onType = getType(type.inlineType.token);
    var name = generateName(onType.token, block, element.getDirectives());

    //in case of interface

    var newType = GQTypeDefinition(
      name: name.value,
      nameDeclared: name.declared,
      fields: applyProjection(onType, block.projections),
      interfaceNames: onType.interfaceNames,
      directives: [...element.getDirectives(), ...onType.getDirectives()],
      derivedFromType: onType,
    );
    // check for super types
    if (onType is GQInterfaceDefinition) {
      var map = <GQTypeDefinition>{};
      //generate implementations ...
      block.projections.values.whereType<GQInlineFragmentsProjection>().forEach((inlineFrag) {
        var result = generateSubClasses(newType, onType, inlineFrag);
        map.addAll(result);
      });
      newType.subTypes.addAll(map);
    }
    return addToProjectedType(newType);
  }

  Set<GQTypeDefinition> generateSubClasses(
    GQTypeDefinition superType,
    GQInterfaceDefinition onType,
    GQInlineFragmentsProjection projection,
  ) {
    var result = <String, GQTypeDefinition>{};
    projection.inlineFragments.map((inlineFragProjection) {
      var name = generateName(
          inlineFragProjection.onTypeName, inlineFragProjection.block, inlineFragProjection.getDirectives());
      var subType = getType(inlineFragProjection.onTypeName);
      var generatedType = GQTypeDefinition(
        name: name.value,
        nameDeclared: name.declared,
        fields: applyProjection(subType, inlineFragProjection.block.projections),
        interfaceNames: subType.interfaceNames,
        directives: subType.getDirectives(),
        derivedFromType: subType,
      );
      generatedType.interfaceNames.add(superType.token);
      return generatedType;
    }).forEach((type) {
      result[type.token] = addToProjectedType(type);
    });

    return result.values.toSet();
  }

  GQTypeDefinition createProjectedTypeWithProjectionBlock(
      GQField field, GQTypeDefinition nonProjectedType, GQFragmentBlockDefinition block,
      [List<GQDirectiveValue> fieldDirectives = const []]) {
    var projections = {...block.projections};
    var name = generateName(nonProjectedType.token, block, fieldDirectives);
    var definition = findByOriginalToken(name.value);
    if (definition != null) {
      return definition;
    }
    block.projections.values
        .where((element) => element.isFragmentReference)
        .map((e) => getFragment(e.fragmentName!, nonProjectedType.token))
        .forEach((frag) {
      projections.addAll(frag.block.projections);
    });
    var result = GQTypeDefinition(
      name: name.value,
      nameDeclared: name.declared,
      fields: applyProjection(nonProjectedType, projections),
      interfaceNames: {},
      directives: [],
      derivedFromType: nonProjectedType,
    );

    return addToProjectedType(result);
  }

  GQTypeDefinition addToProjectedType(GQTypeDefinition definition, {bool similarityCheck = true}) {
    if (definition.nameDeclared) {
      var type = projectedTypes[definition.token];
      if (type == null) {
        if (similarityCheck) {
          var similarDefinitions = findSimilarTo(definition);
          if (similarDefinitions.isNotEmpty) {
            similarDefinitions.where((element) => !element.nameDeclared).forEach((e) {
              var currentDef = projectedTypes[e.token];
              if (currentDef != null) {
                definition.interfaceNames.addAll(currentDef.interfaceNames);
                definition.subTypes.addAll(currentDef.subTypes);
              }
              projectedTypes[e.token] = definition;
            });
          }
        }

        projectedTypes[definition.token] = definition;
        definition.originalTokens.add(definition.token);
        return definition;
      } else {
        if (type.isSimilarTo(definition, this)) {
          type.originalTokens.add(definition.token);
          return type;
        } else {
          throw ParseException(
              "You have names two object the same name '${definition.token}' but have diffrent fields. ${definition.token}_1.fields are: [${type.fields.map((f) => "${f.name}: ${f.type.serialize()}").toList()}], ${definition.token}_2.fields are: [${definition.fields.map((f) => "${f.name}: ${f.type.serialize()}").toList()}]. Please consider renaming one of them");
        }
      }
    }

    if (similarityCheck) {
      var similarDefinitions = findSimilarTo(definition);

      if (similarDefinitions.isNotEmpty) {
        var first = similarDefinitions.first;
        first.originalTokens.add(definition.token);
        first.interfaceNames.addAll(definition.interfaceNames);
        first.subTypes.addAll(definition.subTypes);
        projectedTypes[first.token] = first;
        return first;
      }
    }

    String key = definition.token;
    projectedTypes[key] = definition;
    definition.originalTokens.add(key);
    return projectedTypes[key]!;
  }

  GQTypeDefinition? findByOriginalToken(String originalToken) {
    var values = projectedTypes.values;
    for (var value in values) {
      if (value.originalTokens.contains(originalToken)) {
        return value;
      }
    }
    return null;
  }

  List<GQTypeDefinition> findSimilarTo(GQTypeDefinition definition) {
    return [
      ...projectedTypes.values,
      ...types.values,
    ].where((element) => element.isSimilarTo(definition, this)).toList();
  }

  GeneratedTypeName generateName(
      String originalName, GQFragmentBlockDefinition block, List<GQDirectiveValue> directives) {
    String? name = getNameValueFromDirectives(directives);

    if (name != null) {
      return GeneratedTypeName(name, true);
    }
    // check if we have similar objects
    if (interfaces.containsKey(originalName)) {
      return GeneratedTypeName(originalName, false);
    }
    name = "${originalName}_${block.getUniqueName(this)}";
    String nameTemplate = name;

    int nameIndex = 0;
    if (name.endsWith("_*")) {
      nameTemplate = name.replaceFirst("_*", "");
      name = "${name.substring(0, name.length - 2)}_$nameIndex";
    }
    if (projectedTypes.containsKey(name)) {
      while (projectedTypes.containsKey(name)) {
        name = "${nameTemplate}_${++nameIndex}";
      }
    }
    return GeneratedTypeName(name ?? nameTemplate, false);
  }

  generateQueryDefinitions() {
    var queryDeclarations = types[schema.query];
    if (queryDeclarations != null) {
      generateQueries(queryDeclarations, GQQueryType.query);
    }

    var mutationDeclarations = types[schema.mutation];
    if (mutationDeclarations != null) {
      generateQueries(mutationDeclarations, GQQueryType.mutation);
    }

    var subscriptionDeclarations = types[schema.subscription];
    if (subscriptionDeclarations != null) {
      generateQueries(subscriptionDeclarations, GQQueryType.subscription);
    }
  }

  void generateQueries(GQTypeDefinition def, GQQueryType queryType) {
    for (var field in def.fields) {
      generateForField(field, queryType);
    }
  }

  void generateForField(GQField field, GQQueryType queryType) {
    GQFragmentBlockDefinition? block;
    if (typeRequiresProjection(field.type.inlineType)) {
      final fragName = "${allFields}_${field.type.inlineType.token}";
      getFragment(fragName);
      block = GQFragmentBlockDefinition(
          [GQProjection(fragmentName: fragName, token: fragName, alias: null, block: null, directives: [])]);
    }

    var argValues = field.arguments.map((arg) {
      return GQArgumentValue(arg.token, "\$${arg.token}");
    }).toList();
    var queryElement = GQQueryElement(field.name, [], block, argValues, defaultAlias);
    final def = GQQueryDefinition(
        field.name,
        [],
        field.arguments
            .map((e) => GQArgumentDefinition("\$${e.token}", e.type, [], initialValue: e.initialValue))
            .toList(),
        [queryElement],
        queryType);
    addQueryDefinitionSkipIfExists(def);
  }

  GQFragmentBlockDefinition createProjectionBlockForInterface(GQInterfaceDefinition interface) {
    var types = getTypesImplementing(interface);
    var inlineFrags = <GQInlineFragmentDefinition>[];
    types.map((t) {
      var token = "${allFields}_${t.token}";
      var inlineDef = GQInlineFragmentDefinition(
          t.token,
          GQFragmentBlockDefinition(
              [GQProjection(fragmentName: token, token: token, alias: null, block: null, directives: [])]),
          []);
      inlineFrags.add(inlineDef);
    }).toList();

    var prj = GQInlineFragmentsProjection(inlineFragments: inlineFrags);
    return GQFragmentBlockDefinition([prj]);
  }

  List<GQTypeDefinition> getTypesImplementing(GQInterfaceDefinition def) {
    var result = <GQTypeDefinition>[];
    types.forEach((k, v) {
      if (v.interfaceNames.contains(def.token)) {
        result.add(v);
      }
    });
    return result;
  }

  List<GQField> applyProjection(GQTypeDefinition type, Map<String, GQProjection> p) {
    var src = type.fields;
    var result = <GQField>[];
    var projections = {...p};
    p.forEach((key, value) {
      if (value.isFragmentReference) {
        var fragment = getFragment(value.fragmentName!, type.token);
        projections.addAll(fragment.block.getAllProjections(this));
      }
    });

    if (type is! GQInterfaceDefinition) {
      p.values
          .whereType<GQInlineFragmentsProjection>()
          .expand((e) => e.inlineFragments)
          .forEach((inlineFrag) {
        projections.addAll(inlineFrag.block.projections);
      });
    }

    for (var field in src) {
      var projection = projections[field.name];
      if (projection != null) {
        result.add(applyProjectionToField(field, projection, projection.getDirectives()));
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
      var fieldInlineType = GQType(generatedType.token, field.type.nullable, isScalar: false);

      return GQField(
        name: fieldName,
        type: createTypeFrom(field.type, fieldInlineType),
        arguments: field.arguments,
        directives: projection.getDirectives(),
      );
    }

    return GQField(
      name: fieldName,
      type: createTypeFrom(field.type, field.type),
      arguments: field.arguments,
      directives: projection.getDirectives(),
    );
  }

  GQType createTypeFrom(GQType orig, GQType inline) {
    if (orig is GQListType) {
      return GQListType(createTypeFrom(orig.type, inline), orig.nullable);
    }
    return GQType(inline.token, orig.inlineType.nullable, isScalar: inline.isScalar);
  }

  String getLangType(String typeName) {
    var result = typeMap[typeName];
    if (result == null) {
      throw ParseException("Unknown type $typeName");
    }
    return result;
  }

  String toConstructorDeclaration(GQField field) {
    if (nullableFieldsRequired || !field.type.nullable) {
      return "required this.${field.name}";
    } else {
      return "this.${field.name}";
    }
  }

  static List<String> extractDecorators(
      {required List<GQDirectiveValue> directives, required CodeGenerationMode mode}) {
    // find the list
    var decorators = directives
        .where((d) => d.token == gqDecorators)
        .where((d) {
          switch (mode) {
            case CodeGenerationMode.client:
              return d.getArguments().where((arg) => arg.token == "applyOnClient").first.value as bool;
            case CodeGenerationMode.server:
              return d.getArguments().where((arg) => arg.token == "applyOnServer").first.value as bool;
          }
        })
        .map((d) {
          return d.getArguments().where((arg) => arg.token == "value").first;
        })
        .map((d) {
          var decoratorValues = ((d.value as List)[1] as List)
              .map((e) => e as String)
              .map((str) => str.removeQuotes())
              .toList();
          return decoratorValues;
        })
        .expand((inner) => inner)
        .toList();
    return decorators;
  }

  bool shouldSkipSerialization({required List<GQDirectiveValue> directives}) {
    String token;
    switch (mode) {
      case CodeGenerationMode.client:
        token = gqSkipOnClient;
        break;
      case CodeGenerationMode.server:
        token = gqSkipOnServer;
        break;
    }
    var skipOnList = directives.where((d) => d.token == token).toList();
    return skipOnList.isNotEmpty;
  }
}

class GeneratedTypeName {
  // the generated name value
  final String value;
  //true if the name has been declared using @gqTypeName directive
  final bool declared;

  GeneratedTypeName(this.value, this.declared);
}
