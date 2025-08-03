import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';

class GQUnionDefinition extends GQToken {
  final List<TokenInfo> typeNames;
  GQUnionDefinition(super.name, this.typeNames);

}
