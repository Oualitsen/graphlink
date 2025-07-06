import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_has_directives.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';

///
///  some thing like function(if: Boolean = true, name: String! = "Ahmed" ...)
///

class GQArgumentDefinition extends GQToken with GqHasDirectives {
  final GQType type;
  final Object? initialValue;
  GQArgumentDefinition(super.name, this.type, List<GQDirectiveValue> directives, {this.initialValue}) {
    directives.forEach(addDirective);
  }

  @override
  String toString() {
    return 'Argument{name: $token, type: $type}';
  }

  String get dartArgumentName => token.substring(1);

  @override
  String serialize() {
    var r = "$_escappedToken:${type.serialize()}";
    if (initialValue != null) {
      r += "=$initialValue";
    }
    return r;
  }

  String get _escappedToken => token.replaceFirst("\$", "\\\$");
}

///
///  some thing like function(if: true, name: "Ahmed" ...)
///

class GQArgumentValue extends GQToken {
  Object? value;
  //this is not know at parse type, it must be set only once the grammer parsing is done.
  late final GQType type;
  GQArgumentValue(super.name, this.value);

  @override
  String serialize() {
    return "$_escapedToken:$_escapedValue";
  }

  String get _escapedToken => token.replaceFirst("\$", "\\\$");

  String get _escapedValue => "$value".replaceFirst("\$", "\\\$");

  @override
  String toString() {
    return 'GraphqlArgumentValue{value: $value name: $token}';
  }
}
