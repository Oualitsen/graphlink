import 'package:parser/graphql_parser/gq_grammar.dart';
import 'package:parser/graphql_parser/model/dart_serializable.dart';
import 'package:parser/graphql_parser/model/gq_directive.dart';
import 'package:parser/graphql_parser/model/gq_field.dart';
import 'package:parser/graphql_parser/model/gq_token.dart';
import 'package:parser/graphql_parser/utils.dart';

class GQTypeDefinition extends GQTokenWithFields implements DartSerializable {
  final Set<String> interfaceNames;
  final List<GQDirectiveValue> directives;

  GQTypeDefinition({
    required String name,
    required List<GQField> fields,
    required this.interfaceNames,
    required this.directives,
  }) : super(name, fields);

  @override
  String toString() {
    return 'GraphqlType{name: $token, fields: $fields, interfaceNames: $interfaceNames}';
  }

  @override
  String toDart(GraphQlGrammar grammar) {
    return """@JsonSerializable()
      class $token {
          ${serializeListText(fields.map((e) => e.toDart(grammar)).toList(), join: "\n\r          ", withParenthesis: false)}
          
          $token(${serializeContructorArgs()});
          
          factory $token.fromJson(Map<String, dynamic> json) => _\$${token}FromJson(json);
          
          Map<String, dynamic> toJson() => _\$${token}ToJson(this);
      }
    """;
  }

  String serializeContructorArgs() {
    if (fields.isEmpty) {
      return "";
    }
    return "{${fields.map((e) => e.name).map((e) => "required this.$e").join(", ")}}";
  }

  @override
  String serialize() {
    throw UnimplementedError();
  }

  GQTypeDefinition clone(String newName) {
    return GQTypeDefinition(
      name: newName,
      fields: fields.toList(),
      interfaceNames: interfaceNames,
      directives: [],
    );
  }
}
