import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_directives_mixin.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/gq_token_with_fields.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';

class GQInputDefinition extends GQTokenWithFields with GQDirectivesMixin {
  final String declaredName;
  GQInputDefinition(
      {required List<GQDirectiveValue> directives,
      required TokenInfo name,
      required this.declaredName,
      required List<GQField> fields,
      required bool extension})
      : super(name, extension, fields) {
    directives.forEach(addDirective);
  }

  @override
  String toString() {
    return 'InputType{fields: $fields, name: $tokenInfo}';
  }

  @override
  void merge<T extends GQExtensibleToken>(T other) {
    if (other is GQInputDefinition) {
      other.getDirectives().forEach(addDirective);
      other.fields.forEach(addOrMergeField);
    }
  }
}
