import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/model/gq_argument.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_directives_mixin.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';

class GQField with GQDirectivesMixin {
  final TokenInfo name;
  final GQType type;
  final Object? initialValue;
  final String? documentation;
  final Map<String, GQArgumentDefinition> _arguments = {};

  bool? _isArray;

  bool? _containsSkipOrIncludeDirective;

  GQField({
    required this.name,
    required this.type,
    required List<GQArgumentDefinition> arguments,
    this.initialValue,
    this.documentation,
    required List<GQDirectiveValue> directives,
  }) {
    directives.forEach(addDirective);
    arguments.forEach(_addArgument);
  }

  void _addArgument(GQArgumentDefinition arg) {
    _arguments[arg.token] = arg;
  }

  GQArgumentDefinition? getArgumentByName(String name) {
    return _arguments[name];
  }

  List<GQArgumentDefinition> get arguments => _arguments.values.toList();

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

  void checkMerge(GQField other) {
    if (type != other.type) {
      throw ParseException("You cannot change field type in an extension", info: other.name);
    }
    if (arguments.length != other.arguments.length) {
      throw ParseException("You cannot add/remove arguments in an extension", info: other.name);
    }
    for (var arg in arguments) {
      var otherArg = other.getArgumentByName(arg.token)!;
      if (arg.type != otherArg.type) {
        throw ParseException("You cannot alter argument type in an extension",
            info: otherArg.tokenInfo);
      }
    }
  }
}
