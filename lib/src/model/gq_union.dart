import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/utils.dart';

class GQUnionDefinition extends GQToken {
  final List<String> typeNames;
  GQUnionDefinition(String name, this.typeNames) : super(name);

  @override
  String serialize() {
    return "union $token = ${serializeListText(typeNames, withParenthesis: false, join: "|")}";
  }
}
