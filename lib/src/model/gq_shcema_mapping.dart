import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_queries.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/extensions.dart';

class GQSchemaMapping {
  final GQTypeDefinition type;
  final GQField field;
  ///
  /// when true, the generator should generate a @BatchMapping instead of @SchemaMapping (when false)
  ///
  final bool batch;
  ///
  /// when true, a @SchemaMapping should be generated to forbid access to field.
  ///
  final bool forbid;
  final String serviceName;
  final GQQueryType queryType;
  GQSchemaMapping({required this.type, required this.field, required this.serviceName, this.batch = false, this.forbid = false, required this.queryType,});
  String get key => "${type.token.firstLow}${field.name.firstUp}";
}