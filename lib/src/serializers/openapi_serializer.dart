import 'dart:convert';

import 'package:graphlink/src/model/gl_openapi_document.dart';

const openApiVersion = '3.1.0';
const _schemaPrefix = '#/components/schemas/';
const _responsePrefix = '#/components/responses/';

class OpenApiSerializer {
  const OpenApiSerializer();

  String serialize(GLOpenApiDocument document) =>
      '${const JsonEncoder.withIndent('  ').convert(toMap(document))}\n';

  Map<String, Object?> toMap(GLOpenApiDocument document) => {
        'openapi': openApiVersion,
        'info': {'title': document.title, 'version': document.version},
        'servers': [
          {'url': document.serverUrl},
        ],
        'paths': _paths(document.operations),
        'components': {
          'schemas': {for (final e in document.schemas.entries) e.key: _schema(e.value)},
          'responses': {for (final e in document.responses.entries) e.key: _response(e.value)},
        },
      };

  Map<String, Object?> _paths(List<GLOpenApiOperation> operations) {
    final paths = <String, Map<String, Object?>>{};
    for (final op in operations) {
      paths.putIfAbsent(op.path, () => {})[op.method] = _operation(op);
    }
    return paths;
  }

  Map<String, Object?> _operation(GLOpenApiOperation op) => {
        'operationId': op.operationId,
        if (op.parameters.isNotEmpty) 'parameters': [for (final p in op.parameters) _parameter(p)],
        if (op.body != null)
          'requestBody': {
            'required': op.body!.required,
            'content': {
              op.body!.contentType: {'schema': _schema(op.body!.schema)},
            },
          },
        'responses': {for (final r in op.responses) r.status: _response(r)},
      };

  Map<String, Object?> _parameter(GLOpenApiParameter p) => {
        'name': p.name,
        'in': p.location.name,
        'required': p.required,
        if (p.contentType == null) 'schema': _schema(p.schema),
        if (p.contentType != null)
          'content': {
            p.contentType!: {'schema': _schema(p.schema)},
          },
        if (p.style != null) 'style': p.style,
        if (p.explode != null) 'explode': p.explode,
      };

  Map<String, Object?> _response(GLOpenApiResponse r) {
    if (r.ref != null) return {r'$ref': '$_responsePrefix${r.ref}'};
    return {
      'description': r.description,
      if (r.content.isNotEmpty)
        'content': {
          for (final e in r.content.entries) e.key: {'schema': _schema(e.value)},
        },
    };
  }

  Map<String, Object?> _schema(GLOpenApiSchema s) {
    if (s.ref != null) return {r'$ref': '$_schemaPrefix${s.ref}'};
    return {
      if (s.types.length == 1) 'type': s.types.single,
      if (s.types.length > 1) 'type': s.types,
      if (s.format != null) 'format': s.format,
      if (s.description != null) 'description': s.description,
      if (s.enumValues != null) 'enum': s.enumValues,
      if (s.hasConst) 'const': s.constValue,
      if (s.hasDefault) 'default': s.defaultValue,
      if (s.items != null) 'items': _schema(s.items!),
      if (s.properties.isNotEmpty) 'properties': {for (final e in s.properties.entries) e.key: _schema(e.value)},
      if (s.required.isNotEmpty) 'required': s.required,
      if (s.oneOf.isNotEmpty) 'oneOf': [for (final o in s.oneOf) _schema(o)],
      if (s.discriminator != null)
        'discriminator': {
          'propertyName': s.discriminator!.propertyName,
          'mapping': {for (final e in s.discriminator!.mapping.entries) e.key: '$_schemaPrefix${e.value}'},
        },
    };
  }
}
