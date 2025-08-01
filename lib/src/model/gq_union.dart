import 'package:retrofit_graphql/src/model/gq_token.dart';

class GQUnionDefinition extends GQToken {
  final List<String> typeNames;
  GQUnionDefinition(super.name, this.typeNames);

}
