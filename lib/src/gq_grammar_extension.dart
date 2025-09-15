import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_argument.dart';
import 'package:retrofit_graphql/src/model/gq_controller.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_directives_mixin.dart';
import 'package:retrofit_graphql/src/model/gq_service.dart';
import 'package:retrofit_graphql/src/model/gq_shcema_mapping.dart';
import 'package:retrofit_graphql/src/model/gq_enum_definition.dart';
import 'package:retrofit_graphql/src/model/gq_fragment.dart';
import 'package:retrofit_graphql/src/model/gq_interface_definition.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/model/gq_queries.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:retrofit_graphql/src/utils.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';

const String allFieldsFragmentsFileName = "allFieldsFragments";

const allFields = '_all_fields';

extension GQGrammarExtension on GQGrammar {
  GQToken? getTokenByKey(String key) {
    GQToken? token;

    if (isEnum(key)) {
      token = enums[key]!;
    } else if (types.containsKey(key)) {
      token = types[key]!;
    } else if (interfaces.containsKey(key)) {
      token = interfaces[key]!;
    } else if (isScalar(key)) {
      token = scalars[key];
    } else if (projectedTypes.containsKey(key)) {
      token = projectedTypes[key]!;
    } else if (inputs.containsKey(key)) {
      token = inputs[key]!;
    } else if (services.containsKey(key)) {
      token = services[key]!;
    } else if (controllers.containsKey(key)) {
      token = controllers[key]!;
    }
    return token;
  }

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

  List<GQDirectivesMixin> getDirectiveObjects() {
    var result = [
      ...inputs.values,
      ...types.values,
      ...interfaces.values,
      ...scalars.values,
      ...enums.values,
      ...repositories.values
    ].map((f) => f as GQDirectivesMixin).toList();

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
    var params = <GQDirectivesMixin>[];
    result.whereType<GQField>().where((f) => f.arguments.isNotEmpty).forEach((f) {
      params.addAll(f.arguments);
    });
    result.addAll(params);

    return result;
  }

  void fillInterfaceImplementations() {
    var ifaces = interfaces.values;
    for (var iface in ifaces) {
      var types = getTypesImplementing(iface);
      types.forEach(iface.addImplementation);
    }
  }

  void handleGqExternal() {
    [...inputs.values, ...types.values, ...interfaces.values, ...scalars.values, ...enums.values]
        .map((f) => f as GQDirectivesMixin)
        .where((t) => t.getDirectiveByName(gqExternal) != null)
        .forEach((f) {
      f.addDirectiveIfAbsent(GQDirectiveValue.createDirectiveValue(directiveName: gqSkipOnClient, generated: true));
      f.addDirectiveIfAbsent(GQDirectiveValue.createDirectiveValue(directiveName: gqSkipOnServer, generated: true));
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
        f.addDirectiveIfAbsent(GQDirectiveValue.createDirectiveValue(directiveName: gqSkipOnServer, generated: true));
      }
    });
  }

  void handleDirectiveInheritance() {
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
            f.getDirectives().forEach((d) => typeField.addDirectiveIfAbsent(d));
          }
        }
      }
    }
  }

  void _addSchemaMapping(GQSchemaMapping mapping) {
    var service = services[mapping.serviceName]!;
    var ctrl = controllers["${mapping.serviceName}Controller"]!;
    service.addMapping(mapping);
    ctrl.addMapping(mapping);
  }

  void generateServicesAndControllers() {
    for (var type in GQQueryType.values) {
      _doGenerateServices(types[schema.getByQueryType(type)]?.fields ?? [], type);
    }
    for (var s in services.values) {
      var ctrl = GQController.ofService(s);
      controllers[ctrl.token] = ctrl;
    }
  }

  void _doGenerateServices(List<GQField> fields, GQQueryType type) {
    for (var field in fields) {
      var name = getServiceName(field);
      var service = services[name] ??=
          GQService(name: name.toToken(), nameDeclared: true, directives: [], fields: [], interfaceNames: {});
      service.addField(field);
      service.setFieldType(field.name.token, type);
      services.putIfAbsent(name, () => service);
    }
  }

  String getServiceName(GQField field, [String suffix = "Service"]) {
    var serviceName = field.getDirectiveByName(gqServiceName)?.getArgValueAsString(gqServiceNameArg);
    if (serviceName == null) {
      if (typeRequiresProjection(field.type)) {
        serviceName = "${field.type.token.firstUp}$suffix";
      } else {
        serviceName = "${field.name.token.firstUp}$suffix";
      }
    }
    if (suffix.isNotEmpty && !serviceName.endsWith(suffix)) {
      serviceName += suffix;
    }
    return serviceName;
  }

  GQField? _getIdentityField(GQTypeDefinition type) {
    var mapsTo = type.getDirectiveByName(gqSkipOnServer)?.getArgValueAsString(gqMapTo);
    var skipOnServerFields = type.getSkipOnServerFields();
    if (mapsTo != null) {
      var list = skipOnServerFields.where((e) => e.type.token == mapsTo && e.type.isNotList).toList();
      if (list.length == 1) {
        return list.first;
      }
    }
    return null;
  }

  void genSchemaMappings(List<GQField> queryFields, GQQueryType queryType) {
    for (var field in queryFields) {
      var type = getType(field.type.tokenInfo);
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

        _addSchemaMapping(schemaMappings);
      }
      type.getSkinOnClientFields().forEach((typeField) {
        _addSchemaMapping(GQSchemaMapping(
            type: type, field: typeField, forbid: true, serviceName: getServiceName(field), queryType: queryType));
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

  void setDirectivesDefaulValues() {
    var values = [...directiveValues];
    for (var value in values) {
      var def = directiveDefinitions[value.token];
      if (def != null) {
        value.setDefualtArguments(def.arguments);
      }
    }
  }

  void convertUnionsToInterfaces() {
    //
    unions.forEach((k, union) {
      var interfaceDef = GQInterfaceDefinition(
          name: union.tokenInfo,
          nameDeclared: false,
          fields: getUnionFields(union),
          directives: [],
          interfaceNames: {},
          fromUnion: true);
      addInterfaceDefinition(interfaceDef);

      for (var typeName in union.typeNames) {
        var type = getType(typeName);
        type.addInterfaceName(union.tokenInfo);
      }
    });
  }

  fillQueryElementArgumentTypes(GQQueryElement element, GQQueryDefinition query) {
    for (var arg in element.arguments) {
      var list = query.arguments.where((a) => a.token == arg.value).toList();
      if (list.isEmpty) {
        throw ParseException("Could not find argument ${arg.value} on query ${query.tokenInfo}", info: arg.tokenInfo);
      }
      arg.type = list.first.type;
    }
  }

  fillQueryElementsReturnType() {
    queries.forEach((name, queryDefinition) {
      for (var element in queryDefinition.elements) {
        element.returnType =
            getTypeFromFieldName(element.token, schema.getByQueryType(queryDefinition.type), element.tokenInfo);
        fillQueryElementArgumentTypes(element, queryDefinition);
      }
    });
  }

  void checmEnumDefinition(GQEnumDefinition enumDefinition) {
    if (enums.containsKey(enumDefinition.token)) {
      throw ParseException("Enum ${enumDefinition.tokenInfo} has already been declared",
          info: enumDefinition.tokenInfo);
    }
  }

  List<GQQueryElement> getAllElements() {
    return queries.values.expand((q) => q.elements).toList();
  }

  GQType getFieldType(TokenInfo fieldNameToken, String typeName) {
    var fieldName = fieldNameToken.token;
    var onType = getType(fieldNameToken.ofNewName(typeName));

    var result = onType.fields.where((element) => element.name.token == fieldName);
    if (result.isEmpty && fieldName != GQGrammar.typename) {
      throw ParseException("Could not find field '$fieldName' on type '$typeName'", info: fieldNameToken);
    } else {
      if (result.isNotEmpty) {
        return result.first.type;
      } else {
        return GQType(getLangType("String").toToken(), false);
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
      var fragmentRef = getFragment(projection.targetToken, projection.tokenInfo);

      fragment.addDependecy(fragmentRef);
    } else {
      var type = getType(fragment.onTypeName);
      var field = type.findFieldByName(projection.token, this);
      if (types.containsKey(field.type.token)) {
        fragment.addDependecy(fragments[field.type.token]!);
      }
    }
  }

  GQType getTypeFromFieldName(String fieldName, String typeName, TokenInfo fieldToken) {
    var type = getType(fieldToken.ofNewName(typeName));

    var fields = type.fields.where((element) => element.name.token == fieldName).toList();
    if (fields.isEmpty) {
      throw ParseException("$typeName does not declare a field with name $fieldName", info: type.tokenInfo);
    }
    return fields.first.type;
  }

  void updateFragmentDependencies() {
    fragments.forEach((key, value) {
      value.updateDepencies(fragments);
    });
  }

  void fillTypedFragments() {
    fragments.forEach((key, fragment) {
      checkIfDefined(fragment.onTypeName);
      typedFragments[key] = GQTypedFragment(fragment, getType(fragment.onTypeName));
    });
  }

  GQFragmentDefinition createAllFieldsFragment(GQTypeDefinition typeDefinition) {
    var key = typeDefinition.token;

    var allFieldsKey = allFieldsFragmentName(key);
    if (fragments[allFieldsKey] != null) {
      throw ParseException("Fragment $allFieldsKey is Already defined", info: fragments[allFieldsKey]!.tokenInfo);
    }
    if (typeDefinition is GQInterfaceDefinition) {
      var projection = _createProjectionForInterface(typeDefinition);
      var block = GQFragmentBlockDefinition([projection]);
      return GQFragmentDefinition(allFieldsKey.toToken(), typeDefinition.tokenInfo, block, []);
    } else {
      return GQFragmentDefinition(
          allFieldsKey.toToken(),
          typeDefinition.tokenInfo,
          GQFragmentBlockDefinition(typeDefinition
              .getSerializableFields(mode)
              .map((field) => GQProjection(
                    fragmentName: null,
                    token: field.name,
                    alias: null,
                    block: createAllFieldBlock(field),
                    directives: [],
                  ))
              .toList()),
          []);
    }
  }

  void createAllFieldsFragments() {
    var allTypes = {...types, ...interfaces};
    allTypes.forEach((key, typeDefinition) {
      if (![schema.mutation, schema.query, schema.subscription].contains(key)) {
        var frag = createAllFieldsFragment(typeDefinition);
        addFragmentDefinition(frag);
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
        token: field.type.inlineType.tokenInfo.ofNewName(allFieldsFragmentName(field.type.inlineType.token)),
        alias: null,
        block: null,
        directives: [],
      )
    ]);
  }

  GQInterfaceDefinition _regiterInterface(GQInterfaceDefinition def, GQTypeDefinition implementation) {
    var name = def.token;
    if (projectedTypes.containsKey(name)) {
      var iface = projectedTypes[name]! as GQInterfaceDefinition;
      iface.addImplementation(implementation);
      return iface;
    }
    var newType = GQInterfaceDefinition(
      name: def.tokenInfo.ofNewName(name),
      nameDeclared: false,
      fields: [],
      interfaceNames: {...def.interfaceNames},
      directives: def.getDirectives(),
    );
    newType.addImplementation(implementation);
    return addToProjectedTypes(newType, similarityCheck: false) as GQInterfaceDefinition;
  }

  void updateInterfaceReferences() {
    var allTypes = [...interfaces.values, ...types.values];
    allTypes.where((type) => type.interfaceNames.isNotEmpty).forEach((type) {
      var result = type.interfaceNames.map((token) => getInterface(token.token, token));
      result.forEach(type.addInterface);
    });
  }

  void updateInterfaceCommonFields() {
    projectedTypes.values.whereType<GQInterfaceDefinition>().forEach((i) {
      var commonFields = _getCommonInterfaceFields(i);
      for (var cf in commonFields) {
        i.addField(cf);
      }
    });
  }

  List<GQField> _getCommonInterfaceFields(GQInterfaceDefinition def) {
    // search in projected types, types that have implemented this interface
    var types = getProjectdeTypesImplementing(def);
    if (types.isEmpty) {
      return [];
    }
    var map = <String, int>{};
    final fields = interfaces[def.token]!.fields;
    var interfaceFieldNames = interfaces[def.token]!.fields.map((f) => f.name.token).toSet();

    types.expand((t) => t.fields).forEach((f) {
      if (map.containsKey(f.name.token)) {
        map[f.name.token] = map[f.name.token]! + 1;
      } else {
        map[f.name.token] = 1;
      }
    });

    var result = <GQField>[];
    map.forEach((fieldName, count) {
      if (count == types.length && interfaceFieldNames.contains(fieldName)) {
        result.addAll(fields.where((f) => f.name.token == fieldName));
      }
    });
    return result;
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
        throw ParseException("Type ${projectedType.tokenInfo.token} has already been defined, please rename it",
            info: projectedType.tokenInfo);
      }
      var def = addToProjectedTypes(projectedType);
      query.updateTypeDefinition(def);
    });
  }

  GQTypeDefinition createProjectedTypeForQuery(GQQueryElement element) {
    var type = element.returnType;
    var block = element.block!;
    var onType = getType(type.inlineType.tokenInfo);
    return createProjectedType(type: onType, projectionMap: block.projections, directives: element.getDirectives());
  }

  GQTypeDefinition addToProjectedTypes(GQTypeDefinition definition, {bool similarityCheck = true}) {
    if (definition.nameDeclared) {
      var type = projectedTypes[definition.token];
      if (type == null) {
        if (similarityCheck) {
          var similarDefinitions = findSimilarTo(definition);
          if (similarDefinitions.isNotEmpty) {
            similarDefinitions.where((element) => !element.nameDeclared).forEach((e) {
              var currentDef = projectedTypes[e.token];
              if (currentDef != null) {
                currentDef.interfaceNames.forEach(definition.addInterfaceName);
                if (currentDef is GQInterfaceDefinition && definition is GQInterfaceDefinition) {
                  currentDef.implementations.forEach(definition.addImplementation);
                }
              }
              projectedTypes[e.token] = definition;
            });
          }
        }

        projectedTypes[definition.token] = definition;
        definition.addOriginalToken(definition.token);
        return definition;
      } else {
        if (type.isSimilarTo(definition, this)) {
          type.addOriginalToken(definition.token);
          return type;
        } else {
          var typeTokenInfo = type.getDirectiveByName(gqTypeNameDirective)?.getArgumentByName('name')?.tokenInfo;
          throw ParseException(
              "You have names two object the same name '${definition.tokenInfo}' but have diffrent fields. ${definition.tokenInfo}_1.fields are: [${type.fields.map((f) => "${f.name}: ${serializer.serializeType(f.type)}").toList()}], ${definition.tokenInfo}_2.fields are: [${definition.fields.map((f) => "${f.name}: ${serializer.serializeType(f.type)}").toList()}]. Please consider renaming one of them",
              info: typeTokenInfo ?? type.tokenInfo);
        }
      }
    }

    if (similarityCheck) {
      var similarDefinitions = findSimilarTo(definition);

      if (similarDefinitions.isNotEmpty) {
        var first = similarDefinitions.first;
        first.addOriginalToken(definition.token);
        definition.interfaceNames.forEach(first.addInterfaceName);
        if (definition is GQInterfaceDefinition && first is GQInterfaceDefinition) {
          definition.implementations.forEach(first.addImplementation);
        }
        projectedTypes[first.token] = first;
        return first;
      }
    }

    String key = definition.token;
    projectedTypes[key] = definition;
    definition.addOriginalToken(key);
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
    if (definition is GQInterfaceDefinition) {
      return [];
    }
    return [
      ...projectedTypes.values,
      ...types.values,
    ].where((element) => element.isSimilarTo(definition, this))
    //filter out the Query, Mutation, Subscription
    .where((e) => !schema.queryNamesSet.contains(e.token))
    .toList();
  }

  String getUniqueName(Iterable<GQProjection> projections) {
    //@Todo check the inline fragment case.
    var keys = projections
        .map((e) => e.token)
        .where((t) => !t.endsWith("\*"))
        .where((t) => t != GQGrammar.typename)
        .toSet()
        .toList();
    keys.sort();
    return keys.join("_");
  }

  GeneratedTypeName _generateName(
      String originalName, Iterable<GQProjection> projections, List<GQDirectiveValue> directives) {
    String? name = getNameValueFromDirectives(directives);

    if (name != null) {
      return GeneratedTypeName(name, true);
    }

    name = "${originalName}_${getUniqueName(projections)}";
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

  String generateAllFieldFragment(GQType type) {
    // check if type is an interface

    if (interfaces.containsKey(type.token)) {
      var iface = interfaces[type.token]!;
      GQProjection projection = _createProjectionForInterface(iface);

      var block = GQFragmentBlockDefinition([projection]);
      var frag = GQInlineFragmentDefinition(iface.tokenInfo, block, []);
      addFragmentDefinition(frag);
      return frag.token;
    }
    final fragName = "${allFields}_${type.tokenInfo.token}";
    getFragment(fragName, type.tokenInfo);
    return fragName;
  }

  void generateForField(GQField field, GQQueryType queryType) {
    GQFragmentBlockDefinition? block;
    if (typeRequiresProjection(field.type)) {
      final fragName = generateAllFieldFragment(field.type);
      block = GQFragmentBlockDefinition(
          [GQProjection(fragmentName: fragName, token: fragName.toToken(), alias: null, block: null, directives: [])]);
    }

    var argValues = field.arguments.map((arg) {
      return GQArgumentValue(arg.tokenInfo, "\$${arg.tokenInfo}");
    }).toList();
    var queryElement = GQQueryElement(field.name, [], block, argValues, defaultAlias?.toToken());
    final def = GQQueryDefinition(
        field.name,
        [],
        field.arguments
            .map((e) => GQArgumentDefinition("\$${e.tokenInfo}".toToken(), e.type, [], initialValue: e.initialValue))
            .toList(),
        [queryElement],
        queryType);
    addQueryDefinitionSkipIfExists(def);
  }

  GQProjection _createProjectionForInterface(GQInterfaceDefinition interface) {
    var types = getTypesImplementing(interface);
    var inlineFrags = <GQInlineFragmentDefinition>[];

    types.map((t) {
      var token = t.tokenInfo.ofNewName("${allFields}_${t.token}");
      var inlineDef = GQInlineFragmentDefinition(
          t.tokenInfo,
          GQFragmentBlockDefinition(
              [GQProjection(fragmentName: token.token, token: token, alias: null, block: null, directives: [])]),
          []);
      inlineFrags.add(inlineDef);
      addFragmentDefinition(inlineDef);
    }).toList();

    return GQInlineFragmentsProjection(inlineFragments: inlineFrags);
  }

  List<GQTypeDefinition> getProjectdeTypesImplementing(GQInterfaceDefinition def) {
    return projectedTypes.values.where((pt) => pt.getInterfaceNames().contains(def.token)).toList();
  }

  List<GQTypeDefinition> getTypesImplementing(GQInterfaceDefinition def) {
    var result = <GQTypeDefinition>[];
    types.forEach((k, v) {
      if (v.implements(def.token)) {
        result.add(v);
      }
    });
    return result;
  }

  GQTypeDefinition createProjectedType({
    required GQTypeDefinition type,
    required Map<String, GQProjection> projectionMap,
    required List<GQDirectiveValue> directives,
  }) {
    if (type is GQInterfaceDefinition) {
      var implementationTypes = getTypesImplementing(type);
      GQTypeDefinition? result;

      for (var it in implementationTypes) {
        var projections = _collectProjection(projectionMap, it.token);
        if (projections.isNotEmpty) {
          /// when it is an interface, createProjectedTypeOnType will return the same interface, so this loop is safe
          /// even if it does not look safe at first sight.
          result = createProjectedTypeOnType(
            type: type,
            projectionMap: projectionMap,
            directives: type.getDirectives(),

            /// @TODO think about passing directives from inline fragments
            onTypeName: it.token,
          );
        }
      }
      if (result != null) {
        return result;
      }
    }

    return createProjectedTypeOnType(
      type: type,
      projectionMap: projectionMap,
      directives: directives,
      onTypeName: type.token,
    );
  }

  GQTypeDefinition createProjectedTypeOnType({
    required GQTypeDefinition type,
    required Map<String, GQProjection> projectionMap,
    required List<GQDirectiveValue> directives,
    required String onTypeName,
  }) {
    /// type might be an interface, we need to grab the real type from typesm map.
    var realType = type.token == onTypeName ? type : types[onTypeName]!;
    var src = [...realType.fields];

    var result = <GQField>[];
    var projections = _collectProjection(projectionMap, onTypeName);

    for (var field in src) {
      var projection = projections[field.name.token];
      if (projection != null) {
        result.add(_applyProjectionToField(field, projection, projection.getDirectives()));
      }
    }
    var name = _generateName(onTypeName, projections.values, directives);

    var newType = GQTypeDefinition(
      name: name.value.toToken(),
      nameDeclared: name.declared,
      fields: result,
      interfaceNames: {},
      directives: directives,
      derivedFromType: realType,
    );

    if (type is GQInterfaceDefinition) {
      var savedType = addToProjectedTypes(newType);
      var iface = _regiterInterface(type, savedType);
      newType.addInterfaceName(type.tokenInfo);
      return iface;
    } else {
      var savedType = addToProjectedTypes(newType);
      if (type.interfaceNames.isNotEmpty) {
        for (var i in type.interfaceNames) {
          _regiterInterface(interfaces[i.token]!, savedType);
        }
      }
      return savedType;
    }
  }

  Map<String, GQProjection> _collectProjection(Map<String, GQProjection> projections, String onTypeName) {
    var result = <String, GQProjection>{};
    projections.forEach((k, v) {
      if (v.isFragmentReference) {
        var fragment = getFragmentByName(v.fragmentName!)!;
        var r = _collectProjection(fragment.block.projections, onTypeName);
        result.addAll(r);
      } else if (v is GQInlineFragmentsProjection) {
        v.inlineFragments.where((inline) => inline.onTypeName.token == onTypeName).forEach((inline) {
          var r = _collectProjection(inline.block.projections, onTypeName);
          result.addAll(r);
        });
      } else {
        result[k] = v;
      }
    });
    return result;
  }

  GQField _applyProjectionToField(GQField field, GQProjection projection,
      [List<GQDirectiveValue> fieldDirectives = const []]) {
    final TokenInfo fieldName = projection.alias ?? field.name;
    var block = projection.block;

    if (block != null) {
      //we should create another type here ...
      var generatedType = createProjectedType(
        type: getType(field.type.tokenInfo),
        projectionMap: block.projections,
        directives: fieldDirectives,
      );
      var fieldInlineType = GQType(generatedType.tokenInfo, field.type.nullable, isScalar: false);

      return GQField(
        name: fieldName,
        type: _createTypeFrom(field.type, fieldInlineType),
        arguments: field.arguments,
        directives: projection.getDirectives(),
      );
    }

    return GQField(
      name: fieldName,
      type: _createTypeFrom(field.type, field.type),
      arguments: field.arguments,
      directives: projection.getDirectives(),
    );
  }

  GQType _createTypeFrom(GQType orig, GQType inline) {
    if (orig is GQListType) {
      return GQListType(_createTypeFrom(orig.type, inline), orig.nullable);
    }
    return GQType(inline.tokenInfo, orig.inlineType.nullable, isScalar: inline.isScalar);
  }

  String getLangType(String typeName) {
    var result = typeMap[typeName];
    if (result == null) {
      throw ParseException("Unknown type $typeName");
    }
    return result;
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
          var decoratorValues = (d.value as List).map((e) => e as String).map((str) => str.removeQuotes()).toList();
          return decoratorValues;
        })
        .expand((inner) => inner)
        .toList();
    return decorators;
  }
}

class GeneratedTypeName {
  // the generated name value
  final String value;
  //true if the name has been declared using @gqTypeName directive
  final bool declared;

  GeneratedTypeName(this.value, this.declared);
}
