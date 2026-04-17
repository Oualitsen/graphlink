import 'package:graphlink/src/serializers/code_generation_mode.dart';

enum DartHttpAdapter { http, dio, none }

enum TypeScriptHttpAdapter { fetch, axios, none }

enum JavaWsAdapter { java11, okhttp, none }

enum JavaJsonCodec { jackson, gson, none }

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
      serverConfig:
          json['serverConfig'] != null ? ServerConfig.fromJson(json['serverConfig']) : null,
      clientConfig:
          json['clientConfig'] != null ? ClientConfig.fromJson(json['clientConfig']) : null,
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
  final bool generateSchema;
  final bool injectDataFetching;
  final bool reactive;
  /// When true and reactive is false, emits SecurityContext capture/propagation
  /// code inside CompletableFuture lambdas so the security context is available
  /// on worker threads. Requires spring-security on the classpath.
  /// Has no effect in reactive mode.
  final bool useSpringSecurity;
  final String? schemaTargetPath;
  final bool immutableInputFields;
  final bool immutableTypeFields;

  SpringServerConfig({
    required this.basePackage,
    required this.generateControllers,
    required this.generateInputs,
    required this.generateTypes,
    required this.generateRepositories,
    required this.inputAsRecord,
    required this.typeAsRecord,
    required this.generateSchema,
    required this.injectDataFetching,
    required this.reactive,
    required this.useSpringSecurity,
    required this.immutableInputFields,
    required this.immutableTypeFields,
    this.schemaTargetPath,
  }) : assert(
          !generateSchema ||
              (schemaTargetPath != null &&
                  (schemaTargetPath.endsWith('.graphql') ||
                      schemaTargetPath.endsWith('.graphqls'))),
          'schemaTargetPath must be a non-null path ending with .graphql or .graphqls when generateSchema is true',
        );

  factory SpringServerConfig.fromJson(Map<String, dynamic> json) {
    return SpringServerConfig(
        basePackage: json['basePackage'],
        generateControllers: json['generateControllers'] ?? true,
        generateInputs: json['generateInputs'] ?? true,
        generateTypes: json['generateTypes'] ?? true,
        generateRepositories: json['generateRepositories'] ?? false,
        inputAsRecord: json['inputAsRecord'] ?? false,
        typeAsRecord: json['typeAsRecord'] ?? false,
        generateSchema: json['generateSchema'] ?? false,
        immutableInputFields: json['immutableInputFields'] ?? true,
        immutableTypeFields: json['immutableTypeFields'] ?? false,
        schemaTargetPath: json['schemaTargetPath'],
        injectDataFetching: json['injectDataFetching'] as bool? ?? false,
        reactive: json['reactive'] as bool? ?? false,
        useSpringSecurity: json['useSpringSecurity'] as bool? ?? false);
  }
}

class ClientConfig {
  final DartClientConfig? dart;
  final JavaClientConfig? java;
  final TypeScriptClientConfig? typescript;

  ClientConfig({this.dart, this.java, this.typescript})
      : assert(dart != null || java != null || typescript != null,
            'ClientConfig must have at least one of dart, java, or typescript');

  factory ClientConfig.fromJson(Map<String, dynamic> json) {
    return ClientConfig(
      dart: json['dart'] != null ? DartClientConfig.fromJson(json['dart']) : null,
      java: json['java'] != null ? JavaClientConfig.fromJson(json['java']) : null,
      typescript: json['typescript'] != null ? TypeScriptClientConfig.fromJson(json['typescript']) : null,
    );
  }
}

class DartClientConfig {
  final bool generateAllFieldsFragments;
  final bool nullableFieldsRequired;
  final bool autoGenerateQueries;
  final bool operationNameAsParameter;
  final String? autoGenerateQueriesDefaultAlias;
  final String? defaultAlias;
  final String? packageName;
  final String? appLocalizationsImport;
  final bool generateUiTypes;
  final bool generateUiInputs;
  final bool immutableInputFields;
  final bool immutableTypeFields;
  final bool generateAdapters;
  final DartHttpAdapter httpAdapter;

  DartClientConfig({
    required this.generateAllFieldsFragments,
    required this.nullableFieldsRequired,
    required this.autoGenerateQueries,
    this.autoGenerateQueriesDefaultAlias,
    required this.operationNameAsParameter,
    this.defaultAlias,
    this.packageName,
    this.appLocalizationsImport,
    this.generateUiInputs = false,
    this.generateUiTypes = false,
    this.immutableInputFields = true,
    this.immutableTypeFields = true,
    this.generateAdapters = true,
    this.httpAdapter = DartHttpAdapter.http,
  });

  factory DartClientConfig.fromJson(Map<String, dynamic> json) {
    return DartClientConfig(
      generateAllFieldsFragments: json['generateAllFieldsFragments'] ?? false,
      nullableFieldsRequired: json['nullableFieldsRequired'] ?? false,
      autoGenerateQueries: json['autoGenerateQueries'] ?? false,
      autoGenerateQueriesDefaultAlias: json['autoGenerateQueriesDefaultAlias'] as String?,
      operationNameAsParameter: json['operationNameAsParameter'] ?? false,
      defaultAlias: json['defaultAlias'],
      packageName: json['packageName'] as String?,
      appLocalizationsImport: json['appLocalizationsImport'] as String?,
      generateUiInputs: (json['generateUiInputs'] as bool?) ?? false,
      generateUiTypes: (json['generateUiTypes'] as bool?) ?? false,
      immutableInputFields: (json['immutableInputFields'] as bool?) ?? true,
      immutableTypeFields: (json['immutableTypeFields'] as bool?) ?? true,
      generateAdapters: (json['generateAdapters'] as bool?) ?? true,
      httpAdapter: DartHttpAdapter.values.firstWhere(
        (e) => e.name == json['httpAdapter'],
        orElse: () => DartHttpAdapter.http,
      ),
    );
  }
}

class JavaClientConfig {
  final String packageName;
  final bool generateAllFieldsFragments;
  final bool nullableFieldsRequired;
  final bool autoGenerateQueries;
  final bool operationNameAsParameter;
  final bool immutableInputFields;
  final bool immutableTypeFields;
  final bool inputAsRecord;
  final bool typeAsRecord;
  final JavaWsAdapter wsAdapter;
  final JavaJsonCodec jsonCodec;
  final String? defaultAlias;

  JavaClientConfig({
    required this.packageName,
    this.generateAllFieldsFragments = false,
    this.nullableFieldsRequired = false,
    this.autoGenerateQueries = false,
    this.operationNameAsParameter = false,
    this.immutableInputFields = true,
    this.immutableTypeFields = true,
    this.inputAsRecord = false,
    this.typeAsRecord = false,
    this.wsAdapter = JavaWsAdapter.java11,
    this.jsonCodec = JavaJsonCodec.jackson,
    this.defaultAlias,
  });

  factory JavaClientConfig.fromJson(Map<String, dynamic> json) {
    return JavaClientConfig(
      packageName: json['packageName'] as String,
      generateAllFieldsFragments: (json['generateAllFieldsFragments'] as bool?) ?? false,
      nullableFieldsRequired: (json['nullableFieldsRequired'] as bool?) ?? false,
      autoGenerateQueries: (json['autoGenerateQueries'] as bool?) ?? false,
      operationNameAsParameter: (json['operationNameAsParameter'] as bool?) ?? false,
      immutableInputFields: (json['immutableInputFields'] as bool?) ?? true,
      immutableTypeFields: (json['immutableTypeFields'] as bool?) ?? true,
      inputAsRecord: (json['inputAsRecord'] as bool?) ?? false,
      typeAsRecord: (json['typeAsRecord'] as bool?) ?? false,
      defaultAlias: json['defaultAlias'],
      wsAdapter: JavaWsAdapter.values.firstWhere(
        (e) => e.name == json['wsAdapter'],
        orElse: () => JavaWsAdapter.java11,
      ),
      jsonCodec: JavaJsonCodec.values.firstWhere(
        (e) => e.name == json['jsonCodec'],
        orElse: () => JavaJsonCodec.jackson,
      ),
    );
  }
}

class TypeScriptClientConfig {
  final bool generateAllFieldsFragments;
  final bool autoGenerateQueries;
  final bool operationNameAsParameter;
  final bool immutableTypeFields;
  final bool optionalNullableInputFields;
  final bool generateDefaultWsAdapter;
  final TypeScriptHttpAdapter httpAdapter;
  final String? defaultAlias;

  TypeScriptClientConfig({
    this.generateAllFieldsFragments = false,
    this.autoGenerateQueries = false,
    this.operationNameAsParameter = false,
    this.immutableTypeFields = true,
    this.optionalNullableInputFields = true,
    this.generateDefaultWsAdapter = true,
    this.httpAdapter = TypeScriptHttpAdapter.fetch,
    this.defaultAlias,
  });

  factory TypeScriptClientConfig.fromJson(Map<String, dynamic> json) {
    return TypeScriptClientConfig(
      generateAllFieldsFragments: (json['generateAllFieldsFragments'] as bool?) ?? false,
      autoGenerateQueries: (json['autoGenerateQueries'] as bool?) ?? false,
      operationNameAsParameter: (json['operationNameAsParameter'] as bool?) ?? false,
      immutableTypeFields: (json['immutableTypeFields'] as bool?) ?? true,
      optionalNullableInputFields: (json['optionalNullableInputFields'] as bool?) ?? true,
      generateDefaultWsAdapter: (json['generateDefaultWsAdapter'] as bool?) ?? true,
      httpAdapter: TypeScriptHttpAdapter.values.firstWhere(
        (e) => e.name == json['httpAdapter'],
        orElse: () => TypeScriptHttpAdapter.fetch,
      ),
      defaultAlias: json['defaultAlias'],
    );
  }
}

