import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/serializers/language.dart';
import 'package:graphlink/src/utils.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';

abstract class GLSerializer {
  final GLParser grammar;
  late final CodeGenerationMode mode;
  bool get generateJsonMethods;
  GLSerializer(this.grammar) : mode = grammar.mode;

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

  String serializeField(GLField def, bool immutable) {
    if (shouldSkipSerialization(directives: def.getDirectives(), mode: mode)) {
      return "";
    }
    return doSerializeField(def, immutable);
  }

  String doSerializeField(GLField def, bool immutable);
  String serializeType(GLType def, bool forceNullable, [bool asArray = false]);

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
      // check on typeMap
      return grammar.typeMap[token];
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
      deps = {...deps, ...token.implementations};
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
