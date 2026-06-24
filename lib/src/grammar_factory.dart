import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';

/// Reserved-word set for the target language. Only languages whose serializer
/// reads [GLField.codeName] should return a non-empty set. T
Set<String> _reservedWordsFor(GeneratorConfig config) {
  final lang = config.getMode() == CodeGenerationMode.server
      ? config.serverConfig!.language
      : config.clientConfig!.language;
  if (lang is DartClientConfig) return dartReservedWords;
  if (lang is JavaClientConfig || lang is SpringServerConfig) {
    return javaReservedWords;
  }
  if (lang is KotlinClientConfig || lang is KotlinSpringServerConfig) {
    return kotlinReservedWords;
  }
  // TypeScript accesses fields and arguments as object properties; reserved
  // words are legal there, so nothing to sanitize.
  return const {};
}

GLParser createGrammar(GeneratorConfig config) {
  final mode = config.getMode();
  if (mode == CodeGenerationMode.server) {
return GLParser(mode: mode, identityFields: config.identityFields, reservedWords: _reservedWordsFor(config),)
      ..unknownScalarType = config.unknownScalarType;
  }
  final lang = config.clientConfig!.language;
  return GLParser(
    mode: mode,
    reservedWords: _reservedWordsFor(config),
    identityFields: config.identityFields,
    disableCache: config.disableCache,
    generateAllFieldsFragments: lang.generateAllFieldsFragments,
    nullableFieldsRequired: lang.nullableFieldsRequired,
    autoGenerateQueries: lang.autoGenerateQueries,
    defaultAlias: lang.defaultAlias,
    operationNameAsParameter: lang.operationNameAsParameter,
    captureErrors: lang.captureErrors,
  )..unknownScalarType = config.unknownScalarType;
}

String? buildExtraGql(GLParser parser, GeneratorConfig config) {
  if (parser.mode != CodeGenerationMode.client) return null;
  final lang = config.clientConfig!.language;
  if (lang is JavaClientConfig) {
    return [
      javaJsonEncoderDecorder,
      if (parser.operationNameAsParameter)
        javaClientAdapterWithParamSync
      else
        javaClientAdapterNoParamSync,
      javaGraphLinkWebSocketAdapter,
    ].join();
  }
  if (lang is KotlinClientConfig) {
    return [
      kotlinJsonEncoderDecoder,
      kotlinClientAdapterGql,
    ].join();
  }
  return null;
}
