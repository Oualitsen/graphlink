import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/extensions.dart';

class GLSchemaMapping {
  final GLTypeDefinition type;
  final GLField field;

  ///
  /// when true, the generator should generate a @BatchMapping instead of @SchemaMapping (when false)
  ///
  final bool? batch;

  bool get isBatch => batch ?? true;

  ///
  /// when true, a @SchemaMapping should be generated to forbid access to field.
  ///
  final bool forbid;

  ///
  /// if true, no need to implement Type field(Type t) or Map<Type, Type> field(List<Type>)
  ///
  final bool identity;
  GLSchemaMapping({
    required this.type,
    required this.field,
    this.batch,
    this.forbid = false,
    this.identity = false,
  });
  String get key => "${type.token.firstLow}${field.name.token.firstUp}";
}
