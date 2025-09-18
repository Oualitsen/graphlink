import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_enum_definition.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_directives_mixin.dart';
import 'package:retrofit_graphql/src/model/gq_input_type_definition.dart';
import 'package:retrofit_graphql/src/model/gq_interface_definition.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:retrofit_graphql/src/utils.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';

abstract class GqSerializer {
  final GQGrammar grammar;
  late final CodeGenerationMode mode;
  bool get generateJsonMethods;
  GqSerializer(this.grammar) : mode = grammar.mode;

  String serializeEnumDefinition(GQEnumDefinition def, String importPrefix) {
    if (shouldSkipSerialization(directives: def.getDirectives(), mode: mode)) {
      return "";
    }
    return serializeWithImport(def, importPrefix, doSerializeEnumDefinition(def));
  }

  String serialzeEnumValue(GQEnumValue value) {
    if (shouldSkipSerialization(directives: value.getDirectives(), mode: mode)) {
      return "";
    }
    return doSerializeEnumValue(value);
  }

  String doSerializeEnumDefinition(GQEnumDefinition def);

  String doSerializeEnumValue(GQEnumValue value);

  String serializeField(GQField def) {
    if (shouldSkipSerialization(directives: def.getDirectives(), mode: mode)) {
      return "";
    }
    return doSerializeField(def);
  }

  String doSerializeField(GQField def);
  String serializeType(GQType def, bool forceNullable, [bool asArray = false]);

  String serializeInputDefinition(GQInputDefinition def, String importPrefix) {
    if (shouldSkipSerialization(directives: def.getDirectives(), mode: mode)) {
      return "";
    }
    return serializeWithImport(def, importPrefix, doSerializeInputDefinition(def));
  }

  String doSerializeInputDefinition(GQInputDefinition def);

  String serializeTypeDefinition(GQTypeDefinition def, String importPrefix) {
    if (shouldSkipSerialization(directives: def.getDirectives(), mode: mode)) {
      return "";
    }
    return serializeWithImport(def, importPrefix, doSerializeTypeDefinition(def));
  }

  String doSerializeTypeDefinition(GQTypeDefinition def);

  String serializeDecorators(List<GQDirectiveValue> list, {String joiner = "\n"}) {
    var decorators = GQGrammarExtension.extractDecorators(directives: list, mode: grammar.mode);
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
    typeWithDirectives = typeWithDirectives as GQDirectivesMixin?;
    var result = typeWithDirectives?.getDirectiveByName(gqExternal)?.getArgValueAsString(gqExternalArg);
    if (result == null) {
      // check on typeMap
      return grammar.typeMap[token];
    }
    return result;
  }

  String getFileNameFor(GQToken token);

  String serializeImportToken(GQToken token, String importPrefix);
  String serializeImport(String import);

  String serializeWithImport(GQToken token, String importPrefix, String data) {
    var imports = serializeImports(token, importPrefix);
    var buffer = StringBuffer();
    buffer.writeln(imports);
    buffer.writeln();
    buffer.writeln(data);
    return buffer.toString();
  }

  String serializeImports(GQToken token, String importPrefix) {
    var deps = token.getImportDependecies(grammar);
    if (token is GQInterfaceDefinition && generateJsonMethods) {
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

  String serializeToken(GQToken token, String importPrefix) {
    if (token is GQEnumDefinition) {
      return serializeEnumDefinition(token, importPrefix);
    }
    if (token is GQTypeDefinition) {
      return serializeTypeDefinition(token, importPrefix);
    }
    if (token is GQInputDefinition) {
      return serializeInputDefinition(token, importPrefix);
    }

    throw "${token} is not an enum/type/input definition";
  }
}
