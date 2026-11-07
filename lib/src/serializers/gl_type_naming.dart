import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';

abstract class GLTypeNaming {
  final GLParser grammar;
  late final CodeGenerationMode mode;
  final String importPrefix;

  /// Language-specific scalar defaults (e.g. Boolean→bool for Dart).
  /// Subclasses must override this.
  Map<String, String> get defaultTypeMap;

  /// Effective type map: language defaults merged with user-supplied overrides.
  late final Map<String, String> typeMap;

  /// Resolves the code name for a wire token across all schema maps.
  ///
  /// Returns [wireToken] unchanged when the token is not a user-defined type
  /// (e.g. a built-in scalar), letting the type-map lookup in [serializeType]
  /// handle it as usual.
  String resolveCodeName(String wireToken) {
    final typeOrInterface = grammar.types[wireToken] ?? grammar.interfaces[wireToken];
    if (typeOrInterface != null) {
      return typeOrInterface.mappedToType?.codeName ?? typeOrInterface.codeName;
    }
    return grammar.projectedTypes[wireToken]?.codeName ??
        grammar.inputs[wireToken]?.codeName ??
        grammar.enums[wireToken]?.codeName ??
        grammar.unions[wireToken]?.codeName ??
        wireToken;
  }

  GLTypeNaming(this.grammar, {Map<String, String> typeMapOverrides = const {}, required this.importPrefix})
      : mode = grammar.mode {
    typeMap = {...defaultTypeMap, ...typeMapOverrides};
    _applyUnknownScalarFallback();
    grammar.typeMap = typeMap;
  }

  /// Maps every custom scalar that has no explicit mapping to
  /// `grammar.unknownScalarType`, so unrecognized scalars (e.g. `scalar UserId`)
  /// are emitted as the configured target-language type instead of verbatim.
  /// Scalars already resolved by [defaultTypeMap], user `typeMappings`, or an
  /// `@glExternal` directive are left untouched — those take precedence.
  void _applyUnknownScalarFallback() {
    final fallback = grammar.unknownScalarType;
    if (fallback == null) return;
    for (final entry in grammar.scalars.entries) {
      if (typeMap.containsKey(entry.key)) continue;
      if (entry.value.getDirectiveByName(glExternal) != null) continue;
      typeMap[entry.key] = fallback;
    }
  }

  String? getTypeNameFromGQExternal(String token) {
    Object? typeWithDirectives = grammar.types[token] ??
        grammar.projectedTypes[token] ??
        grammar.interfaces[token] ??
        grammar.inputs[token] ??
        grammar.enums[token] ??
        grammar.scalars[token];
    typeWithDirectives = typeWithDirectives as GLDirectivesMixin?;
    var result = typeWithDirectives
        ?.getDirectiveByName(glExternal)
        ?.getArgValueAsString(glExternalArg);
    if (result == null) {
      return typeMap[token];
    }
    return result;
  }
}
