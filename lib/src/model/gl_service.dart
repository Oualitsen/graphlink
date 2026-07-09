import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_schema_mapping.dart';
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
    _checkReturnTypeIsGeneratable(field);
    super.addField(field);
  }

  /// A field returning a type/interface that is itself `@glSkipOnServer` with
  /// no (resolvable) `mapTo` has no server-side class to return — the type
  /// is excluded from codegen entirely (see `getSerializableTypes()`), so
  /// referencing it here would emit a dangling reference to a class that is
  /// never generated.
  void _checkReturnTypeIsGeneratable(GLField field) {
    final type = parser.types[field.type.token] ?? parser.interfaces[field.type.token];
    if (type == null) return;
    if (type.getDirectiveByName(glSkipOnServer) != null && type.mappedToType == null) {
      throw ParseException(
          "Field '${field.name.token}' returns '${field.type.token}' which is marked "
          "$glSkipOnServer with no (resolvable) $glMapTo — the server has no type to generate for it",
          info: field.name);
    }
  }

  void setFieldType(String fieldName, GLQueryType type) {
    _fieldType[fieldName] = type;
  }

  GLQueryType? getTypeByFieldName(String fieldName) {
    return _fieldType[fieldName];
  }

  void addMapping(GLSchemaMapping mapping) {
    _checkReturnTypeIsGeneratable(mapping.field);
    var m = _mappings[mapping.key];
    if (m == null || m.batch == null || (m.batch == false && m.batch == true)) {
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
