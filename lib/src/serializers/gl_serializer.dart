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
import 'package:graphlink/src/gl_grammar_maps_to_extension.dart';

abstract class GLSerializer {
  final GLParser grammar;
  late final CodeGenerationMode mode;
  bool get generateJsonMethods;

  /// Language-specific scalar defaults (e.g. Boolean→bool for Dart).
  /// Subclasses must override this.
  Map<String, String> get defaultTypeMap;

  /// Effective type map: language defaults merged with user-supplied overrides.
  late final Map<String, String> typeMap;

  /// When `true`, type fields should be generated as nullable regardless of
  /// the schema declaration. Required in server mode because a GraphQL client
  /// may request only a subset of fields, so resolvers cannot guarantee every
  /// field is populated.
  bool get forceFieldNullable => mode == CodeGenerationMode.server;

  GLSerializer(this.grammar, {Map<String, String> typeMapOverrides = const {}})
      : mode = grammar.mode {
    typeMap = {...defaultTypeMap, ...typeMapOverrides};
    grammar.typeMap = typeMap;
  }

  String serializeEnumDefinition(GLEnumDefinition def, String importPrefix) {
    if (shouldSkipSerialization(directives: def.getDirectives(), mode: mode)) {
      return "";
    }
    return serializeWithImport(
        def, importPrefix, doSerializeEnumDefinition(def));
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

  String serializeField(GLField def, bool immutable, bool isTypeField) {
    if (shouldSkipSerialization(directives: def.getDirectives(), mode: mode)) {
      return "";
    }
    return doSerializeField(def, immutable, isTypeField);
  }

  String doSerializeField(GLField def, bool immutable, bool isTypeField);
  String serializeType(GLType def, bool forceNullable);

  String serializeInputDefinition(GLInputDefinition def, String importPrefix) {
    if (shouldSkipSerialization(directives: def.getDirectives(), mode: mode)) {
      return "";
    }
    return serializeWithImport(
        def, importPrefix, doSerializeInputDefinition(def));
  }

  String doSerializeInputDefinition(GLInputDefinition def);

  String serializeTypeDefinition(GLTypeDefinition def, String importPrefix) {
    if (shouldSkipSerialization(directives: def.getDirectives(), mode: mode)) {
      return "";
    }
    return serializeWithImport(
        def, importPrefix, doSerializeTypeDefinition(def));
  }

  String doSerializeTypeDefinition(GLTypeDefinition def);

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

  String serializeImportToken(GLToken token, String importPrefix);
  String serializeImport(String import);

  String serializeWithImport(GLToken token, String importPrefix, String data) {
    var imports = serializeImports(token, importPrefix);
    var buffer = StringBuffer();
    buffer.writeln(imports);
    buffer.writeln();
    buffer.writeln(data);
    return buffer.toString();
  }

  String serializeImports(GLToken token, String importPrefix) {
    var deps = token.getImportDependecies(grammar);
    if (token is GLInterfaceDefinition && generateJsonMethods) {
      deps = {...deps, ...token.getSerializableImplementations(mode)};
    }
    var imports = token.getImports(grammar);
    if (deps.isEmpty && imports.isEmpty) {
      return "";
    }
    var buffer = StringBuffer();
    for (var dep in deps) {
      var import = serializeImportToken(dep, importPrefix);
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
          GLInputDefinition def, String targetType, MappingPlan plan) =>
      '';

  /// Generates the `fromXxx()` static method body for [targetType] → [def].
  /// Returns an empty string by default (no mapping support).
  String generateFromMethod(
          GLInputDefinition def, String targetType, MappingPlan plan) =>
      '';

  /// Returns the mapping method strings for [def] if it declares @glMapsTo,
  /// otherwise returns an empty list.
  List<String> generateMappingMethods(GLInputDefinition def) {
    final plan = grammar.resolveInputMappingPlan(def, mode);
    if (plan == null) return [];
    final targetName = def.mapsToType!;
    return [
      generateToMethod(def, targetName, plan),
      generateFromMethod(def, targetName, plan),
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
      {bool withImports = true, required String importPrefix}) {
    if (!withImports) return theClass.body.trim();
    return theClass.toFileContent();
  }

  String serializeToken(GLToken token, String importPrefix) {
    if (token is GLEnumDefinition) {
      return serializeEnumDefinition(token, importPrefix);
    }
    if (token is GLTypeDefinition) {
      return serializeTypeDefinition(token, importPrefix);
    }
    if (token is GLInputDefinition) {
      return serializeInputDefinition(token, importPrefix);
    }

    throw "${token} is not an enum/type/input definition";
  }
}
