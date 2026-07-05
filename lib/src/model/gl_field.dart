import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/code_name_mixin.dart';
import 'package:graphlink/src/model/token_info.dart';

class GLField with GLDirectivesMixin, CodeNameMixin {
  final TokenInfo name;
  final GLType type;
  final Object? initialValue;
  final String? documentation;
  final Map<String, GLArgumentDefinition> _arguments = {};

  List<GLArgumentDefinition>? _cachedArguments;
  bool? _containsSkipOrIncludeDirective;

  /// Set on a field returned by Spring controller return-type mappification
  /// (e.g. an enum field retyped to `String`, or a projectable type retyped
  /// to `Map<String, Object>`). Points back to the real (pre-mappification)
  /// type so the controller body knows what `.toJson()` conversion, if any,
  /// to apply to the value the service layer returns. Null for every field
  /// that wasn't mappified.
  GLType? originalType;

  @override
  String get wireName => name.token;

  GLField({
    required this.name,
    required this.type,
    required List<GLArgumentDefinition> arguments,
    this.initialValue,
    this.documentation,
    required List<GLDirectiveValue> directives,
  }) {
    directives.forEach(addDirective);
    arguments.forEach(addArgument);
  }

  void addArgument(GLArgumentDefinition arg) {
    _arguments[arg.token] = arg;
    _cachedArguments = null;
  }

  void removeArgument(String token) {
    _arguments.remove(token);
    _cachedArguments = null;
  }


  GLArgumentDefinition? getArgumentByName(String name) {
    return _arguments[name];
  }

  /// Arguments sorted by original declaration order. Insertion order into
  /// `_arguments` already reflects that in the common case, but a
  /// replaced/renamed argument (e.g. `fooAsMap` swapped in for `foo` during
  /// Spring controller mappification) is re-inserted at the end — sorting by
  /// [GLArgumentDefinition.effectiveDeclarationOrder] keeps such replacements
  /// at their original position instead.
  List<GLArgumentDefinition> get arguments {
    if (_cachedArguments != null) return _cachedArguments!;
    final sorted = _arguments.values.toList()
      ..sort((a, b) =>
          a.effectiveDeclarationOrder.compareTo(b.effectiveDeclarationOrder));
    return _cachedArguments = sorted;
  }

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

  /// Whether this field is marked @deprecated.
  bool get isDeprecated => getDirectiveByName(deprecatedDirective) != null;

  /// The deprecation reason, defaulting to `"No longer supported"` per the GraphQL spec.
  /// Returns `null` when the field is not deprecated.
  String? get deprecationReason {
    final d = getDirectiveByName(deprecatedDirective);
    if (d == null) return null;
    return d.getArgValueAsString("reason") ?? "No longer supported";
  }

  /// Returns the target field name from @glMapField, or null if not declared.
  String? get mapFieldTo =>
      getDirectiveByName(glMapField)?.getArgValueAsString(glMapFieldTo);



  /// Returns a copy of this field with [newType] in place of [type].
  GLField ofType(GLType newType) {
    return GLField(
      name: name,
      type: newType,
      arguments: [...arguments],
      initialValue: initialValue,
      documentation: documentation,
      directives: [...getDirectives()],
    );
  }

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
