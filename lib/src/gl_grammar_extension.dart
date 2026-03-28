import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_controller.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_shcema_mapping.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_fragment.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/token_info.dart';
import 'package:graphlink/src/serializers/language.dart';
import 'package:graphlink/src/ui/flutter/gl_type_view.dart';
import 'package:graphlink/src/utils.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';

const String allFieldsFragmentsFileName = "allFieldsFragments";

const allFields = '_all_fields';

final Map<String, List<GLTypeDefinition>> _typeHashIndex = {};
final Map<String, List<GLTypeDefinition>> _interfaceHashIndex = {};

extension GLGrammarExtension on GLParser {
  GLToken? getTokenByKey(String key) {
    GLToken? token;

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
    } else if (projectedInterfaces.containsKey(key)) {
      token = projectedInterfaces[key]!;
    } else if (inputs.containsKey(key)) {
      token = inputs[key]!;
    } else if (services.containsKey(key)) {
      token = services[key]!;
    } else if (controllers.containsKey(key)) {
      token = controllers[key]!;
    }
    return token;
  }

  void convertAnnotationsToDecorators(List<GLDirectivesMixin> mixins,
      String Function(GLDirectiveValue value) serializer) {
    for (var elm in mixins) {
      elm
          .getAnnotations(mode: mode)
          .map(
            (an) => GLDirectiveValue.createGqDecorators(
                decorators: [serializer(an)],
                applyOnClient: mode == CodeGenerationMode.client,
                applyOnServer: mode == CodeGenerationMode.server,
                import: an.getArgValueAsString(glImport)),
          )
          .forEach(elm.addDirective);
    }
  }

  void handleAnnotations(String Function(GLDirectiveValue value) serializer) {
    if (annotationsProcessed) {
      return;
    }
    annotationsProcessed = true;
    convertAnnotationsToDecorators(_getDirectiveObjects(), serializer);
  }

  List<GLDirectivesMixin> _getDirectiveObjects() {
    var result = [
      ...inputs.values,
      ...typesWithNoResolvers,
      ...interfaces.values,
      ...scalars.values,
      ...enums.values,
      ...repositories.values,
    ].map((f) => f as GLDirectivesMixin).toList();

    var inputFields = inputs.values.expand((e) => e.fields);
    var interfaceFields = interfaces.values.expand((e) => e.fields);
    var repositoryFields = repositories.values.expand((e) => e.fields);
    var typeFields = typesWithNoResolvers.expand((e) => e.fields);
    var enumValues = enums.values.expand((e) => e.values);
    result.addAll([
      ...inputFields,
      ...interfaceFields,
      ...typeFields,
      ...enumValues,
      ...repositoryFields,
    ]);
    var params = <GLDirectivesMixin>[];
    result
        .whereType<GLField>()
        .where((f) => f.arguments.isNotEmpty)
        .forEach((f) {
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

  void handleGLExternal() {
    [
      ...inputs.values,
      ...types.values,
      ...interfaces.values,
      ...scalars.values,
      ...enums.values
    ]
        .map((f) => f as GLDirectivesMixin)
        .where((t) => t.getDirectiveByName(glExternal) != null)
        .forEach((f) {
      f.addDirectiveIfAbsent(GLDirectiveValue.createDirectiveValue(
          directiveName: glSkipOnClient, generated: true));
      f.addDirectiveIfAbsent(GLDirectiveValue.createDirectiveValue(
          directiveName: glSkipOnServer, generated: true));
    });
  }

  List<GLTypeDefinition> getSerializableTypes() {
    return typesWithNoResolvers.where(_filterByMode).toList();
  }

  List<GLTypeDefinition> get typesWithNoResolvers {
    final queries =
        GLQueryType.values.map((t) => schema.getByQueryType(t)).toSet();
    return types.values.where((type) => !queries.contains(type.token)).toList();
  }

  List<GLInputDefinition> getSerializableInputs() {
    return inputs.values.where(_filterByMode).toList();
  }

  List<GLEnumDefinition> getSerializableEnums() {
    return enums.values.where(_filterByMode).toList();
  }

  List<GLInterfaceDefinition> getSerializableInterfaces() {
    return interfaces.values.where(_filterByMode).toList();
  }

  bool _filterByMode(GLDirectivesMixin mixin) {
    switch (mode) {
      case CodeGenerationMode.client:
        return mixin.getDirectiveByName(glSkipOnClient) == null;
      case CodeGenerationMode.server:
        return mixin.getDirectiveByName(glSkipOnServer) == null;
    }
  }

  void skipFieldOfSkipOnServerTypes() {
    types.values
        .where((t) => t.getDirectiveByName(glSkipOnServer) != null)
        .forEach((t) {
      var argValues = t
          .getDirectiveByName(glSkipOnServer)!
          .getArguments()
          .where((e) => e.token != glMapTo)
          .toList();
      for (var f in t.fields) {
        f.addDirectiveIfAbsent(GLDirectiveValue.createDirectiveValue(
            directiveName: glSkipOnServer, generated: true, args: argValues));
      }
    });
  }

  void generateServicesAndControllers() {
    for (var type in GLQueryType.values) {
      _doGenerateServices(
          types[schema.getByQueryType(type)]?.fields ?? [], type);
    }
    for (var s in services.values) {
      var ctrl = GLController.ofService(s);
      controllers[ctrl.token] = ctrl;
    }
  }

  void _doGenerateServices(List<GLField> fields, GLQueryType type) {
    for (var field in fields) {
      var name = _getServiceName(field);
      var service = services[name] ??= GLService(
          name: name.toToken(),
          nameDeclared: true,
          directives: [],
          fields: [],
          interfaceNames: {});
      service.addField(field);
      service.setFieldType(field.name.token, type);

      var validate = field.getDirectiveByName(glValidate);
      if (validate != null) {
        var validationField = GLField(
            name: field.name
                .ofNewName(GLService.getValidationMethodName(field.name.token)),
            type: field.type,
            arguments: field.arguments,
            directives: [
              GLDirectiveValue.createDirectiveValue(
                  directiveName: glValidate, generated: true),
            ]);
        service.addField(validationField);
        service.setFieldType(validationField.name.token, type);
      }
      services.putIfAbsent(name, () => service);
    }
  }

  String _getServiceName(GLField field, [String suffix = "Service"]) {
    var serviceName = field
        .getDirectiveByName(glServiceName)
        ?.getArgValueAsString(glServiceNameArg);
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

  GLField? _getIdentityField(GLTypeDefinition type) {
    var mapsTo =
        type.getDirectiveByName(glSkipOnServer)?.getArgValueAsString(glMapTo);
    var skipOnServerFields = type.getSkipOnServerFields();
    if (mapsTo != null) {
      var list = skipOnServerFields
          .where((e) => e.type.token == mapsTo && e.type.isNotList)
          .toList();
      if (list.length == 1) {
        return list.first;
      }
    }
    return null;
  }

  void generateSchemaMappings() {
    types.values.forEach(genSchemaMappings);
    // generate Services and controllers for mappings only
    generateSchemaMappingServices();
  }

  void generateSchemaMappingServices() {
    for (var type in types.values) {
      var serviceMappings = getServiceMappingByType(type.token);
      if (serviceMappings.isNotEmpty) {
        var serviceName = serviceMappingName(type.token);
        var service = services[serviceName] ??
            GLService(
                name: serviceName.toToken(),
                nameDeclared: false,
                fields: [],
                directives: [],
                interfaceNames: {});
        serviceMappings.forEach(service.addMapping);
        services[serviceName] = service;

        var controllerMappings = getAllMappingsByType(type.token);
        if (controllerMappings.isNotEmpty) {
          var ctrlName = controllerMappingName(type.token);
          var ctrl = controllers[ctrlName] ??
              GLController(
                serviceName: serviceName,
                name: ctrlName.toToken(),
                nameDeclared: false,
                fields: [],
                interfaceNames: {},
                directives: [],
              );
          controllerMappings.forEach(ctrl.addMapping);
          controllers[ctrlName] = ctrl;
        }
      }
    }
  }

  void genSchemaMappings(GLTypeDefinition typeDef) {
    var fields =
        typeDef.fields.where((f) => types.containsKey(f.type.token)).toList();

    for (var field in fields) {
      var type = getType(field.type.tokenInfo);
      var skipOnServerFields = type.getSkipOnServerFields();
      var typeBatch = type
          .getDirectiveByName(glSkipOnServer)
          ?.getArgValue(glBatch) as bool?;
      var fieldBacth = field
          .getDirectiveByName(glSkipOnServer)
          ?.getArgValue(glBatch) as bool?;

      // find the field to make as identity
      GLField? identityField = _getIdentityField(type);
      for (var typeField in skipOnServerFields) {
        var targetField = typeField;
        var fieldType = getTypeByName(typeField.type.token);
        if (fieldType != null) {
          var skipOnServer = fieldType.getDirectiveByName(glSkipOnServer);

          if (skipOnServer != null) {
            var mapTo = skipOnServer.getArgValueAsString(glMapTo);
            if (mapTo == null) {
              throw ParseException(
                  "Argument '${glMapTo}' is required on type '${type.token}' for schema mapping generation",
                  info: skipOnServer.tokenInfo);
            }
            targetField = GLField(
                name: typeField.name,
                type: typeField.type.ofNewName(mapTo.toToken()),
                arguments: typeField.arguments,
                directives: typeField.getDirectives());
          }
        }
        var identity = identityField == typeField;
        var batch = identity ? false : fieldBacth ?? typeBatch;
        var schemaMapping = GLSchemaMapping(
          type: type,
          field: targetField,
          batch: batch,
          identity: identity,
        );
        addSchemaMapping(schemaMapping);
      }
      // generate forbidden fields
      type.getSkipOnClientFields().forEach((typeField) {
        addSchemaMapping(
            GLSchemaMapping(type: type, field: typeField, forbid: true));
      });
    }

    typeDef.getSkipOnClientFields().forEach((typeField) {
      addSchemaMapping(GLSchemaMapping(
        type: typeDef,
        field: typeField,
        forbid: true,
      ));
    });
  }

  String serviceMappingName(String type) => "${type}SchemaMappingsService";
  String controllerMappingName(String type) =>
      "${type}SchemaMappingsController";

  void setDirectivesDefaultValues() {
    var values = [...directiveValues];
    for (var value in values) {
      var def = directiveDefinitions[value.token];
      if (def != null) {
        value.setDefualtArguments(def.arguments);
      }
    }
  }

  void proparageAnnotationsOnFields() {
    extensibleTokens.values
        .expand((e) => e.data)
        .whereType<GLTokenWithFields>()
        .forEach(_propagateAnnotations);
  }

  void mergeTokens() {
    List<GLExtensibleToken> tokens = [
      ...scalars.values,
      ...enums.values,
      ...inputs.values,
      ...types.values,
      ...interfaces.values,
      ...unions.values
    ];
    for (var token in tokens) {
      var list = extensibleTokens[token.token];
      if (list != null) {
        list.data.where((e) => e != token).forEach((e) {
          token.merge(e);
        });
      }
    }
  }

  void _propagateAnnotations(GLTokenWithFields tokenWithFields) {
    if (tokenWithFields is! GLDirectivesMixin) {
      return;
    }
    var mixin = tokenWithFields as GLDirectivesMixin;

    var annotations = mixin
        .getDirectives()
        .where((d) =>
            d.getArgValueAsBool(glAnnotation) &&
            d.getArgValueAsBool(glApplyOnFields))
        .toList();
    if (annotations.isEmpty) {
      return;
    }
    for (var field in tokenWithFields.fields) {
      annotations.forEach(field.addDirectiveIfAbsent);
    }
    // remove directives from the super class.
    annotations.map((e) => e.token).forEach(mixin.removeDirectiveByName);
  }

  void convertUnionsToInterfaces() {
    //
    unions.forEach((k, union) {
      var interfaceDef = GLInterfaceDefinition(
        name: union.tokenInfo,
        nameDeclared: false,
        fields: getUnionFields(union),
        directives: [],
        interfaceNames: {},
        fromUnion: true,
        extension: true,
      );
      addInterfaceDefinition(interfaceDef);

      for (var typeName in union.typeNames) {
        var type = getType(typeName);
        type.addInterfaceName(union.tokenInfo);
      }
    });
  }

  fillQueryElementArgumentTypes(
      GLQueryElement element, GLQueryDefinition query) {
    for (var arg in element.arguments) {
      var list = query.arguments.where((a) => a.token == arg.value).toList();
      if (list.isEmpty) {
        throw ParseException(
            "Could not find argument ${arg.value} on query ${query.tokenInfo}",
            info: arg.tokenInfo);
      }
      arg.type = list.first.type;
    }
  }

  fillQueryElementsReturnType() {
    queries.forEach((name, queryDefinition) {
      for (var element in queryDefinition.elements) {
        element.returnType = getTypeFromFieldName(element.token,
            schema.getByQueryType(queryDefinition.type), element.tokenInfo);
        fillQueryElementArgumentTypes(element, queryDefinition);
      }
    });
  }

  List<GLQueryElement> getAllElements() {
    return queries.values.expand((q) => q.elements).toList();
  }

  GLType getFieldType(TokenInfo fieldNameToken, String typeName) {
    var fieldName = fieldNameToken.token;
    var onType = getType(fieldNameToken.ofNewName(typeName));

    var result =
        onType.fields.where((element) => element.name.token == fieldName);
    if (result.isEmpty && fieldName != GLGrammar.typename) {
      throw ParseException(
          "Could not find field '$fieldName' on type '$typeName'",
          info: fieldNameToken);
    } else {
      if (result.isNotEmpty) {
        return result.first.type;
      } else {
        return GLType(getLangType("String").toToken(), false);
      }
    }
  }

  void updateFragmentAllTypesDependencies() {
    fragments.forEach((key, fragment) {
      fragment.block.projections.values
          .where((projection) => projection.block == null)
          .forEach((projection) {
        handleFragmentDepenecy(fragment, projection);
      });
    });
  }

  void handleFragmentDepenecy(
      GLFragmentDefinitionBase fragment, GLProjection projection) {
    if (projection is GLInlineFragmentsProjection) {
      for (var inlineFrag in projection.inlineFragments) {
        inlineFrag.block.projections.forEach((k, proj) {
          if (projection.block == null) {
            handleFragmentDepenecy(fragment, proj);
          }
        });
      }
    } else if (projection.isFragmentReference) {
      var fragmentRef =
          getFragment(projection.targetToken, projection.tokenInfo);

      fragment.addDependecy(fragmentRef);
    } else {
      var type = getType(fragment.onTypeName);
      var field = type.findFieldByName(projection.token, this);
      if (types.containsKey(field.type.token)) {
        fragment.addDependecy(fragments[field.type.token]!);
      }
    }
  }

  GLType getTypeFromFieldName(
      String fieldName, String typeName, TokenInfo fieldToken) {
    var type = getType(fieldToken.ofNewName(typeName));

    var fields = type.fields
        .where((element) => element.name.token == fieldName)
        .toList();
    if (fields.isEmpty) {
      throw ParseException(
          "$typeName does not declare a field with name $fieldName",
          info: type.tokenInfo);
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
      typedFragments[key] =
          GLTypedFragment(fragment, getType(fragment.onTypeName));
    });
  }

  GLFragmentDefinition createAllFieldsFragment(
      GLTypeDefinition typeDefinition) {
    var key = typeDefinition.token;

    var allFieldsKey = allFieldsFragmentName(key);
    if (fragments[allFieldsKey] != null) {
      throw ParseException("Fragment $allFieldsKey is Already defined",
          info: fragments[allFieldsKey]!.tokenInfo);
    }
    if (typeDefinition is GLInterfaceDefinition) {
      var projection = _createProjectionForInterface(typeDefinition);
      var block = GLFragmentBlockDefinition([projection]);
      return GLFragmentDefinition(
          allFieldsKey.toToken(), typeDefinition.tokenInfo, block, []);
    } else {
      return GLFragmentDefinition(
          allFieldsKey.toToken(),
          typeDefinition.tokenInfo,
          GLFragmentBlockDefinition(typeDefinition
              .getSerializableFields(mode)
              .map((field) => GLProjection(
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
    var queryTypeNames =
        GLQueryType.values.map((t) => schema.getByQueryType(t)).toSet();
    allTypes.forEach((key, typeDefinition) {
      if (!queryTypeNames.contains(key) &&
          typeDefinition.getDirectiveByName(glInternal) == null) {
        var frag = createAllFieldsFragment(typeDefinition);
        addFragmentDefinition(frag);
      }
    });
  }

  static String allFieldsFragmentName(String token) {
    return "${allFields}_$token";
  }

  GLFragmentBlockDefinition? createAllFieldBlock(GLField field) {
    if (!typeRequiresProjection(field.type)) {
      return null;
    }
    return GLFragmentBlockDefinition([
      GLProjection(
        fragmentName: allFieldsFragmentName(field.type.inlineType.token),
        token: field.type.inlineType.tokenInfo
            .ofNewName(allFieldsFragmentName(field.type.inlineType.token)),
        alias: null,
        block: null,
        directives: [],
      )
    ]);
  }

  void updateInterfaceReferences() {
    var allTypes = [...interfaces.values, ...types.values];
    allTypes.where((type) => type.interfaceNames.isNotEmpty).forEach((type) {
      var result =
          type.interfaceNames.map((token) => getInterface(token.token, token));
      result.forEach(type.addInterface);
    });
  }

  void updateInterfaceCommonFields() {
    for (var i in tempProjectedInterfaces.values) {
      var commonFields = _getCommonInterfaceFields(i);
      for (var cf in commonFields) {
        i.addField(cf);
      }
    }
  }

  void fillProjectedInterfaces() {
    for (var iface in tempProjectedInterfaces.values) {
      var projections = iface.fields.map((field) => GLProjection(
          fragmentName: null,
          token: field.name,
          alias: null,
          block: null,
          directives: []));
      var newName =
          _generateName(iface.derivedFromType!.token, projections, []);
      var newIface = GLInterfaceDefinition(
        name: iface.tokenInfo.ofNewName(newName.value),
        nameDeclared: newName.declared,
        fields: iface.fields,
        directives: iface.getDirectives(),
        interfaceNames: iface.interfaceNames,
        extension: false,
      );
      iface.implementations.forEach(newIface.addImplementation);
      var added = addToProjectedTypes(newIface) as GLInterfaceDefinition;
      iface.implementations.forEach(added.addImplementation);
      for (var impl in added.implementations) {
        impl.addInterface(added);
      }
    }
  }

  /// need to remove all implementations from interfaces that has been replaced by similar objects
  void cleanProjectedInterfacesImplementations() {
    for (var iface in projectedInterfaces.values) {
      iface.implementations
          .map((e) => e.token)
          .where((token) => !projectedTypes.containsKey(token))
          .toSet()
          .forEach(iface.removeImplementation);
    }
  }

  void addClientTypesToProjectedTypes() {
    for (var type in clientTypes) {
      var t = types[type];
      if (t != null) {
        projectedTypes[type] = t;
      }
    }

    for (var type in clientInterfaces) {
      var result = types[type] ?? interfaces[type];
      if (result != null) {
        if (result is GLInterfaceDefinition) {
          projectedInterfaces[type] = result;
        } else {
          projectedTypes[type] = result;
        }
      }
    }
  }

  List<GLField> _getCommonInterfaceFields(GLInterfaceDefinition def) {
    // search in projected types, types that have implemented this interface
    var types = def.implementations;
    if (types.isEmpty) {
      return [];
    }
    var map = <String, int>{};
    var token = def.derivedFromType!.token;
    final fields = interfaces[token]!.fields;
    var interfaceFieldNames =
        interfaces[token]!.fields.map((f) => f.name.token).toSet();

    types.expand((t) => t.fields).forEach((f) {
      if (map.containsKey(f.name.token)) {
        map[f.name.token] = map[f.name.token]! + 1;
      } else {
        map[f.name.token] = 1;
      }
    });

    var result = <GLField>[];
    map.forEach((fieldName, count) {
      if (count == types.length && interfaceFieldNames.contains(fieldName)) {
        result.addAll(fields.where((f) => f.name.token == fieldName));
      }
    });
    return result;
  }

  void createProjectedTypes() {
    _typeHashIndex.clear();
    _interfaceHashIndex.clear();
    // pre-populate index with static schema types so findSimilarTo covers them
    for (var t in typesWithNoResolvers) {
      _typeHashIndex.putIfAbsent(t.getHash(this), () => []).add(t);
    }
    for (var i in interfaces.values) {
      _interfaceHashIndex.putIfAbsent(i.getHash(this), () => []).add(i);
    }

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
        throw ParseException(
            "Type ${projectedType.tokenInfo.token} has already been defined, please rename it",
            info: projectedType.tokenInfo);
      }
      var def = addToProjectedTypes(projectedType);
      query.updateTypeDefinition(def);
    });
  }

  GLTypeDefinition createProjectedTypeForQuery(GLQueryElement element) {
    var type = element.returnType;
    var block = element.block!;
    var onType = getType(type.inlineType.tokenInfo);
    return createProjectedType(
        type: onType,
        projectionMap: block.projections,
        directives: element.getDirectives());
  }

  GLTypeDefinition addToProjectedTypes(GLTypeDefinition definition,
      {bool similarityCheck = true}) {
    var targetStore = definition is GLInterfaceDefinition
        ? projectedInterfaces
        : projectedTypes;
    if (definition.nameDeclared) {
      var type = targetStore[definition.token];
      if (type == null) {
        if (similarityCheck) {
          var similarDefinitions = findSimilarTo(definition);
          if (similarDefinitions.isNotEmpty) {
            similarDefinitions
                .where((element) => !element.nameDeclared)
                .forEach((e) {
              var currentDef = targetStore[e.token];
              if (currentDef != null) {
                currentDef.interfaceNames.forEach(definition.addInterfaceName);
                if (currentDef is GLInterfaceDefinition &&
                    definition is GLInterfaceDefinition) {
                  currentDef.implementations
                      .forEach(definition.addImplementation);
                }
              }
              targetStore[e.token] = definition;
            });
          }
        }

        targetStore[definition.token] = definition;
        definition.addOriginalToken(definition.token);
        return definition;
      } else {
        if (type.isSimilarTo(definition, this)) {
          type.addOriginalToken(definition.token);
          if (type is GLInterfaceDefinition &&
              definition is GLInterfaceDefinition) {
            definition.implementations.forEach(type.addImplementation);
          }
          return type;
        } else {
          var typeTokenInfo = type
              .getDirectiveByName(glTypeNameDirective)
              ?.getArgumentByName('name')
              ?.tokenInfo;
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
        if (definition is GLInterfaceDefinition &&
            first is GLInterfaceDefinition) {
          definition.implementations.forEach(first.addImplementation);
        }
        targetStore[first.token] = first;
        if (first is GLInterfaceDefinition &&
            definition is GLInterfaceDefinition) {
          definition.implementations.forEach(first.addImplementation);
        }
        return first;
      }
    }

    String key = definition.token;
    targetStore[key] = definition;
    definition.addOriginalToken(key);
    final index = definition is GLInterfaceDefinition ? _interfaceHashIndex : _typeHashIndex;
    index.putIfAbsent(definition.getHash(this), () => []).add(definition);
    return targetStore[key]!;
  }

  List<GLTypeDefinition> findSimilarTo(GLTypeDefinition definition) {
    final index = definition is GLInterfaceDefinition ? _interfaceHashIndex : _typeHashIndex;
    final hash = definition.getHash(this);
    final candidates = index[hash];
    if (candidates == null) return [];
    return candidates.where((e) => e.isSimilarTo(definition, this)).toList();
  }

  String getUniqueName(Iterable<GLProjection> projections) {
    //@Todo check the inline fragment case.
    var keys = projections
        .map((e) => e.token)
        .where((t) => !t.endsWith("*"))
        .where((t) => t != GLGrammar.typename)
        .toSet()
        .toList();
    keys.sort();
    return keys.join("_");
  }

  GeneratedTypeName _generateName(String originalName,
      Iterable<GLProjection> projections, List<GLDirectiveValue> directives) {
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
    var queryDeclarations = types[schema.getByQueryType(GLQueryType.query)];
    if (queryDeclarations != null) {
      generateQueries(queryDeclarations, GLQueryType.query);
    }

    var mutationDeclarations =
        types[schema.getByQueryType(GLQueryType.mutation)];
    if (mutationDeclarations != null) {
      generateQueries(mutationDeclarations, GLQueryType.mutation);
    }

    var subscriptionDeclarations =
        types[schema.getByQueryType(GLQueryType.subscription)];
    if (subscriptionDeclarations != null) {
      generateQueries(subscriptionDeclarations, GLQueryType.subscription);
    }
  }

  void generateQueries(GLTypeDefinition def, GLQueryType queryType) {
    for (var field in def.fields) {
      _generateForField(field, queryType);
    }
  }

  String generateAllFieldFragment(GLType type) {
    // check if type is an interface

    if (interfaces.containsKey(type.token)) {
      var iface = interfaces[type.token]!;
      GLProjection projection = _createProjectionForInterface(iface);

      var block = GLFragmentBlockDefinition([projection]);
      var frag = GLInlineFragmentDefinition(iface.tokenInfo, block, []);
      addFragmentDefinition(frag);
      return frag.token;
    }
    final fragName = "${allFields}_${type.tokenInfo.token}";
    getFragment(fragName, type.tokenInfo);
    return fragName;
  }

  void _generateForField(GLField field, GLQueryType queryType) {
    GLFragmentBlockDefinition? block;
    if (typeRequiresProjection(field.type)) {
      final fragName = generateAllFieldFragment(field.type);
      block = GLFragmentBlockDefinition([
        GLProjection(
            fragmentName: fragName,
            token: fragName.toToken(),
            alias: null,
            block: null,
            directives: [])
      ]);
    }

    var argValues = field.arguments.map((arg) {
      return GLArgumentValue(arg.tokenInfo, "\$${arg.tokenInfo}");
    }).toList();
    const inheritedDirectives = [glCache, glNoCache, glCacheInvalidate];
    var directives = field
        .getDirectives()
        .where((e) => inheritedDirectives.contains(e.token))
        .toList();
    var queryElement = GLQueryElement(
        field.name, directives, block, argValues, defaultAlias?.toToken());
    final def = GLQueryDefinition(
        field.name,
        [],
        field.arguments
            .map((e) => GLArgumentDefinition(
                "\$${e.tokenInfo}".toToken(), e.type, [],
                initialValue: e.initialValue))
            .toList(),
        [queryElement],
        queryType);
    addQueryDefinitionSkipIfExists(def);
  }

  GLProjection _createProjectionForInterface(GLInterfaceDefinition interface) {
    var types = getTypesImplementing(interface);
    var inlineFrags = <GLInlineFragmentDefinition>[];

    types.map((t) {
      var token = t.tokenInfo.ofNewName("${allFields}_${t.token}");
      var inlineDef = GLInlineFragmentDefinition(
          t.tokenInfo,
          GLFragmentBlockDefinition([
            GLProjection(
                fragmentName: token.token,
                token: token,
                alias: null,
                block: null,
                directives: [])
          ]),
          []);
      inlineFrags.add(inlineDef);
      addFragmentDefinition(inlineDef);
    }).toList();

    return GLInlineFragmentsProjection(inlineFragments: inlineFrags);
  }

  List<GLTypeDefinition> getProjectdeTypesImplementing(
      GLInterfaceDefinition def) {
    return projectedTypes.values.where((pt) {
      return pt.getInterfaceNames().contains(def.token);
    }).toList();
  }

  List<GLTypeDefinition> getTypesImplementing(GLInterfaceDefinition def) {
    var result = <GLTypeDefinition>[];
    types.forEach((k, v) {
      if (v.implements(def.token)) {
        result.add(v);
      }
    });
    return result;
  }

  GLTypeDefinition createProjectedType({
    required GLTypeDefinition type,
    required Map<String, GLProjection> projectionMap,
    required List<GLDirectiveValue> directives,
  }) {
    if (type is GLInterfaceDefinition) {
      var implementationTypes = getTypesImplementing(type);
      GLTypeDefinition? result;
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

  GLInterfaceDefinition _createNewInterface(GLInterfaceDefinition original) {
    return GLInterfaceDefinition(
      name: generateUuid().toToken(),
      nameDeclared: false,
      fields: [],
      directives: original.getDirectives(),
      interfaceNames: {},
      derivedFromType: original,
      extension: original.extension,
    );
  }

  GLTypeDefinition _createNewType(GeneratedTypeName name, List<GLField> fields,
      List<GLDirectiveValue> directives, GLTypeDefinition? realType) {
    return GLTypeDefinition(
      name: name.value.toToken(),
      nameDeclared: name.declared,
      fields: fields,
      interfaceNames: {},
      directives: directives,
      derivedFromType: realType,
      extension: false,
    );
  }

  GLTypeDefinition createProjectedTypeOnType({
    required GLTypeDefinition type,
    required Map<String, GLProjection> projectionMap,
    required List<GLDirectiveValue> directives,
    required String onTypeName,
  }) {
    /// type might be an interface, we need to grab the real type from typesm map.
    var realType = type.token == onTypeName ? type : types[onTypeName]!;
    var src = [...realType.fields];

    var result = <GLField>[];
    var projections = _collectProjection(projectionMap, onTypeName);

    for (var field in src) {
      var projection = projections[field.name.token];
      if (projection != null) {
        result.add(_applyProjectionToField(
            field, projection, projection.getDirectives()));
      }
    }
    var name = _generateName(onTypeName, projections.values, directives);
    var newType = _createNewType(name, result, directives, realType);
    for (var iface in realType.interfaces) {
      var newInface = _createNewInterface(iface);
      tempProjectedInterfaces[newInface.token] = newInface;
      newInface.addImplementation(newType);
    }

    return addToProjectedTypes(newType);
  }

  Map<String, GLProjection> _collectProjection(
      Map<String, GLProjection> projections, String onTypeName) {
    var result = <String, GLProjection>{};
    projections.forEach((k, v) {
      if (v.isFragmentReference) {
        var fragment = getFragmentByName(v.fragmentName!)!;
        var r = _collectProjection(fragment.block.projections, onTypeName);
        result.addAll(r);
      } else if (v is GLInlineFragmentsProjection) {
        v.inlineFragments
            .where((inline) => inline.onTypeName.token == onTypeName)
            .forEach((inline) {
          var r = _collectProjection(inline.block.projections, onTypeName);
          result.addAll(r);
        });
      } else {
        result[k] = v;
      }
    });
    return result;
  }

  GLField _applyProjectionToField(GLField field, GLProjection projection,
      [List<GLDirectiveValue> fieldDirectives = const []]) {
    final TokenInfo fieldName = projection.alias ?? field.name;
    var block = projection.block;

    if (block != null) {
      //we should create another type here ...
      var generatedType = createProjectedType(
        type: getType(field.type.tokenInfo),
        projectionMap: block.projections,
        directives: fieldDirectives,
      );
      var fieldInlineType =
          GLType(generatedType.tokenInfo, field.type.nullable);

      return GLField(
        name: fieldName,
        type: _createTypeFrom(field.type, fieldInlineType),
        arguments: field.arguments,
        directives: projection.getDirectives(),
      );
    }

    return GLField(
      name: fieldName,
      type: _createTypeFrom(field.type, field.type),
      arguments: field.arguments,
      directives: projection.getDirectives(),
    );
  }

  GLType _createTypeFrom(GLType orig, GLType inline) {
    if (orig is GLListType) {
      return GLListType(_createTypeFrom(orig.type, inline), orig.nullable);
    }
    return GLType(inline.tokenInfo, orig.inlineType.nullable);
  }

  String getLangType(String typeName) {
    var result = typeMap[typeName];
    if (result == null) {
      throw ParseException("Unknown type $typeName");
    }
    return result;
  }

  static List<String> extractDecorators(
      {required List<GLDirectiveValue> directives,
      required CodeGenerationMode mode}) {
    // find the list
    var decorators = directives
        .where((d) => d.token == glDecorators)
        .where((d) {
          switch (mode) {
            case CodeGenerationMode.client:
              return d
                  .getArguments()
                  .where((arg) => arg.token == glApplyOnClient)
                  .first
                  .value as bool;
            case CodeGenerationMode.server:
              return d
                  .getArguments()
                  .where((arg) => arg.token == glApplyOnServer)
                  .first
                  .value as bool;
          }
        })
        .map((d) {
          return d.getArguments().where((arg) => arg.token == "value").first;
        })
        .map((d) {
          var decoratorValues = (d.value as List)
              .map((e) => e as String)
              .map((str) => str.removeQuotes())
              .toList();
          return decoratorValues;
        })
        .expand((inner) => inner)
        .toList();
    return decorators;
  }

  void generateViews() {
    final queryTypeNames =
        GLQueryType.values.map((t) => schema.getByQueryType(t)).toSet();
    projectedTypes.values
        .where((t) =>
            t is! GLInterfaceDefinition &&
            !queryTypeNames.contains(t.token) &&
            t.getDirectiveByName(glInternal) == null)
        .map((t) => GLTypeView(type: t))
        .forEach((view) {
      views[view.token] = view;
    });
    if (views.isNotEmpty) {
      // add GQFieldViewType enumeration
      addEnumDefinition(GLEnumDefinition(
          extension: false,
          token: "GQFieldViewType".toToken(),
          values: ['listTile', 'reversedListTile', 'labelValueRow']
              .map((e) => e.toToken())
              .map(
                (e) =>
                    GLEnumValue(value: e, documentation: null, directives: []),
              )
              .toList(),
          directives: []));
    }
  }
}

class GeneratedTypeName {
  // the generated name value
  final String value;
  //true if the name has been declared using @glTypeName directive
  final bool declared;

  GeneratedTypeName(this.value, this.declared);
}
