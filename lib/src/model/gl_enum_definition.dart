import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/token_info.dart';

class GLEnumDefinition extends GLExtensibleToken with GLDirectivesMixin {
  final Map<String, GLEnumValue> _values = {};

  GLEnumDefinition(
      {required TokenInfo token,
      required Iterable<GLEnumValue> values,
      required List<GLDirectiveValue> directives,
      required bool extension,
      String? documentation})
      : super(token, extension, documentation: documentation) {
    values.forEach(addValue);

    directives.forEach(addDirective);
  }

  List<GLEnumValue> get values => _values.values.toList();

  /// Assigns a collision-free, keyword-safe [GLEnumValue.codeName] to each value
  /// whose name is reserved in the target language. The original token stays the
  /// wire string used in toJson/fromJson; only the emitted constant changes.
  void assignCodeNames(Set<String> reservedWords) {
    if (reservedWords.isEmpty) return;
    final taken = _values.keys.toSet();
    for (final value in _values.values) {
      final name = value.value.token;
      if (!reservedWords.contains(name)) continue;
      var candidate = "${name}_";
      var counter = 2;
      while (taken.contains(candidate)) {
        candidate = "${name}_$counter";
        counter++;
      }
      value.codeName = candidate;
      taken.add(candidate);
    }
  }

  void addValue(GLEnumValue value) {
    if (_values.containsKey(value.token)) {
      throw ParseException("${value.token} already defined on enum ${token}",
          info: value.tokenInfo);
    }
    _values[value.token] = value;
  }

  @override
  void merge<T extends GLExtensibleToken>(T other) {
    if (other is GLEnumDefinition) {
      other.getDirectives().forEach(addDirective);
      other.values.forEach(addValue);
    }
  }
}

class GLEnumValue extends GLToken with GLDirectivesMixin {
  final TokenInfo value;
  final String? documentation;

  /// Keyword-safe identifier for the emitted enum constant. Defaults to the
  /// original [value] token (the wire string); set by
  /// [GLEnumDefinition.assignCodeNames] only when the name is reserved.
  String? _codeName;
  String get codeName => _codeName ?? value.token;
  set codeName(String value) => _codeName = value;

  GLEnumValue(
      {required this.value,
      required this.documentation,
      required List<GLDirectiveValue> directives})
      : super(value) {
    directives.forEach(addDirective);
  }
}
