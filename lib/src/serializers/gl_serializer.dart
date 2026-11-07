import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/scalar_codec.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_scalar_codec_extension.dart';
import 'package:graphlink/src/utils.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_maps_to_extension.dart';

import 'package:graphlink/src/serializers/gl_import_rendering.dart';
import 'package:graphlink/src/serializers/gl_mapping_serializer.dart';

abstract class GLSerializer extends GLImportRendering {
  GLSerializer(super.grammar, {super.typeMapOverrides, required super.importPrefix});

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

  /// A string literal of the target language whose value is [decoded] (a GraphQL
  /// string literal already resolved by [decodeGraphqlString]).
  /// Must be implemented by every language serializer.
  String stringLiteral(String decoded);

  /// The decoder member of an interface whose only implementation is synthetic
  /// ([GLInterfaceDefinition.syntheticImplementation]): it returns that
  /// implementation directly and never reads `__typename`. Called in place of
  /// the dispatching decoder.
  /// Must be implemented by every language serializer.
  String serializeSyntheticInterfaceFromJson(GLInterfaceDefinition interface);

  /// The expression that turns [json], a raw JSON value in the target language
  /// (`dynamic`, `Any?`, `Object`, `unknown`), into the scalar's type using
  /// [codec]. [json] is substituted for `{}` in the codec's `fromJson` template.
  /// When [nullable], a null [json] yields null instead of reaching the template.
  /// Must be implemented by every language serializer.
  String scalarFromJson(GLScalarCodec codec, String json, {required bool nullable});

  /// The expression that turns [value], a value of the scalar's type, into a JSON
  /// value using [codec]. [value] is substituted for `{}` in the codec's `toJson`
  /// template. When [nullable], a null [value] yields null instead of reaching it.
  /// Must be implemented by every language serializer.
  String scalarToJson(GLScalarCodec codec, String value, {required bool nullable});

  /// The expression that turns [value], a code value of [type], into its JSON value:
  /// codec, then the type's own `toJson`, null-safe at every list level.
  /// [context] is the file being written, for languages that add imports.
  /// Must be implemented by every language serializer.
  String toJsonExpr(GLType type, String value, {int depth = 0, GLImportSink? context});

  /// The expression that turns [json], a raw JSON value, into a code value of [type]:
  /// codec, then the type's own `fromJson`, null-safe at every list level.
  /// Must be implemented by every language serializer.
  String fromJsonExpr(GLType type, String json, {int depth = 0, GLImportSink? context});

  /// The codec that decodes values of [type], or null when the scalar is a plain alias.
  GLScalarCodec? fromJsonCodecOf(GLType type) {
    final codec = grammar.scalarCodecOf(type.token);
    return codec != null && codec.canDecode ? codec : null;
  }

  /// The codec that encodes values of [type], or null when the scalar is a plain alias.
  GLScalarCodec? toJsonCodecOf(GLType type) {
    final codec = grammar.scalarCodecOf(type.token);
    return codec != null && codec.canEncode ? codec : null;
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

  // ---------------------------------------------------------------------------
  // Mapping — @glMapsTo / @glMapField
  // Override generateToMethod and generateFromMethod in language serializers.
  // ---------------------------------------------------------------------------

  /// The `@glMapsTo` mapping generator of the language, or null when it has none.
  GLMappingSerializer? get mapping => null;

  /// Returns the mapping method strings for [def] if it declares @glMapsTo,
  /// otherwise returns an empty list.
  List<String> generateMappingMethods(GLInputDefinition def) {
    if (mapping == null) return [];
    final toPlan = grammar.resolveToMappingPlan(def, mode);
    if (toPlan == null) return [];
    final fromPlan = grammar.resolveFromMappingPlan(def, mode)!;
    final targetWireName = def.mapsToType!;
    final targetName = grammar.types[targetWireName]?.codeName ?? targetWireName;
    return [
      if (toPlan.derivesAnythingFromSource)
        mapping!.toMethod(def, targetName, toPlan),
      if (fromPlan.derivesAnythingFromTarget)
        mapping!.fromMethod(def, targetName, fromPlan),
    ].where((s) => s.isNotEmpty).toList();
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
