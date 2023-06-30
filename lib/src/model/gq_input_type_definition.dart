import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/dart_serializable.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/utils.dart';

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
  String toDart(GQGrammar grammar) {
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
