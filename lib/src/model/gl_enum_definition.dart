import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/token_info.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/naming_convention.dart';

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

  /// Applies [convention] to every enum value, normalizing identifier casing.
  ///
  /// Collision with a sibling wire name or an already-assigned code name is
  /// resolved with an index suffix (`MALE`, `MALE2`, …). Must run before
  /// [assignCodeNames] so keyword-safe operates on the already-normalized name.
  void applyEnumValueNaming(NamingConvention convention) {
    final taken = _values.keys.toSet();
    for (final value in _values.values) {
      final raw = value.value.token;
      final normalized = convention.enumValue(raw);
      if (normalized == raw) continue;

      var code = normalized;
      if (taken.contains(code)) {
        var counter = 2;
        while (taken.contains('$code$counter')) counter++;
        code = '$code$counter';
      }
      value.codeName = code;
      taken.add(code);
    }
  }

  /// Assigns a collision-free, keyword-safe [GLEnumValue.codeName] to each value
  /// whose name is reserved in the target language or starts with a leading
  /// underscore. The original token stays the wire string used in
  /// toJson/fromJson; only the emitted constant changes.
  ///
  /// Starts from [GLEnumValue.codeName] (not the raw wire name) so that a prior
  /// [applyEnumValueNaming] pass is respected.
  void assignCodeNames(Set<String> reservedWords) {
    if (reservedWords.isEmpty) return;
    final taken = _values.keys.toSet();
    for (final value in _values.values) {
      // Start from codeName so normalization applied earlier is respected.
      final name = value.codeName;

      var codeName = name.startsWith('_') ? '${name.substring(1)}_' : name;
      if (codeName == name && !reservedWords.contains(name)) continue;

      if (reservedWords.contains(codeName)) {
        codeName = '${codeName}_';
      }
      var candidate = codeName;
      var counter = 2;
      while (taken.contains(candidate)) {
        candidate = '$codeName$counter';
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

  /// Whether this enum value is marked @deprecated.
  bool get isDeprecated => getDirectiveByName(deprecatedDirective) != null;

  /// The deprecation reason, defaulting to `"No longer supported"` per the GraphQL spec.
  /// Returns `null` when the enum value is not deprecated.
  String? get deprecationReason {
    final d = getDirectiveByName(deprecatedDirective);
    if (d == null) return null;
    return d.getArgValueAsString("reason") ?? "No longer supported";
  }
}
