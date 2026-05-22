import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';

GLParser createGrammar(GeneratorConfig config) {
  final mode = config.getMode();
  if (mode == CodeGenerationMode.server) {
    return GLParser(mode: mode, identityFields: config.identityFields);
  }
  final lang = config.clientConfig!.language;
  return GLParser(
    mode: mode,
    identityFields: config.identityFields,
    disableCache: config.disableCache,
    generateAllFieldsFragments: lang.generateAllFieldsFragments,
    nullableFieldsRequired: lang.nullableFieldsRequired,
    autoGenerateQueries: lang.autoGenerateQueries,
    defaultAlias: lang.defaultAlias,
    operationNameAsParameter: lang.operationNameAsParameter,
    captureErrors: lang.captureErrors,
  );
}

String? buildExtraGql(GLParser parser, GeneratorConfig config) {
  if (parser.mode != CodeGenerationMode.client) return null;
  final lang = config.clientConfig!.language;
  if (lang is JavaClientConfig) {
    return [
      getClientObjects("Object", "Map<String, Object>"),
      javaJsonEncoderDecorder,
      if (parser.operationNameAsParameter)
        javaClientAdapterWithParamSync
      else
        javaClientAdapterNoParamSync,
      javaGraphLinkWebSocketAdapter,
    ].join();
  }
  if (lang is DartClientConfig) {
    return getClientObjects("dynamic", "Map<String, dynamic>");
  }
  if (lang is TypeScriptClientConfig) {
    return getClientObjects("unknown", "Record<string, unknown>");
  }
  return null;
}
