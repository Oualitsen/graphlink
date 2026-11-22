import 'package:graphlink/src/model/gl_type_definition.dart';

class GLErrorDefinition {
  static const defaultField = ['extensions', 'code'];

  final GLTypeDefinition type;
  final List<String> field;
  final String value;
  final int? status;

  GLErrorDefinition({required this.type, required this.field, required this.value, this.status});

  String get name => type.token;
}
