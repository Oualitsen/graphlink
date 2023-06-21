import 'package:parser/graphql_parser/gq_grammar.dart';
import 'package:parser/graphql_parser/model/dart_serializable.dart';
import 'package:parser/graphql_parser/model/gq_directive.dart';
import 'package:parser/graphql_parser/model/gq_field.dart';
import 'package:parser/graphql_parser/model/gq_token.dart';
import 'package:parser/graphql_parser/utils.dart';

class GQInputDefinition extends GQTokenWithFields implements DartSerializable {
  GQInputDefinition({required String name, required List<GQField> fields})
      : super(name, fields);

  @override
  String toString() {
    return 'InputType{fields: $fields, name: $token}';
  }

  @override
  String serialize() {
    return """
      input $token {
      
      }
    """;
  }

  @override
  String toDart(GraphQlGrammar grammar) {
    return """
    @JsonSerializable()
      class $token {
          ${serializeListText(fields.map((e) => e.toDart(grammar)).toList(), join: "\n\r          ", withParenthesis: false)}
          
          $token({${fields.map((e) => e.name).map((e) => "required this.$e").join(", ")}});
          
          factory $token.fromJson(Map<String, dynamic> json) => _\$${token}FromJson(json);
          
          Map<String, dynamic> toJson() => _\$${token}ToJson(this);
      }
""";
  }
}
