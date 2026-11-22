import 'package:graphlink/src/model/gl_type_definition.dart';

class GLErrorDefinition {
  static const defaultField = ['extensions', 'code'];
  static const defaultRestField = ['code'];

  final GLTypeDefinition type;
  final List<String> field;
  final String value;
  final int? status;
  final bool explicitField;
  final bool explicitValue;

  GLErrorDefinition({
    required this.type,
    required this.field,
    required this.value,
    this.status,
    this.explicitField = false,
    this.explicitValue = false,
  });

  String get name => type.token;

  /// A REST error that sets a status and no discriminator is chosen by its status alone.
  bool get matchesStatusOnly => status != null && !explicitField && !explicitValue;

  /// The body path a REST response is compared on, or null when the status alone decides.
  List<String>? get restField => matchesStatusOnly ? null : (explicitField ? field : defaultRestField);
}
