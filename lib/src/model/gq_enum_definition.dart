import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';

class GQEnumDefinition extends GQToken {
  List<GQEnumValue> values;
  List<GQDirectiveValue> list;

  GQEnumDefinition({required String token, required this.values, required this.list}) : super(token);

  @override
  String serialize() {
    throw UnimplementedError();
  }

  List<GQDirectiveValue> get directives => list;
}

class GQEnumValue {
  final String value;
  final String? comment;

  GQEnumValue({required this.value, required this.comment});
}
