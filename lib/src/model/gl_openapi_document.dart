class GLOpenApiDiscriminator {
  final String propertyName;
  final Map<String, String> mapping;

  const GLOpenApiDiscriminator({required this.propertyName, required this.mapping});
}

class GLOpenApiSchema {
  static const nullType = 'null';

  final List<String> types;
  final String? format;
  final String? description;
  final String? ref;
  final List<Object?>? enumValues;
  final bool hasConst;
  final Object? constValue;
  final bool hasDefault;
  final Object? defaultValue;
  final GLOpenApiSchema? items;
  final Map<String, GLOpenApiSchema> properties;
  final List<String> required;
  final List<GLOpenApiSchema> oneOf;
  final GLOpenApiDiscriminator? discriminator;

  const GLOpenApiSchema({
    this.types = const [],
    this.format,
    this.description,
    this.ref,
    this.enumValues,
    this.hasConst = false,
    this.constValue,
    this.hasDefault = false,
    this.defaultValue,
    this.items,
    this.properties = const {},
    this.required = const [],
    this.oneOf = const [],
    this.discriminator,
  });

  static const any = GLOpenApiSchema();

  factory GLOpenApiSchema.scalar(String type, {String? format, String? description}) =>
      GLOpenApiSchema(types: [type], format: format, description: description);

  factory GLOpenApiSchema.reference(String name) => GLOpenApiSchema(ref: name);

  factory GLOpenApiSchema.array(GLOpenApiSchema items) => GLOpenApiSchema(types: const ['array'], items: items);

  factory GLOpenApiSchema.object(Map<String, GLOpenApiSchema> properties, {List<String> required = const []}) =>
      GLOpenApiSchema(types: const ['object'], properties: properties, required: required);

  factory GLOpenApiSchema.enumeration(List<String> values) => GLOpenApiSchema(types: const ['string'], enumValues: values);

  factory GLOpenApiSchema.constant(String value) =>
      GLOpenApiSchema(types: const ['string'], hasConst: true, constValue: value);

  bool get isAny =>
      types.isEmpty && ref == null && oneOf.isEmpty && enumValues == null && !hasConst && properties.isEmpty && items == null;

  bool get allowsNull => types.contains(nullType) || oneOf.any((s) => s.types.contains(nullType) && s.types.length == 1);

  GLOpenApiSchema orNull() {
    if (allowsNull || isAny) return this;
    if (types.isNotEmpty && ref == null && oneOf.isEmpty) {
      return _copy(types: [...types, nullType], enumValues: enumValues == null ? null : [...enumValues!, null]);
    }
    return GLOpenApiSchema(oneOf: [this, GLOpenApiSchema.scalar(nullType)]);
  }

  GLOpenApiSchema withDefault(Object? value) => _copy(hasDefault: true, defaultValue: value);

  GLOpenApiSchema withDescription(String text) => _copy(description: text);

  GLOpenApiSchema withDiscriminator(GLOpenApiDiscriminator value) => _copy(discriminator: value);

  GLOpenApiSchema withProperties(Map<String, GLOpenApiSchema> newProperties, List<String> newRequired) =>
      _copy(properties: newProperties, required: newRequired);

  GLOpenApiSchema _copy({
    List<String>? types,
    String? description,
    List<Object?>? enumValues,
    bool? hasDefault,
    Object? defaultValue,
    Map<String, GLOpenApiSchema>? properties,
    List<String>? required,
    GLOpenApiDiscriminator? discriminator,
  }) =>
      GLOpenApiSchema(
        types: types ?? this.types,
        format: format,
        description: description ?? this.description,
        ref: ref,
        enumValues: enumValues ?? this.enumValues,
        hasConst: hasConst,
        constValue: constValue,
        hasDefault: hasDefault ?? this.hasDefault,
        defaultValue: defaultValue ?? this.defaultValue,
        items: items,
        properties: properties ?? this.properties,
        required: required ?? this.required,
        oneOf: oneOf,
        discriminator: discriminator ?? this.discriminator,
      );
}

enum GLOpenApiParameterLocation { path, query, header }

class GLOpenApiParameter {
  final String name;
  final GLOpenApiParameterLocation location;
  final bool required;
  final GLOpenApiSchema schema;

  /// When set, the value travels as JSON text and the parameter carries `content` instead of `schema`.
  final String? contentType;
  final String? style;
  final bool? explode;

  const GLOpenApiParameter({
    required this.name,
    required this.location,
    required this.required,
    required this.schema,
    this.contentType,
    this.style,
    this.explode,
  });
}

class GLOpenApiBody {
  final String contentType;
  final GLOpenApiSchema schema;
  final bool required;

  const GLOpenApiBody({required this.contentType, required this.schema, required this.required});
}

class GLOpenApiResponse {
  final String status;
  final String description;

  /// Media type to schema; empty for a response without content.
  final Map<String, GLOpenApiSchema> content;

  /// Name of a shared `components.responses` entry; the other fields are then unused.
  final String? ref;

  const GLOpenApiResponse({required this.status, this.description = '', this.content = const {}, this.ref});
}

class GLOpenApiOperation {
  final String path;
  final String method;
  final String operationId;
  final List<GLOpenApiParameter> parameters;
  final GLOpenApiBody? body;
  final List<GLOpenApiResponse> responses;

  const GLOpenApiOperation({
    required this.path,
    required this.method,
    required this.operationId,
    required this.parameters,
    required this.body,
    required this.responses,
  });
}

class GLOpenApiDocument {
  final String title;
  final String version;
  final String serverUrl;
  final List<GLOpenApiOperation> operations;
  final Map<String, GLOpenApiSchema> schemas;
  final Map<String, GLOpenApiResponse> responses;

  const GLOpenApiDocument({
    required this.title,
    required this.version,
    required this.serverUrl,
    required this.operations,
    required this.schemas,
    required this.responses,
  });

  bool get isEmpty => operations.isEmpty;
}
