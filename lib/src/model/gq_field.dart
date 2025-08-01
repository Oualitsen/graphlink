import 'package:retrofit_graphql/src/model/gq_argument.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_has_directives.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';

class GQField with GqDirectivesMixin {
  final String name;
  final GQType type;
  final Object? initialValue;
  final String? documentation;
  final List<GQArgumentDefinition> arguments;

  bool? _isArray;

  bool? _containsSkipOrIncludeDirective;

  GQField({
    required this.name,
    required this.type,
    required this.arguments,
    this.initialValue,
    this.documentation,
    required List<GQDirectiveValue> directives,
  }) {
    directives.forEach(addDirective);
  }

  @override
  bool operator ==(Object other) {
    if (other is GQField && runtimeType == other.runtimeType) {
      return name == other.name && type == other.type;
    }
    return false;
  }

  @override
  int get hashCode => name.hashCode * type.hashCode;


  //check for inclue or skip directives
  bool get hasInculeOrSkipDiretives => _containsSkipOrIncludeDirective ??=
      getDirectives().where((d) => [includeDirective, skipDirective].contains(d.token)).isNotEmpty;

  bool get serialzeAsArray {
    _isArray ??= getDirectives().where((e) => e.token == gqArray).isNotEmpty;
    return _isArray!;
  }
}
