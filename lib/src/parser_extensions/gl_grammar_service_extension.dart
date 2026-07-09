import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_controller.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_schema_mapping.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';

extension GLGrammarServiceExtension on GLParser {
  void generateServicesAndControllers() {
    for (var type in GLQueryType.values) {
      _doGenerateServices(
          types[schema.getByQueryType(type)]?.fields ?? [], type);
    }
    for (var s in services.values) {
      var ctrl = GLController.ofService(s, this);
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
          interfaceNames: {},
          parser: this);
      service.addField(field);
      service.setFieldType(field.name.token, type);

      var validate = field.getDirectiveByName(glValidate);
      if (validate != null) {
        var validationField = GLField(
            name: field.name
                .ofNewName(GLService.getValidationMethodName(field.name.token)),
            type: GLVoidType(),
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
      final base = typeRequiresProjection(field.type)
          ? field.type.token
          : field.name.token;
      serviceName = "${_sanitizeClassNameBase(base)}$suffix";
    }
    if (suffix.isNotEmpty && !serviceName.endsWith(suffix)) {
      serviceName += suffix;
    }
    return serviceName;
  }

  /// Sanitizes a synthetic service/controller class-name base derived from a
  /// GraphQL field or type token. Unlike wire type names these names have no
  /// JSON/wire coupling, so leading-underscore noise is dropped and the result
  /// PascalCased into an idiomatic class identifier (`_status` -> `Status`, so
  /// the service is `StatusService`, never `_statusService`).
  String _sanitizeClassNameBase(String token) {
    final stripped = token.replaceFirst(RegExp(r'^_+'), '');
    return (stripped.isEmpty ? token : stripped).firstUp;
  }

  /// Returns true when [a] and [b] have the same structural type:
  /// same base token, same nullability, and — for lists — matching element types.
  bool _typesMatch(GLType a, GLType b) {
    if (a.isList != b.isList) return false;
    if (a.nullable != b.nullable) return false;
    if (a.token != b.token) return false;
    if (a.isList) return _typesMatch(a.inlineType, b.inlineType);
    return true;
  }

  /// Fields of [type] that need a real @SchemaMapping (with service delegation).
  ///
  /// When [type] has `@glSkipOnServer(mapTo: "ServerType")` and `ServerType` is
  /// in the grammar, auto-detects which fields are absent from `ServerType`.
  /// Fields explicitly annotated with `@glSkipOnServer` at the field level are
  /// always included regardless of whether they match (backward-compat override).
  /// Falls back to the explicit-annotation list when the mapTo type is external.
  List<GLField> _getFieldsNeedingSchemaMappings(GLTypeDefinition type) {
    final mapToName =
        type.getDirectiveByName(glSkipOnServer)?.getArgValueAsString(glMapTo);
    if (mapToName != null) {
      final serverType = getTypeByName(mapToName);
      if (serverType != null) {
        return type.fields
            .where((f) => f.getDirectiveByName(glSkipOnClient) == null)
            .where((f) =>
                f.getDirectiveByName(glSkipOnServer) != null ||
                !serverType.fields.any((sf) =>
                    sf.name.token == f.name.token &&
                    _typesMatch(sf.type, f.type)))
            .toList();
      }
    }
    return type.getSkipOnServerFields();
  }

  /// Fields of [type] that exist verbatim on the mapTo server type
  /// (same name + structural type, no explicit @glSkipOnServer override).
  /// The controller will forward these directly to the server type's getter.
  List<GLField> _getForwardedFields(GLTypeDefinition type) {
    final mapToName =
        type.getDirectiveByName(glSkipOnServer)?.getArgValueAsString(glMapTo);
    if (mapToName != null) {
      final serverType = getTypeByName(mapToName);
      if (serverType != null) {
        return type.fields
            .where((f) => f.getDirectiveByName(glSkipOnClient) == null)
            .where((f) => serverType.getFieldByName(f.name.token) != null && _typesMatch(f.type, serverType.getFieldByName(f.name.token)!.type))
            .toList();
      }
    }
    return [];
  }

  GLField? _getIdentityField(GLTypeDefinition type, List<GLField> fieldsNeedingMapping) {
    var mapsTo =
        type.getDirectiveByName(glSkipOnServer)?.getArgValueAsString(glMapTo);
    if (mapsTo != null) {
      var list = fieldsNeedingMapping
          .where((e) => e.type.token == mapsTo && e.type.isNotList)
          .toList();
      if (list.length == 1) {
        return list.first;
      }
    }
    return null;
  }

  /// The service-facing field for [mapping]: a synthetic [GLField] named
  /// after [GLSchemaMapping.key], carrying the mapping's already-resolved
  /// return type (batch mappings wrapped as `GLMapType(keyType, valueType)`)
  /// and its `value` argument. Lets the service interface be serialized
  /// through the standard field-based serializer path instead of a bespoke
  /// per-mapping method builder.
  GLField _mappingServiceField(GLSchemaMapping mapping) {
    GLType returnType = mapping.field.type;
    if (mapping.isBatch) {
      final keyType = GLType(mapping.getMappedToType(this).tokenInfo, false);
      returnType = GLMapType(keyType, mapping.field.type, false);
    }
    
    return GLField(
      name: mapping.key.toToken(),
      type: returnType,
      arguments: mapping.field.arguments.map((arg) => GLArgumentDefinition(arg.tokenInfo, arg.type, [])..codeName = arg.codeName).toList(),
      directives: const [],
    );
  }

  void generateSchemaMappings() {
    types.values.forEach(genSchemaMappings);
    // generate Services and controllers for mappings only
    generateSchemaMappingServices();
  }

  void generateSchemaMappingServices() {
    for (var type in types.values) {
      var controllerMappings = getAllMappingsByType(type.token);
      if (controllerMappings.isEmpty) continue;

      var serviceName = serviceMappingName(type.token);
      var serviceMappings = getServiceMappingByType(type.token);

      // Only create the service interface when there are methods that require
      // service delegation (forwarded and forbidden mappings need no service method).
      if (serviceMappings.isNotEmpty) {
        var service = services[serviceName] ??
            GLService(
                name: serviceName.toToken(),
                nameDeclared: false,
                fields: [],
                directives: [],
                interfaceNames: {},
                parser: this);
        serviceMappings.forEach(service.addMapping);
        for (var m in serviceMappings) {
          service.addField(_mappingServiceField(m));
        }
        services[serviceName] = service;
      }

      var ctrlName = controllerMappingName(type.token);
      var ctrl = controllers[ctrlName] ??
          GLController(
            serviceName: serviceName,
            name: ctrlName.toToken(),
            nameDeclared: false,
            fields: [],
            interfaceNames: {},
            directives: [],
            parser: this,
          );
      controllerMappings.forEach(ctrl.addMapping);
      controllers[ctrlName] = ctrl;
    }
  }

  void genSchemaMappings(GLTypeDefinition typeDef) {
    var fields =
        typeDef.fields.where((f) => types.containsKey(f.type.token)).toList();

    for (var field in fields) {
      var type = getType(field.type.tokenInfo);
      var skipOnServerFields = _getFieldsNeedingSchemaMappings(type);
      var typeBatch = type
          .getDirectiveByName(glSkipOnServer)
          ?.getArgValue(glBatch) as bool?;
      var fieldBacth = field
          .getDirectiveByName(glSkipOnServer)
          ?.getArgValue(glBatch) as bool?;

      // Fields that exist verbatim on the server type → forwarded getter mappings
      for (var forwardedField in _getForwardedFields(type)) {
        addSchemaMapping(GLSchemaMapping(
          type: type,
          field: forwardedField,
          forwarded: true,
        ));
      }

      // find the field to make as identity
      GLField? identityField = _getIdentityField(type, skipOnServerFields);
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
        var typeFieldBatch = typeField
            .getDirectiveByName(glSkipOnServer)
            ?.getArgValue(glBatch) as bool?;
        var identity = identityField == typeField;
        var batch = identity ? false : typeFieldBatch ?? fieldBacth ?? typeBatch;
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
}
