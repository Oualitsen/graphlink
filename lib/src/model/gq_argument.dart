import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_directives_mixin.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';

///
///  some thing like function(if: Boolean = true, name: String! = "Ahmed" ...)
///

class GQArgumentDefinition extends GQToken with GQDirectivesMixin {
  final GQType type;
  final Object? initialValue;
  GQArgumentDefinition(super.tokenInfo, this.type, List<GQDirectiveValue> directives, {this.initialValue}) {
    directives.forEach(addDirective);
  }

  @override
  String toString() {
    return 'Argument{name: $tokenInfo, type: $type}';
  }

  String get dartArgumentName => tokenInfo.token.substring(1);
}

///
///  some thing like function(if: true, name: "Ahmed" ...)
///

class GQArgumentValue extends GQToken {
  Object? value;
  //this is not know at parse type, it must be set only once the grammer parsing is done.
  late final GQType type;
  GQArgumentValue(super.tokenInfo, this.value);

  @override
  String toString() {
    return 'GraphqlArgumentValue{value: $value name: $tokenInfo}';
  }
}
