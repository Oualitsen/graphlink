import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/token_info.dart';

class GLField with GLDirectivesMixin {
  final TokenInfo name;
  final GLType type;
  final Object? initialValue;
  final String? documentation;
  final Map<String, GLArgumentDefinition> _arguments = {};


  bool? _containsSkipOrIncludeDirective;

  GLField({
    required this.name,
    required this.type,
    required List<GLArgumentDefinition> arguments,
    this.initialValue,
    this.documentation,
    required List<GLDirectiveValue> directives,
  }) {
    directives.forEach(addDirective);
    arguments.forEach(_addArgument);
  }

  void _addArgument(GLArgumentDefinition arg) {
    _arguments[arg.token] = arg;
  }

  GLArgumentDefinition? getArgumentByName(String name) {
    return _arguments[name];
  }

  List<GLArgumentDefinition> get arguments => _arguments.values.toList();

  @override
  bool operator ==(Object other) {
    if (other is GLField && runtimeType == other.runtimeType) {
      return name == other.name && type == other.type;
    }
    return false;
  }

  @override
  int get hashCode => name.hashCode * type.hashCode;

  //check for inclue or skip directives
  bool get hasInculeOrSkipDiretives => _containsSkipOrIncludeDirective ??=
      getDirectives().where((d) => [includeDirective, skipDirective].contains(d.token)).isNotEmpty;

  /// Returns the target field name from @glMapField, or null if not declared.
  String? get mapFieldTo =>
      getDirectiveByName(glMapField)?.getArgValueAsString(glMapFieldTo);


  void checkMerge(GLField other) {
    if (type != other.type) {
      throw ParseException("You cannot change field type in an extension", info: other.name);
    }
    if (arguments.length != other.arguments.length) {
      throw ParseException("You cannot add/remove arguments in an extension", info: other.name);
    }
    for (var arg in arguments) {
      var otherArg = other.getArgumentByName(arg.token)!;
      if (arg.type != otherArg.type) {
        throw ParseException("You cannot alter argument type in an extension", info: otherArg.tokenInfo);
      }
    }
  }
}
