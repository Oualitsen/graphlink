import 'package:retrofit_graphql/src/serializers/language.dart';

class GeneratorConfig {
  final List<String> schemaPaths;
  final String mode; // "server" or "client"
  final List<String> identityFields;
  Map<String, String>? typeMappings;
  final String outputDir;
  final ServerConfig? serverConfig;
  final ClientConfig? clientConfig;

  CodeGenerationMode getMode() {
    if (mode == "client") {
      return CodeGenerationMode.client;
    }
    return CodeGenerationMode.server;
  }

  GeneratorConfig({
    required this.schemaPaths,
    required this.mode,
    required this.identityFields,
    required this.typeMappings,
    required this.outputDir,
    this.serverConfig,
    this.clientConfig,
  });

  factory GeneratorConfig.fromJson(Map<String, dynamic> json) {
    return GeneratorConfig(
      schemaPaths: List<String>.from(json['schemaPaths'] ?? []),
      mode: json['mode'] ?? 'server',
      identityFields: List<String>.from(json['identityFields'] ?? []),
      typeMappings: Map<String, String>.from(json['typeMappings'] ?? {}),
      outputDir: json['outputDir'] ?? 'src/main/java',
      serverConfig: json['serverConfig'] != null ? ServerConfig.fromJson(json['serverConfig']) : null,
      clientConfig: json['clientConfig'] != null ? ClientConfig.fromJson(json['clientConfig']) : null,
    );
  }
}

// ServerConfig supports multiple frameworks
class ServerConfig {
  final SpringServerConfig? spring;

  ServerConfig({this.spring});

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      spring: json['spring'] != null ? SpringServerConfig.fromJson(json['spring']) : null,
    );
  }
}

class SpringServerConfig {
  final String basePackage;
  final bool generateControllers;
  final bool generateInputs;
  final bool generateTypes;
  final bool generateRepositories;
  final bool inputAsRecord;
  final bool typeAsRecord;

  SpringServerConfig(
      {required this.basePackage,
      required this.generateControllers,
      required this.generateInputs,
      required this.generateTypes,
      required this.generateRepositories,
      required this.inputAsRecord,
      required this.typeAsRecord});

  factory SpringServerConfig.fromJson(Map<String, dynamic> json) {
    return SpringServerConfig(
      basePackage: json['basePackage'],
      generateControllers: json['generateControllers'] ?? true,
      generateInputs: json['generateInputs'] ?? true,
      generateTypes: json['generateTypes'] ?? true,
      generateRepositories: json['generateRepositories'] ?? false,
      inputAsRecord: json['inputAsRecord'] ?? false,
      typeAsRecord: json['typeAsRecord'] ?? false,
    );
  }
}

class ClientConfig {
  final String targetLanguage; // e.g., "dart"
  final bool generateAllFieldsFragments;
  final bool nullableFieldsRequired;
  final bool autoGenerateQueries;
  final bool operationNameAsParameter;
  final String? autoGenerateQueriesDefaultAlias;
  final String? defaultAlias;

  ClientConfig(
      {required this.targetLanguage,
      required this.generateAllFieldsFragments,
      required this.nullableFieldsRequired,
      required this.autoGenerateQueries,
      this.autoGenerateQueriesDefaultAlias,
      required this.operationNameAsParameter,
      this.defaultAlias});

  factory ClientConfig.fromJson(Map<String, dynamic> json) {
    return ClientConfig(
      targetLanguage: json['targetLanguage'] ?? 'dart',
      generateAllFieldsFragments: json['generateAllFieldsFragments'] ?? false,
      nullableFieldsRequired: json['nullableFieldsRequired'] ?? false,
      autoGenerateQueries: json['autoGenerateQueries'] ?? false,
      autoGenerateQueriesDefaultAlias: json['autoGenerateQueriesDefaultAlias'] as String?,
      operationNameAsParameter: json['operationNameAsParameter'] ?? false,
      defaultAlias: json['defaultAlias'],
    );
  }
}
