import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_argument.dart';
import 'package:retrofit_graphql/src/model/dart_serializable.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';

class GQField extends DartSerializable {
  final String name;
  final GQType type;
  final Object? initialValue;
  final String? documentation;
  final List<GQArgumentDefinition> arguments;
  final List<GQDirectiveValue> directives;

  bool? _containsSkipOrIncludeDirective;

  GQField({
    required this.name,
    required this.type,
    required this.arguments,
    this.initialValue,
    this.documentation,
    required this.directives,
  });

  @override
  bool operator ==(Object other) {
    if (other is GQField && runtimeType == other.runtimeType) {
      return name == other.name && type == other.type;
    }
    return false;
  }

  @override
  int get hashCode => name.hashCode * type.hashCode;

  @override
  String toString() {
    return 'GraphqlField{name: $name, type: ${type.serialize()}, initialValue: $initialValue, documentation: $documentation, arguments: $arguments}';
  }

  @override
  String toDart(GQGrammar grammar) {
    return "final ${type.toDartType(grammar.typeMap, _hasInculeOrSkipDiretives)} $name;";
  }

  String toDartMethodDeclaration(GQGrammar grammar) {
    return "final ${type.toDartType(grammar.typeMap, _hasInculeOrSkipDiretives)} $name";
  }

  String toDartNoFinal(GQGrammar grammar) {
    return "${type.toDartType(grammar.typeMap, _hasInculeOrSkipDiretives)} $name";
  }

  //check for inclue or skip directives
  bool get _hasInculeOrSkipDiretives =>
      _containsSkipOrIncludeDirective ??= directives
          .where((d) => [GQGrammar.includeDirective, GQGrammar.skipDirective]
              .contains(d.token))
          .isNotEmpty;
}
