import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/gl_error.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_openapi_document.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_error_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';

const _errorSchemaName = 'RestError';

const _builtInScalars = {
  'ID': GLOpenApiSchema(types: ['string']),
  'String': GLOpenApiSchema(types: ['string']),
  'Int': GLOpenApiSchema(types: ['integer'], format: 'int32'),
  'Float': GLOpenApiSchema(types: ['number']),
  'Boolean': GLOpenApiSchema(types: ['boolean']),
  'Long': GLOpenApiSchema(types: ['integer'], format: 'int64'),
};

const _codecJsonTypes = {
  'String': 'string',
  'Int': 'integer',
  'Double': 'number',
  'Bool': 'boolean',
  'Map': 'object',
  'List': 'array',
};

const _formatByScalarName = {
  'DateTime': 'date-time',
  'Date': 'date',
  'BigDecimal': 'decimal',
  'Decimal': 'decimal',
};

const _locations = {
  RestArgRole.path: GLOpenApiParameterLocation.path,
  RestArgRole.query: GLOpenApiParameterLocation.query,
  RestArgRole.header: GLOpenApiParameterLocation.header,
};

const _sharedErrors = {
  '400': 'Bad request: an argument is missing or malformed',
  '404': 'Not found',
  '405': 'Method not allowed',
  '500': 'Internal server error',
};

extension GLGrammarOpenApiExtension on GLParser {
  GLOpenApiDocument buildOpenApiDocument(OpenApiConfig config) =>
      _OpenApiBuilder(this, config).build();
}

class _OpenApiBuilder {
  final GLParser parser;
  final OpenApiConfig config;
  final Map<String, GLOpenApiSchema> schemas = {};
  final List<String> pending = [];
  final Map<String, Map<String, String>> discriminatorsOfType = {};

  _OpenApiBuilder(this.parser, this.config) {
    for (final discriminator in parser.restDiscriminators.values) {
      for (final entry in discriminator.valueByType.entries) {
        discriminatorsOfType.putIfAbsent(entry.key, () => {})[discriminator.field] = entry.value;
      }
    }
  }

  GLOpenApiDocument build() {
    final operations = [for (final op in parser.restOperations.values) _operation(op)];
    if (operations.isNotEmpty) _drain();
    return GLOpenApiDocument(
      title: config.title,
      version: config.version,
      serverUrl: config.serverUrl,
      operations: operations,
      schemas: operations.isEmpty ? const {} : {...schemas, _errorSchemaName: _errorSchema},
      responses: operations.isEmpty
          ? const {}
          : {
              for (final e in _sharedErrors.entries)
                e.key: GLOpenApiResponse(
                  status: e.key,
                  description: e.value,
                  content: {'application/json': GLOpenApiSchema.reference(_errorSchemaName)},
                ),
            },
    );
  }

  static final _errorSchema = GLOpenApiSchema.object(
    {'message': GLOpenApiSchema.scalar('string')},
    required: const ['message'],
  );

  // ── operations ──────────────────────────────────────────────────────────

  GLOpenApiOperation _operation(GLRestOperation op) {
    final parameters = [for (final arg in op.arguments) ..._parameters(arg)];
    final body = _body(op);
    return GLOpenApiOperation(
      path: op.path,
      method: op.method.name,
      operationId: op.name,
      parameters: parameters,
      body: body,
      responses: _withDeclaredErrors(op, [
        ..._successResponses(op),
        if (parameters.isNotEmpty || body != null) const GLOpenApiResponse(status: '400', ref: '400'),
        if (op.placeholders.isNotEmpty) const GLOpenApiResponse(status: '404', ref: '404'),
        const GLOpenApiResponse(status: '500', ref: '500'),
      ]),
    );
  }

  List<GLOpenApiResponse> _withDeclaredErrors(GLRestOperation op, List<GLOpenApiResponse> responses) {
    final thrown = parser.restThrownErrorsOf(op);
    if (thrown.isEmpty) return responses;
    final byStatus = <String, List<GLErrorDefinition>>{};
    for (final error in thrown) {
      byStatus.putIfAbsent(error.status?.toString() ?? 'default', () => []).add(error);
      schemas.putIfAbsent(error.name, () => _errorSchemaOf(error));
    }
    final declared = {
      for (final entry in byStatus.entries)
        entry.key: GLOpenApiResponse(
          status: entry.key,
          description: entry.value.map((e) => e.name).join(', '),
          content: {
            'application/json': entry.value.length == 1
                ? GLOpenApiSchema.reference(entry.value.single.name)
                : GLOpenApiSchema(oneOf: [for (final e in entry.value) GLOpenApiSchema.reference(e.name)]),
          },
        ),
    };
    return [
      for (final response in responses)
        if (!declared.containsKey(response.status)) response,
      ...declared.values,
    ];
  }

  GLOpenApiSchema _errorSchemaOf(GLErrorDefinition error) {
    final properties = <String, GLOpenApiSchema>{
      for (final field in error.type.fields) field.name.token: _typeSchema(field.type),
      'message': GLOpenApiSchema.scalar('string'),
    };
    final required = [
      for (final field in error.type.fields)
        if (!field.type.nullable) field.name.token,
    ];
    final path = error.restField;
    if (path != null) _putDiscriminator(properties, required, path, error.value);
    return GLOpenApiSchema.object(properties, required: required);
  }

  void _putDiscriminator(Map<String, GLOpenApiSchema> properties, List<String> required, List<String> path, String value) {
    final head = path.first;
    if (!required.contains(head)) required.add(head);
    if (path.length == 1) {
      properties[head] = GLOpenApiSchema.constant(value);
      return;
    }
    final nested = Map<String, GLOpenApiSchema>.from(properties[head]?.properties ?? const {});
    final nestedRequired = List<String>.from(properties[head]?.required ?? const []);
    _putDiscriminator(nested, nestedRequired, path.sublist(1), value);
    properties[head] = GLOpenApiSchema.object(nested, required: nestedRequired);
  }

  List<GLOpenApiParameter> _parameters(GLRestArgument arg) {
    final location = _locations[arg.role];
    if (location == null) return const [];
    final type = arg.argument.type;
    final required = arg.role == RestArgRole.path || _isRequired(type, arg.argument.defaultValue);
    if (arg.encoding == RestEncoding.spread) return _spreadParameters(arg, location, required);
    final schema = _withDefault(_typeSchema(type, nonNull: true), arg.argument.defaultValue?.value);
    final name = arg.wireName!;
    if (arg.encoding == RestEncoding.json) {
      return [
        GLOpenApiParameter(
            name: name, location: location, required: required, schema: schema, contentType: 'application/json'),
      ];
    }
    return [
      GLOpenApiParameter(
        name: name,
        location: location,
        required: required,
        schema: schema,
        style: _styleOf(arg, location),
        explode: _explodeOf(arg, location),
      ),
    ];
  }

  List<GLOpenApiParameter> _spreadParameters(
      GLRestArgument arg, GLOpenApiParameterLocation location, bool argRequired) {
    final input = parser.inputs[arg.argument.type.firstType.token]!;
    return [
      for (final field in input.fields)
        if (arg.spreadFields.containsKey(field.name.token))
          GLOpenApiParameter(
            name: arg.spreadFields[field.name.token]!,
            location: location,
            required: argRequired && _isRequired(field.type, field.initialValue),
            schema: _withDefault(_typeSchema(field.type, nonNull: true), field.initialValue),
            style: _spreadStyle(field, location),
            explode: _spreadStyle(field, location) == null ? null : true,
          ),
    ];
  }

  String? _spreadStyle(GLField field, GLOpenApiParameterLocation location) =>
      location == GLOpenApiParameterLocation.query && field.type.isList ? 'form' : null;

  String? _styleOf(GLRestArgument arg, GLOpenApiParameterLocation location) {
    if (location == GLOpenApiParameterLocation.header) return arg.argument.type.isList ? 'simple' : null;
    if (location == GLOpenApiParameterLocation.path) return null;
    if (parser.inputs.containsKey(arg.argument.type.firstType.token)) return 'deepObject';
    return arg.argument.type.isList ? 'form' : null;
  }

  bool? _explodeOf(GLRestArgument arg, GLOpenApiParameterLocation location) {
    final style = _styleOf(arg, location);
    return style == null || style == 'simple' ? null : true;
  }

  GLOpenApiBody? _body(GLRestOperation op) {
    switch (op.bodyKind) {
      case RestBodyKind.none:
        return null;
      case RestBodyKind.json:
        final arg = op.arguments.firstWhere((a) => a.role == RestArgRole.body);
        return GLOpenApiBody(
          contentType: op.contentType!,
          schema: _typeSchema(arg.argument.type, nonNull: true),
          required: !op.bodyIsOptional,
        );
      case RestBodyKind.raw:
        return GLOpenApiBody(
          contentType: op.contentType ?? 'application/octet-stream',
          schema: GLOpenApiSchema.scalar('string', format: 'binary'),
          required: !op.bodyIsOptional,
        );
      case RestBodyKind.form:
        return GLOpenApiBody(
          contentType: op.contentType!,
          schema: _bodyObject(op.arguments.where((a) => a.role == RestArgRole.field)),
          required: !op.bodyIsOptional,
        );
      case RestBodyKind.multipart:
        return GLOpenApiBody(
          contentType: op.contentType!,
          schema: _bodyObject(op.arguments.where((a) => a.role == RestArgRole.part)),
          required: !op.bodyIsOptional,
        );
    }
  }

  GLOpenApiSchema _bodyObject(Iterable<GLRestArgument> arguments) {
    final properties = <String, GLOpenApiSchema>{};
    final required = <String>[];
    for (final arg in arguments) {
      final type = arg.argument.type;
      final isRequired = _isRequired(type, arg.argument.defaultValue);
      if (arg.encoding == RestEncoding.spread) {
        final input = parser.inputs[type.firstType.token]!;
        for (final field in input.fields) {
          final wire = arg.spreadFields[field.name.token];
          if (wire == null) continue;
          properties[wire] = _withDefault(_typeSchema(field.type, nonNull: true), field.initialValue);
          if (isRequired && _isRequired(field.type, field.initialValue)) required.add(wire);
        }
        continue;
      }
      properties[arg.wireName!] = _withDefault(_typeSchema(type, nonNull: true), arg.argument.defaultValue?.value);
      if (isRequired) required.add(arg.wireName!);
    }
    return GLOpenApiSchema.object(properties, required: required);
  }

  List<GLOpenApiResponse> _successResponses(GLRestOperation op) {
    switch (op.responseKind) {
      case RestResponseKind.none:
        return const [GLOpenApiResponse(status: '204', description: 'No content')];
      case RestResponseKind.text:
        return [
          GLOpenApiResponse(
            status: '200',
            description: 'Success',
            content: {op.accept: GLOpenApiSchema.scalar('string')},
          ),
          if (op.allowsEmptyBody) const GLOpenApiResponse(status: '204', description: 'No content'),
        ];
      case RestResponseKind.binary:
        return [
          GLOpenApiResponse(
            status: '200',
            description: 'Success',
            content: {op.accept: GLOpenApiSchema.scalar('string', format: 'binary')},
          ),
          if (op.allowsEmptyBody) const GLOpenApiResponse(status: '204', description: 'No content'),
        ];
      case RestResponseKind.json:
        return [
          GLOpenApiResponse(
            status: '200',
            description: 'Success',
            content: {op.accept: _jsonResponseSchema(op)},
          ),
          if (op.allowsEmptyBody) const GLOpenApiResponse(status: '204', description: 'No content'),
        ];
    }
  }

  GLOpenApiSchema _jsonResponseSchema(GLRestOperation op) {
    final segments = op.responsePathSegments;
    var schema = _typeSchema(op.field.type, nonNull: segments.isEmpty);
    for (final segment in segments.reversed) {
      schema = GLOpenApiSchema.object({segment: schema}, required: [segment]);
    }
    return schema;
  }

  // ── types ───────────────────────────────────────────────────────────────

  bool _isRequired(GLType type, Object? defaultValue) => !type.nullable && defaultValue == null;

  GLOpenApiSchema _withDefault(GLOpenApiSchema schema, Object? value) =>
      value is String || value is num || value is bool ? schema.withDefault(value) : schema;

  GLOpenApiSchema _typeSchema(GLType type, {bool nonNull = false}) {
    final GLOpenApiSchema inner;
    if (type is GLListType) {
      inner = GLOpenApiSchema.array(_typeSchema(type.inlineType));
    } else {
      inner = _namedSchema(type.token);
    }
    return type.nullable && !nonNull ? inner.orNull() : inner;
  }

  GLOpenApiSchema _namedSchema(String name) {
    if (parser.uploadScalarNames.contains(name)) return GLOpenApiSchema.scalar('string', format: 'binary');
    if (parser.enums.containsKey(name) || parser.inputs.containsKey(name) || _declaredType(name) != null) {
      if (!schemas.containsKey(name) && !pending.contains(name)) pending.add(name);
      return GLOpenApiSchema.reference(name);
    }
    final codec = parser.scalarCodecs[name];
    final jsonType = codec?.jsonType;
    if (jsonType != null) {
      return GLOpenApiSchema.scalar(_codecJsonTypes[jsonType]!, format: _formatByScalarName[name]);
    }
    final builtIn = _builtInScalars[name];
    if (builtIn != null) return builtIn;
    return GLOpenApiSchema(description: "Custom scalar '$name'");
  }

  GLTypeDefinition? _declaredType(String name) =>
      parser.interfaces[name] ?? parser.types[name] ?? parser.projectedInterfaces[name] ?? parser.projectedTypes[name];

  void _drain() {
    while (pending.isNotEmpty) {
      final name = pending.removeLast();
      if (schemas.containsKey(name)) continue;
      schemas[name] = _componentSchema(name);
    }
    final sorted = Map.fromEntries(schemas.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
    schemas
      ..clear()
      ..addAll(sorted);
  }

  GLOpenApiSchema _componentSchema(String name) {
    final enumeration = parser.enums[name];
    if (enumeration != null) {
      return GLOpenApiSchema.enumeration([for (final v in enumeration.values) v.wireName]);
    }
    final input = parser.inputs[name];
    if (input != null) return _objectSchema(input, input.fields);
    final type = _declaredType(name)!;
    if (type is GLInterfaceDefinition) return _interfaceSchema(type);
    return _objectSchema(type, type.getSerializableFields(CodeGenerationMode.server), discriminators: discriminatorsOfType[name]);
  }

  GLOpenApiSchema _objectSchema(GLTokenWithFields owner, List<GLField> fields,
      {Map<String, String>? discriminators}) {
    final properties = <String, GLOpenApiSchema>{};
    final required = <String>[];
    for (final field in fields) {
      var schema = _withDefault(_typeSchema(field.type), field.initialValue);
      final doc = field.documentation;
      if (doc != null && doc.isNotEmpty) schema = schema.withDescription(doc);
      properties[field.name.token] = schema;
      if (!field.type.nullable) required.add(field.name.token);
    }
    for (final entry in (discriminators ?? const <String, String>{}).entries) {
      properties[entry.key] = GLOpenApiSchema.constant(entry.value);
      if (!required.contains(entry.key)) required.add(entry.key);
    }
    return GLOpenApiSchema.object(properties, required: required);
  }

  GLOpenApiSchema _interfaceSchema(GLInterfaceDefinition iface) {
    final discriminator = parser.restDiscriminators[iface.token];
    if (discriminator == null) return _objectSchema(iface, iface.getSerializableFields(CodeGenerationMode.server));
    final members = discriminator.valueByType.keys.toList();
    for (final member in members) {
      _namedSchema(member);
    }
    return GLOpenApiSchema(
      oneOf: [for (final member in members) GLOpenApiSchema.reference(member)],
      discriminator: GLOpenApiDiscriminator(
        propertyName: discriminator.field,
        mapping: {for (final e in discriminator.valueByType.entries) e.value: e.key},
      ),
    );
  }
}
