import 'package:retrofit_graphql/graphql_parser/gq_grammar.dart';
import 'package:retrofit_graphql/graphql_parser/model/dart_serializable.dart';
import 'package:retrofit_graphql/graphql_parser/model/gq_directive.dart';
import 'package:retrofit_graphql/graphql_parser/model/gq_token.dart';

class GQEnumDefinition extends GQToken implements DartSerializable {
  List<GQEnumValue> values;
  List<GQDirectiveValue> list;

  GQEnumDefinition(
      {required String token, required this.values, required this.list})
      : super(token);

  @override
  String serialize() {
    throw UnimplementedError();
  }

  List<GQDirectiveValue> get directives => list;
  @override
  String toDart(GQGrammar grammar) {
    return """
   
      enum $token {
   ${values.map((e) => e.value).toList().join(", ")}
      }
""";
  }
}

class GQEnumValue {
  final String value;
  final String? comment;

  GQEnumValue({required this.value, required this.comment});
}
