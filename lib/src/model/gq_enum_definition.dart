import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_has_directives.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';

class GQEnumDefinition extends GQToken with GqHasDirectives {
  List<GQEnumValue> values;
  List<GQDirectiveValue> directives;

  GQEnumDefinition({required String token, required this.values, required this.directives}) : super(token) {
    directives.forEach(addDirective);
  }

  @override
  String serialize() {
    throw UnimplementedError();
  }

}

class GQEnumValue {
  final String value;
  final String? comment;

  GQEnumValue({required this.value, required this.comment});
}
