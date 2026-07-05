import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_controller.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_schema_mapping.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

class GLService extends GLInterfaceDefinition {
  final GLParser parser;
  final Map<String, GLQueryType> _fieldType = {};
  final Map<String, GLSchemaMapping> _mappings = {};

  GLService(
      {required super.name,
      required super.nameDeclared,
      required super.fields,
      required super.directives,
      required super.interfaceNames,
      required this.parser})
      : super(extension: false);

  @override
  void addField(GLField field) {
    if(this is GLController) {
      return super.addField(field);
    }
    super.addField(_applyReturnsProjection(field));
  }

  /// Rewrites [field]'s type to its server projection name (e.g. `User` ->
  /// `GLUserProjection`) when it carries `@glReturnsProjection`. Returns
  /// [field] unchanged otherwise — including when [field] was already
  /// projected by a prior call, since the projected name (e.g.
  /// `GLUserProjection`) never resolves back to a real registered
  /// type/interface, so a repeated call is a no-op rather than
  /// double-wrapping the name.
  GLField _applyReturnsProjection(GLField field) {
    if (!field.hasDirective(glReturnsProjection)) {
      return field;
    }
    final type = parser.types[field.type.token] ?? parser.interfaces[field.type.token];
    if (type == null) {
      return field;
    }
    return field.ofType(field.type.ofNewName(
        GLTypeDefinition.getServerProjectionName(type.mappedToType?.token ?? type.token).toToken()));
  }

  void setFieldType(String fieldName, GLQueryType type) {
    _fieldType[fieldName] = type;
  }

  GLQueryType? getTypeByFieldName(String fieldName) {
    return _fieldType[fieldName];
  }

  void addMapping(GLSchemaMapping mapping) {
    var m = _mappings[mapping.key];
    if (m == null || m.batch == null || (m.batch == false && m.batch == true)) {
      mapping.field = _applyReturnsProjection(mapping.field);
      _mappings[mapping.key] = mapping;
    }
  }

  List<GLSchemaMapping> get mappings => _mappings.values.toList();
  List<GLSchemaMapping> get serviceMapping =>
      _mappings.values.where((e) => !e.forbid && !e.identity).toList();
  

  static String getValidationMethodName(String methodName) {
    return '${glValidateMethodPrefix}${methodName.firstUp}';
  }

  bool isSubscription(GLField field) =>
      getTypeByFieldName(field.name.token) == GLQueryType.subscription;
}
