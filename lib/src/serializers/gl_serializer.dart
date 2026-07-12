import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/utils.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_maps_to_extension.dart';

abstract class GLSerializer {
  final GLParser grammar;
  late final CodeGenerationMode mode;
  final String importPrefix;

  /// Language-specific scalar defaults (e.g. Boolean→bool for Dart).
  /// Subclasses must override this.
  Map<String, String> get defaultTypeMap;

  /// Converts a parsed GraphQL default value into a target-language literal
  /// expression. [type] is the field's declared GraphQL type (used to resolve
  /// whether a bare-identifier value is an enum reference or a scalar).
  /// [value] is the raw [GLField.initialValue] as produced by the parser:
  ///   - [int] / [double] / [bool] — emit as-is
  ///   - [String] with surrounding quotes (e.g. `"anonymous"`) — strip quotes,
  ///     format as a language string literal
  ///   - [String] bare identifier (e.g. `USER`) — format as enum reference
  ///     (`EnumType.value`) when [type] resolves to a known enum
  ///   - [List] — format as a language list literal (recursively)
  ///   - `null` — emit null literal
  /// Must be implemented by every language serializer.
  /// When [needsConst] is true (Dart only), the outermost list/map/object
  /// literal is prefixed with `const`.  Inner elements are NOT prefixed
  /// because Dart's const-context propagation makes them implicitly const.
  String serializeDefaultLiteral(GLType type, Object? value, {bool needsConst = false});

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



  GLSerializer(this.grammar, {Map<String, String> typeMapOverrides = const {}, required this.importPrefix})
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

  String serializeEnumDefinition(GLEnumDefinition def) {
    if (shouldSkipSerialization(directives: def.getDirectives(), mode: mode)) {
      return "";
    }
    return serializeWithImport(
        def, doSerializeEnumDefinition(def));
  }

  String serialzeEnumValue(GLEnumValue value) {
    if (shouldSkipSerialization(
        directives: value.getDirectives(), mode: mode)) {
      return "";
    }
    return doSerializeEnumValue(value);
  }

  String doSerializeEnumDefinition(GLEnumDefinition def);

  String doSerializeEnumValue(GLEnumValue value);

  String serializeField(GLField def, bool immutable, bool isTypeField,
      {bool isOverride = false}) {
    if (shouldSkipSerialization(directives: def.getDirectives(), mode: mode)) {
      return "";
    }
    return '${serializeFieldDeprecation(def)}${doSerializeField(def, immutable, isTypeField, isOverride: isOverride)}';
  }

  String doSerializeField(GLField def, bool immutable, bool isTypeField,
      {bool isOverride = false});
  String serializeType(GLType def);

  /// Returns the language-specific deprecation marker for [field] (e.g. an
  /// annotation or JSDoc comment), or an empty string if the field is not
  /// marked `@deprecated`.
  String serializeFieldDeprecation(GLField field);

  /// Returns the language-specific deprecation marker for [value] (e.g. an
  /// annotation or JSDoc comment), or an empty string if the enum value is not
  /// marked `@deprecated`.
  String serializeEnumValueDeprecation(GLEnumValue value);

  String serializeInputDefinition(GLInputDefinition def) {
    if (shouldSkipSerialization(directives: def.getDirectives(), mode: mode)) {
      return "";
    }
    return serializeWithImport(
        def, doSerializeInputDefinition(def));
  }

  String doSerializeInputDefinition(GLInputDefinition def);

  String serializeTypeDefinition(GLTypeDefinition def) {
    if (shouldSkipSerialization(directives: def.getDirectives(), mode: mode)) {
      return "";
    }
    return serializeWithImport(
        def, doSerializeTypeDefinition(def));
  }

  String doSerializeTypeDefinition(GLTypeDefinition def);

  /// True when [def] must not get generated `toJson`/`fromJson` methods —
  /// language serializers should check this before emitting either method.
  bool shouldSkipJsonMethods(GLTypeDefinition def) => def.skipJsonMethods;

  String serializeDecorators(List<GLDirectiveValue> list,
      {String joiner = "\n"}) {
    var decorators = GLGrammarExtension.extractDecorators(
        directives: list, mode: grammar.mode);
    if (decorators.isEmpty) {
      return "";
    }
    return "${serializeListText(decorators, withParenthesis: false, join: joiner)}$joiner";
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

  String getFileNameFor(GLToken token);

  String serializeImportToken(GLToken token);
  String serializeImport(String import);

  String serializeWithImport(GLToken token, String data) {
    var imports = serializeImports(token);
    var buffer = StringBuffer();
    buffer.writeln(imports);
    buffer.writeln();
    buffer.writeln(data);
    return buffer.toString();
  }

  String serializeImports(GLToken token) {
    var deps = token.getImportDependecies(grammar).where((d) => d != token).toSet();
    if (token is GLInterfaceDefinition) {
      deps = {...deps, ...token.getSerializableImplementations(mode)};
    }
    var imports = token.getImports(grammar);
    if (deps.isEmpty && imports.isEmpty) {
      return "";
    }
    var buffer = StringBuffer();
    for (var dep in deps) {
      var import = serializeImportToken(dep);
      if (import.isNotEmpty) {
        buffer.writeln(import);
      }
    }
    for (var i in imports) {
      var import = serializeImport(i);
      if (import.isNotEmpty) {
        buffer.writeln(import);
      }
    }
    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // Mapping — @glMapsTo / @glMapField
  // Override generateToMethod and generateFromMethod in language serializers.
  // ---------------------------------------------------------------------------

  /// Generates the `toXxx()` method body for [def] → [targetType].
  /// Returns an empty string by default (no mapping support).
  String generateToMethod(
          GLInputDefinition def, String targetType, ToMappingPlan plan) =>
      '';

  /// Generates the `fromXxx()` static method body for [targetType] → [def].
  /// Returns an empty string by default (no mapping support).
  String generateFromMethod(
          GLInputDefinition def, String targetType, FromMappingPlan plan) =>
      '';

  /// Returns the mapping method strings for [def] if it declares @glMapsTo,
  /// otherwise returns an empty list.
  List<String> generateMappingMethods(GLInputDefinition def) {
    final toPlan = grammar.resolveToMappingPlan(def, mode);
    if (toPlan == null) return [];
    final fromPlan = grammar.resolveFromMappingPlan(def, mode)!;
    final targetWireName = def.mapsToType!;
    final targetName = grammar.types[targetWireName]?.codeName ?? targetWireName;
    return [
      if (toPlan.derivesAnythingFromSource)
        generateToMethod(def, targetName, toPlan),
      if (fromPlan.derivesAnythingFromTarget)
        generateFromMethod(def, targetName, fromPlan),
    ].where((s) => s.isNotEmpty).toList();
  }

  /// Serializes a [GLClassModel] to a source file string.
  ///
  /// When [withImports] is `true` (default) the import block is prepended to
  /// the body, producing a self-contained file.  Pass `false` to get just the
  /// class body — useful when embedding the class inside a larger file that
  /// already manages its own imports (e.g. the Dart single-file output).
  ///
  /// [importPrefix] is forwarded to [serializeImportToken] when resolving
  /// [GLClassModel.importDepencies] into language-specific import lines.
  /// Language-specific subclasses should override this to handle token
  /// dependencies via [serializeImportToken].
  String serializeGlClass(GLClassModel theClass,
      {bool withImports = true}) {
    if (!withImports) return theClass.body.trim();
    return theClass.toFileContent();
  }

  String serializeToken(GLToken token) {
    if (token is GLEnumDefinition) {
      return serializeEnumDefinition(token);
    }
    if (token is GLTypeDefinition) {
      return serializeTypeDefinition(token);
    }
    if (token is GLInputDefinition) {
      return serializeInputDefinition(token);
    }

    throw "${token} is not an enum/type/input definition";
  }
}
