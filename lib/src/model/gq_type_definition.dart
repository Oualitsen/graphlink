import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/dart_serializable.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/utils.dart';

class GQTypeDefinition extends GQTokenWithFields implements DartSerializable {
  final Set<String> interfaceNames;
  final List<GQDirectiveValue> directives;
  final bool nameDeclared;

  String? _hash;

  GQTypeDefinition({
    required String name,
    required this.nameDeclared,
    required List<GQField> fields,
    required this.interfaceNames,
    required this.directives,
  }) : super(name, fields) {
    fields.sort((f1, f2) => f1.name.compareTo(f2.name));
  }

  ///
  ///check is the two definitions will produce the same object structure
  ///
  bool isSimilarTo(GQTypeDefinition other, GQGrammar g) {
    return getHash(g) == other.getHash(g);
  }

  String getHash(GQGrammar grammar) {
    _hash ??= serializeFields(grammar);
    return _hash!;
  }

  @override
  String toString() {
    return 'GraphqlType{name: $token, fields: $fields, interfaceNames: $interfaceNames}';
  }

  @override
  String toDart(GQGrammar grammar) {
    return """
      @JsonSerializable()
      class $token {
          ${serializeListText(fields.map((e) => e.toDart(grammar)).toList(), join: "\n\r          ", withParenthesis: false)}
          
          $token(${serializeContructorArgs()});
          
          factory $token.fromJson(Map<String, dynamic> json) => _\$${token}FromJson(json);
          
          Map<String, dynamic> toJson() => _\$${token}ToJson(this);
      }
    """;
  }

  String serializeFields(GQGrammar grammar) {
    return serializeListText(
        fields.map((e) => e.toDartNoFinal(grammar)).toList(),
        join: " ",
        withParenthesis: false);
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
      nameDeclared: nameDeclared,
      fields: fields.toList(),
      interfaceNames: interfaceNames,
      directives: [],
    );
  }
}
