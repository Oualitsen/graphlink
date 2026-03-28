import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/token_info.dart';

class GLInputDefinition extends GLTokenWithFields with GLDirectivesMixin {
  final String declaredName;
  GLInputDefinition(
      {required List<GLDirectiveValue> directives,
      required TokenInfo name,
      required this.declaredName,
      required List<GLField> fields,
      required bool extension,
      String? documentation})
      : super(name, extension, fields, documentation: documentation) {
    directives.forEach(addDirective);
  }

  @override
  String toString() {
    return 'InputType{fields: $fields, name: $tokenInfo}';
  }

  @override
  void merge<T extends GLExtensibleToken>(T other) {
    if (other is GLInputDefinition) {
      other.getDirectives().forEach(addDirective);
      other.fields.forEach(addOrMergeField);
    }
  }
}
