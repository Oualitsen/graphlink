import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/model/gl_collection_imports.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/java_imports.dart';

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
  // TypeScript accesses fields as object properties; reserved words are legal
  // there, so fields need no sanitizing (parameters are handled separately,
  // see [_parameterReservedWordsFor]).
  return const {};
}

/// Parameter/binding-position reserved words for the target language. Differs
/// from [_reservedWordsFor] only for TypeScript, where reserved words are legal
/// as object-property names (fields) but illegal as parameter / destructuring
/// identifiers. Returning `null` lets [GLParser] default it to [reservedWords].
NamingConvention _namingConventionFor(GeneratorConfig config) {
  final lang = config.getMode() == CodeGenerationMode.server
      ? config.serverConfig!.language
      : config.clientConfig!.language;
  if (lang is DartClientConfig) return NamingConvention.dart;
  if (lang is JavaClientConfig || lang is SpringServerConfig) return NamingConvention.java;
  if (lang is KotlinClientConfig || lang is KotlinSpringServerConfig) return NamingConvention.kotlin;
  // TypeScript / Express Apollo
  return NamingConvention.typescript;
}

Set<String>? _parameterReservedWordsFor(GeneratorConfig config) {
  final lang = config.getMode() == CodeGenerationMode.server
      ? config.serverConfig!.language
      : config.clientConfig!.language;
  if (lang is TypeScriptClientConfig || lang is ExpressApolloServerConfig) {
    return typescriptParameterReservedWords;
  }
  return null;
}

/// `List`/`Map` import strings for the target language. Only Java needs an
/// explicit import for its collection types (`java.util.List`/`java.util.Map`);
/// Kotlin, Dart, and TypeScript use built-in collection types, so they
/// contribute no imports here.
GLCollectionImports _collectionImportsFor(GeneratorConfig config) {
  final lang = config.getMode() == CodeGenerationMode.server
      ? config.serverConfig!.language
      : config.clientConfig!.language;
  if (lang is JavaClientConfig || lang is SpringServerConfig) {
    return const GLCollectionImports(
      listImport: JavaImports.list,
      mapImport: JavaImports.map,
    );
  }
  return GLCollectionImports.none;
}

GLParser createGrammar(GeneratorConfig config) {
  final mode = config.getMode();
  if (mode == CodeGenerationMode.server) {
    return GLParser(
      mode: mode,
      naming: _namingConventionFor(config),
      identityFields: config.identityFields,
      reservedWords: _reservedWordsFor(config),
      parameterReservedWords: _parameterReservedWordsFor(config),
      collectionImports: _collectionImportsFor(config),
    )..unknownScalarType = config.unknownScalarType;
  }
  final lang = config.clientConfig!.language;
  return GLParser(
    mode: mode,
    naming: _namingConventionFor(config),
    reservedWords: _reservedWordsFor(config),
    parameterReservedWords: _parameterReservedWordsFor(config),
    identityFields: config.identityFields,
    disableCache: config.disableCache,
    collectionImports: _collectionImportsFor(config),
    generateAllFieldsFragments: lang.generateAllFieldsFragments,
    nullableFieldsRequired: lang.nullableFieldsRequired,
    autoGenerateQueries: lang.autoGenerateQueries,
    autoGenerateQueriesFor: lang.autoGenerateQueriesFor == null ? null : {
      GLQueryType.query: lang.autoGenerateQueriesFor!.queries,
      GLQueryType.mutation: lang.autoGenerateQueriesFor!.mutations,
      GLQueryType.subscription: lang.autoGenerateQueriesFor!.subscriptions,
    },
    defaultAlias: lang.defaultAlias,
    operationNameAsParameter: lang.operationNameAsParameter,
    captureErrors: lang.captureErrors,
    autoQueryArgumentLimit: lang.autoGenerateQueriesArgumentLimit,
    maxFragmentBodySize: lang.maxFragmentBodySize,
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
