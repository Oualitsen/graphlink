import 'package:retrofit_graphql/graphql_parser/gq_grammar.dart';
import 'package:retrofit_graphql/graphql_parser/model/gq_argument.dart';
import 'package:retrofit_graphql/graphql_parser/model/dart_serializable.dart';
import 'package:retrofit_graphql/graphql_parser/model/gq_directive.dart';
import 'package:retrofit_graphql/graphql_parser/model/gq_type.dart';

class GQField extends DartSerializable {
  final String name;
  final GQType type;
  final Object? initialValue;
  final String? documentation;
  final List<GQArgumentDefinition> arguments;
  final List<GQDirectiveValue>? directives;

  GQField({
    required this.name,
    required this.type,
    required this.arguments,
    this.initialValue,
    this.documentation,
    this.directives,
  });

  @override
  String toString() {
    return 'GraphqlField{name: $name, type: ${type.serialize()}, initialValue: $initialValue, documentation: $documentation, arguments: $arguments}';
  }

  @override
  String toDart(GQGrammar grammar) {
    return "final ${type.toDartType(grammar.typeMap)} $name;";
  }
}
