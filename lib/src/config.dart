import 'package:graphlink/src/serializers/code_generation_mode.dart';

enum DartHttpAdapter { http, dio, none }

enum TypeScriptHttpAdapter { fetch, axios, none }

enum JavaWsAdapter { java11, okhttp, none }

enum JavaJsonCodec { jackson, gson, none }

// ── Abstract base classes ────────────────────────────────────────────────────

abstract class ClientLanguageConfig {
  bool get generateAllFieldsFragments => true;
  bool get nullableFieldsRequired => false;
  bool get autoGenerateQueries => true;
  bool get operationNameAsParameter => false;
  bool get immutableTypeFields => true;
  String? get defaultAlias => null;

  static ClientLanguageConfig fromJson(Map<String, dynamic> json) {
    if (json['dart'] != null) return DartClientConfig.fromJson(json['dart'] as Map<String, dynamic>);
    if (json['java'] != null) return JavaClientConfig.fromJson(json['java'] as Map<String, dynamic>);
    if (json['typescript'] != null) return TypeScriptClientConfig.fromJson(json['typescript'] as Map<String, dynamic>);
    throw ArgumentError('clientConfig must specify one of: dart, java, typescript');
  }
}

abstract class ServerLanguageConfig {
  static ServerLanguageConfig fromJson(Map<String, dynamic> json) {
    if (json['spring'] != null) return SpringServerConfig.fromJson(json['spring'] as Map<String, dynamic>);
    if (json['expressApollo'] != null) return ExpressApolloServerConfig.fromJson(json['expressApollo'] as Map<String, dynamic>);
    throw ArgumentError('serverConfig must specify one of: spring, expressApollo');
  }
}

// ── Top-level config ─────────────────────────────────────────────────────────

class GeneratorConfig {
  final List<String> schemaPaths;
  final String mode;
  final List<String> identityFields;
  Map<String, String>? typeMappings;
  final bool disableCache;
  final String outputDir;
  final ServerConfig? serverConfig;
  final ClientConfig? clientConfig;

  CodeGenerationMode getMode() =>
      mode == 'client' ? CodeGenerationMode.client : CodeGenerationMode.server;

  GeneratorConfig({
    required this.schemaPaths,
    required this.mode,
    required this.identityFields,
    required this.typeMappings,
    required this.outputDir,
    this.disableCache = false,
    this.serverConfig,
    this.clientConfig,
  });

  factory GeneratorConfig.fromJson(Map<String, dynamic> json) {
    return GeneratorConfig(
      schemaPaths: List<String>.from(json['schemaPaths'] ?? []),
      mode: json['mode'] ?? 'server',
      identityFields: List<String>.from(json['identityFields'] ?? []),
      typeMappings: Map<String, String>.from(json['typeMappings'] ?? {}),
      disableCache: (json['disableCache'] as bool?) ?? false,
      outputDir: json['outputDir'] ?? 'src/main/java',
      serverConfig: json['serverConfig'] != null ? ServerConfig.fromJson(json['serverConfig'] as Map<String, dynamic>) : null,
      clientConfig: json['clientConfig'] != null ? ClientConfig.fromJson(json['clientConfig'] as Map<String, dynamic>) : null,
    );
  }
}

// ── Server config ─────────────────────────────────────────────────────────────

class ServerConfig {
  final ServerLanguageConfig language;

  ServerConfig(this.language);

  factory ServerConfig.fromJson(Map<String, dynamic> json) =>
      ServerConfig(ServerLanguageConfig.fromJson(json));
}

class ExpressApolloServerConfig extends ServerLanguageConfig {
  final int port;
  final String graphqlPath;
  final bool generateEntryPoint;
  final bool useResolveInfo;

  ExpressApolloServerConfig({
    this.port = 4000,
    this.graphqlPath = '/graphql',
    this.generateEntryPoint = true,
    this.useResolveInfo = false,
  });

  factory ExpressApolloServerConfig.fromJson(Map<String, dynamic> json) {
    return ExpressApolloServerConfig(
      port: (json['port'] as int?) ?? 4000,
      graphqlPath: (json['graphqlPath'] as String?) ?? '/graphql',
      generateEntryPoint: (json['generateEntryPoint'] as bool?) ?? true,
      useResolveInfo: (json['useResolveInfo'] as bool?) ?? false,
    );
  }
}

class SpringServerConfig extends ServerLanguageConfig {
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
      basePackage: json['basePackage'] as String,
      generateControllers: (json['generateControllers'] as bool?) ?? true,
      generateInputs: (json['generateInputs'] as bool?) ?? true,
      generateTypes: (json['generateTypes'] as bool?) ?? true,
      generateRepositories: (json['generateRepositories'] as bool?) ?? false,
      inputAsRecord: (json['inputAsRecord'] as bool?) ?? false,
      typeAsRecord: (json['typeAsRecord'] as bool?) ?? false,
      generateSchema: (json['generateSchema'] as bool?) ?? false,
      immutableInputFields: (json['immutableInputFields'] as bool?) ?? true,
      immutableTypeFields: (json['immutableTypeFields'] as bool?) ?? false,
      schemaTargetPath: json['schemaTargetPath'] as String?,
      injectDataFetching: (json['injectDataFetching'] as bool?) ?? false,
      reactive: (json['reactive'] as bool?) ?? false,
      useSpringSecurity: (json['useSpringSecurity'] as bool?) ?? false,
    );
  }
}

// ── Client configs ────────────────────────────────────────────────────────────

class ClientConfig {
  final ClientLanguageConfig language;

  ClientConfig(this.language);

  factory ClientConfig.fromJson(Map<String, dynamic> json) =>
      ClientConfig(ClientLanguageConfig.fromJson(json));
}

enum BooleanWidget { tristate, checkbox, switchWidget }

enum NullableBooleanWidget { tristate, checkbox }

enum ListWidget { chips, checkboxes }

class FlutterConfig {
  final List<String> typesToSkip;
  final List<String> inputsToSkip;
  final bool generateTypes;
  final bool generateInputs;
  final double defaultGap;
  final BooleanWidget booleanWidget;
  final NullableBooleanWidget nullableBooleanWidget;
  final ListWidget listWidget;

  const FlutterConfig({
    this.typesToSkip = const [],
    this.inputsToSkip = const [],
    this.generateTypes = true,
    this.generateInputs = false,
    this.defaultGap = 16,
    this.booleanWidget = BooleanWidget.switchWidget,
    this.nullableBooleanWidget = NullableBooleanWidget.checkbox,
    this.listWidget = ListWidget.chips,
  });

  factory FlutterConfig.fromJson(Map<String, dynamic> json) {
    final nullableBoolStr = json['nullableBooleanWidget'] as String? ?? 'checkbox';
    if (nullableBoolStr == 'switch') {
      throw ArgumentError('nullableBooleanWidget cannot be "switch": Switch cannot represent null. Use "checkbox" or "tristate".');
    }
    return FlutterConfig(
      typesToSkip: List<String>.from(json['typesToSkip'] ?? []),
      inputsToSkip: List<String>.from(json['inputsToSkip'] ?? []),
      generateTypes: (json['generateTypes'] as bool?) ?? true,
      generateInputs: (json['generateInputs'] as bool?) ?? false,
      defaultGap: (json['defaultGap'] as num?)?.toDouble() ?? 16,
      booleanWidget: BooleanWidget.values.firstWhere(
        (e) => e.name == (json['booleanWidget'] as String? ?? 'switchWidget'),
        orElse: () => BooleanWidget.switchWidget,
      ),
      nullableBooleanWidget: NullableBooleanWidget.values.firstWhere(
        (e) => e.name == nullableBoolStr,
        orElse: () => NullableBooleanWidget.checkbox,
      ),
      listWidget: ListWidget.values.firstWhere(
        (e) => e.name == (json['listWidget'] as String? ?? 'chips'),
        orElse: () => ListWidget.chips,
      ),
    );
  }
}

class DartClientConfig extends ClientLanguageConfig {
  @override final bool generateAllFieldsFragments;
  @override final bool nullableFieldsRequired;
  @override final bool autoGenerateQueries;
  @override final bool operationNameAsParameter;
  @override final bool immutableTypeFields;
  @override final String? defaultAlias;

  final String? autoGenerateQueriesDefaultAlias;
  final String? packageName;
  final String? appLocalizationsImport;
  final FlutterConfig? flutter;
  final bool immutableInputFields;
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
    this.flutter,
    this.immutableInputFields = true,
    this.immutableTypeFields = true,
    this.generateAdapters = true,
    this.httpAdapter = DartHttpAdapter.http,
  });

  factory DartClientConfig.fromJson(Map<String, dynamic> json) {
    return DartClientConfig(
      generateAllFieldsFragments: (json['generateAllFieldsFragments'] as bool?) ?? true,
      nullableFieldsRequired: (json['nullableFieldsRequired'] as bool?) ?? false,
      autoGenerateQueries: (json['autoGenerateQueries'] as bool?) ?? true,
      autoGenerateQueriesDefaultAlias: json['autoGenerateQueriesDefaultAlias'] as String?,
      operationNameAsParameter: (json['operationNameAsParameter'] as bool?) ?? false,
      defaultAlias: json['defaultAlias'] as String?,
      packageName: json['packageName'] as String?,
      appLocalizationsImport: json['appLocalizationsImport'] as String?,
      flutter: json['flutter'] != null
          ? FlutterConfig.fromJson(json['flutter'] as Map<String, dynamic>)
          : null,
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

class JavaClientConfig extends ClientLanguageConfig {
  @override final bool generateAllFieldsFragments;
  @override final bool nullableFieldsRequired;
  @override final bool autoGenerateQueries;
  @override final bool operationNameAsParameter;
  @override final bool immutableTypeFields;
  @override final String? defaultAlias;

  final String packageName;
  final bool immutableInputFields;
  final bool inputAsRecord;
  final bool typeAsRecord;
  final JavaWsAdapter wsAdapter;
  final JavaJsonCodec jsonCodec;

  JavaClientConfig({
    required this.packageName,
    this.generateAllFieldsFragments = true,
    this.nullableFieldsRequired = false,
    this.autoGenerateQueries = true,
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
      generateAllFieldsFragments: (json['generateAllFieldsFragments'] as bool?) ?? true,
      nullableFieldsRequired: (json['nullableFieldsRequired'] as bool?) ?? false,
      autoGenerateQueries: (json['autoGenerateQueries'] as bool?) ?? true,
      operationNameAsParameter: (json['operationNameAsParameter'] as bool?) ?? false,
      immutableInputFields: (json['immutableInputFields'] as bool?) ?? true,
      immutableTypeFields: (json['immutableTypeFields'] as bool?) ?? true,
      inputAsRecord: (json['inputAsRecord'] as bool?) ?? false,
      typeAsRecord: (json['typeAsRecord'] as bool?) ?? false,
      defaultAlias: json['defaultAlias'] as String?,
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

class TypeScriptClientConfig extends ClientLanguageConfig {
  @override final bool generateAllFieldsFragments;
  @override final bool autoGenerateQueries;
  @override final bool operationNameAsParameter;
  @override final bool immutableTypeFields;
  @override final String? defaultAlias;

  final bool optionalNullableInputFields;
  final bool generateDefaultWsAdapter;
  final bool observables;
  final TypeScriptHttpAdapter httpAdapter;

  TypeScriptClientConfig({
    this.generateAllFieldsFragments = true,
    this.autoGenerateQueries = true,
    this.operationNameAsParameter = false,
    this.immutableTypeFields = true,
    this.optionalNullableInputFields = true,
    this.generateDefaultWsAdapter = true,
    this.observables = false,
    this.httpAdapter = TypeScriptHttpAdapter.fetch,
    this.defaultAlias,
  });

  factory TypeScriptClientConfig.fromJson(Map<String, dynamic> json) {
    return TypeScriptClientConfig(
      generateAllFieldsFragments: (json['generateAllFieldsFragments'] as bool?) ?? true,
      autoGenerateQueries: (json['autoGenerateQueries'] as bool?) ?? true,
      operationNameAsParameter: (json['operationNameAsParameter'] as bool?) ?? false,
      immutableTypeFields: (json['immutableTypeFields'] as bool?) ?? true,
      optionalNullableInputFields: (json['optionalNullableInputFields'] as bool?) ?? true,
      generateDefaultWsAdapter: (json['generateDefaultWsAdapter'] as bool?) ?? true,
      observables: (json['observables'] as bool?) ?? false,
      httpAdapter: TypeScriptHttpAdapter.values.firstWhere(
        (e) => e.name == json['httpAdapter'],
        orElse: () => TypeScriptHttpAdapter.fetch,
      ),
      defaultAlias: json['defaultAlias'] as String?,
    );
  }
}
