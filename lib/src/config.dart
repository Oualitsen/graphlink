import 'package:graphlink/src/serializers/code_generation_mode.dart';

enum DartHttpAdapter { http, dio, none }

enum TypeScriptHttpAdapter { fetch, axios, none }

enum JavaWsAdapter { java11, okhttp, none }

/// Async style for the generated Java client. `blocking` keeps the existing
/// synchronous adapters; the reactive styles wrap operation results in the
/// library's deferred-single type (Mono/Single/Uni) and subscriptions in the
/// deferred-many type (Flux/Observable/Multi).
enum JavaAsyncStyle { blocking, reactor, rxjava3, mutiny }

/// HTTP transport for the generated reactive default adapter. `jdk` is the
/// universal `HttpClient.sendAsync` bridge (works with every reactive style,
/// zero extra dependency). `webclient` is Spring WebClient and is only valid
/// with [JavaAsyncStyle.reactor].
enum JavaReactiveHttpClient { jdk, webclient }

enum KotlinWsAdapter { okhttp, none }

enum JavaJsonCodec { jackson, gson, none }

// ── AutoGenerateQueriesFor ────────────────────────────────────────────────────

class AutoGenerateQueriesFor {
  final List<String> queries;
  final List<String> mutations;
  final List<String> subscriptions;

  const AutoGenerateQueriesFor({
    this.queries = const [],
    this.mutations = const [],
    this.subscriptions = const [],
  });

  bool get isEmpty => queries.isEmpty && mutations.isEmpty && subscriptions.isEmpty;

  factory AutoGenerateQueriesFor.fromJson(Map<String, dynamic> json) {
    return AutoGenerateQueriesFor(
      queries: List<String>.from(json['queries'] ?? []),
      mutations: List<String>.from(json['mutations'] ?? []),
      subscriptions: List<String>.from(json['subscriptions'] ?? []),
    );
  }
}

// ── Abstract base classes ────────────────────────────────────────────────────

abstract class ClientLanguageConfig {
  bool get generateAllFieldsFragments => true;
  bool get nullableFieldsRequired => false;
  bool get autoGenerateQueries => true;
  bool get operationNameAsParameter => false;
  bool get immutableTypeFields => true;
  bool get captureErrors => false;
  String? get defaultAlias => null;
  AutoGenerateQueriesFor? get autoGenerateQueriesFor => null;

  /// Maximum propagated-arg count before an auto-generated operation is skipped.
  /// `null` disables the cap entirely. Default 200 — grouping handles normal
  /// explosions; the cap only catches absurdly large schemas.
  int? get autoGenerateQueriesArgumentLimit => 200;

  static ClientLanguageConfig fromJson(Map<String, dynamic> json) {
    if (json['dart'] != null) return DartClientConfig.fromJson(json['dart'] as Map<String, dynamic>);
    if (json['java'] != null) return JavaClientConfig.fromJson(json['java'] as Map<String, dynamic>);
    if (json['typescript'] != null) return TypeScriptClientConfig.fromJson(json['typescript'] as Map<String, dynamic>);
    if (json['kotlin'] != null) return KotlinClientConfig.fromJson(json['kotlin'] as Map<String, dynamic>);
    throw ArgumentError('clientConfig must specify one of: dart, java, typescript, kotlin');
  }
}

abstract class ServerLanguageConfig {
  static ServerLanguageConfig fromJson(Map<String, dynamic> json) {
    if (json['spring'] != null) return SpringServerConfig.fromJson(json['spring'] as Map<String, dynamic>);
    if (json['kotlinSpring'] != null) return KotlinSpringServerConfig.fromJson(json['kotlinSpring'] as Map<String, dynamic>);
    if (json['expressApollo'] != null) return ExpressApolloServerConfig.fromJson(json['expressApollo'] as Map<String, dynamic>);
    throw ArgumentError('serverConfig must specify one of: spring, kotlinSpring, expressApollo');
  }
}

// ── Top-level config ─────────────────────────────────────────────────────────

class GeneratorConfig {
  final List<String> schemaPaths;
  final String mode;
  final List<String> identityFields;
  Map<String, String>? typeMappings;

  /// Target-language type used for any custom scalar that is not explicitly
  /// mapped (via [typeMappings] or `@glExternal`). When null, unmapped custom
  /// scalars are emitted verbatim using their declared scalar name.
  /// e.g. `"String"` for Dart, `"string"` for TypeScript, `"Object"` for Java.
  final String? unknownScalarType;
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
    this.unknownScalarType,
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
      unknownScalarType: json['unknownScalarType'] as String?,
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

/// Shared config for Spring Boot server generation, common across JVM
/// languages (Java, Kotlin). Language-specific options (e.g. record vs.
/// data class, reactive/security toggles) live on the subclasses.
abstract class SpringServerConfigBase extends ServerLanguageConfig {
  final String basePackage;
  final bool generateControllers;
  final bool generateInputs;
  final bool generateTypes;
  final bool generateRepositories;
  final bool generateSchema;
  final String? schemaTargetPath;
  final bool immutableInputFields;
  final bool immutableTypeFields;
  final bool injectDataFetching;

  SpringServerConfigBase({
    required this.basePackage,
    required this.generateControllers,
    required this.generateInputs,
    required this.generateTypes,
    required this.generateRepositories,
    required this.generateSchema,
    required this.immutableInputFields,
    required this.immutableTypeFields,
    required this.injectDataFetching,
    this.schemaTargetPath,
  }) : assert(
          !generateSchema ||
              (schemaTargetPath != null &&
                  (schemaTargetPath.endsWith('.graphql') ||
                      schemaTargetPath.endsWith('.graphqls'))),
          'schemaTargetPath must be a non-null path ending with .graphql or .graphqls when generateSchema is true',
        );
}

class SpringServerConfig extends SpringServerConfigBase {
  final bool inputAsRecord;
  final bool typeAsRecord;
  final bool reactive;
  final bool useSpringSecurity;
  final bool jspecify;

  SpringServerConfig({
    required super.basePackage,
    required super.generateControllers,
    required super.generateInputs,
    required super.generateTypes,
    required super.generateRepositories,
    required this.inputAsRecord,
    required this.typeAsRecord,
    required super.generateSchema,
    required super.injectDataFetching,
    required this.reactive,
    required this.useSpringSecurity,
    required super.immutableInputFields,
    required super.immutableTypeFields,
    this.jspecify = false,
    super.schemaTargetPath,
  });

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
      jspecify: (json['jspecify'] as bool?) ?? false,
      schemaTargetPath: json['schemaTargetPath'] as String?,
      injectDataFetching: (json['injectDataFetching'] as bool?) ?? false,
      reactive: (json['reactive'] as bool?) ?? false,
      useSpringSecurity: (json['useSpringSecurity'] as bool?) ?? false,
    );
  }
}

class KotlinSpringServerConfig extends SpringServerConfigBase {
  final bool inputAsDataClass;
  final bool typeAsDataClass;

  /// Whether the generated `*Service` interfaces are implemented by blocking
  /// (JPA/JDBC) code. When `true`, controller methods wrap their service call
  /// in `withContext(Dispatchers.IO + SecurityCoroutineContext()) { ... }` —
  /// offloading blocking work and propagating `SecurityContextHolder` across
  /// the dispatcher switch. When `false`, the service layer is assumed to be
  /// coroutine-native/non-blocking and methods are emitted with no wrapping.
  final bool blockingServices;

  KotlinSpringServerConfig({
    required super.basePackage,
    required super.generateControllers,
    required super.generateInputs,
    required super.generateTypes,
    required super.generateRepositories,
    required this.inputAsDataClass,
    required this.typeAsDataClass,
    required this.blockingServices,
    required super.generateSchema,
    required super.injectDataFetching,
    required super.immutableInputFields,
    required super.immutableTypeFields,
    super.schemaTargetPath,
  });

  factory KotlinSpringServerConfig.fromJson(Map<String, dynamic> json) {
    return KotlinSpringServerConfig(
      basePackage: json['basePackage'] as String,
      generateControllers: (json['generateControllers'] as bool?) ?? true,
      generateInputs: (json['generateInputs'] as bool?) ?? true,
      generateTypes: (json['generateTypes'] as bool?) ?? true,
      generateRepositories: (json['generateRepositories'] as bool?) ?? false,
      inputAsDataClass: (json['inputAsDataClass'] as bool?) ?? false,
      typeAsDataClass: (json['typeAsDataClass'] as bool?) ?? false,
      blockingServices: (json['blockingServices'] as bool?) ?? true,
      generateSchema: (json['generateSchema'] as bool?) ?? false,
      immutableInputFields: (json['immutableInputFields'] as bool?) ?? true,
      immutableTypeFields: (json['immutableTypeFields'] as bool?) ?? false,
      schemaTargetPath: json['schemaTargetPath'] as String?,
      injectDataFetching: (json['injectDataFetching'] as bool?) ?? false,
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

enum LabelPosition { beside, above, floatingLabel }
enum FormLayout { column, twoColumn }
enum RequiredIndicator { none, asterisk, requiredText, optionalText }
enum StepperOrientation { vertical, horizontal }
enum TypeLayout { labeledRow, listTile, listTileReversed, expandable }
enum DateFieldMode { dialog, inline }
enum FlutterLabelStyle { bold, muted }

class FlutterConfig {
  final List<String> typesToSkip;
  final List<String> inputsToSkip;
  final bool generateTypes;
  final bool generateInputs;
  final double defaultGap;
  final BooleanWidget booleanWidget;
  final NullableBooleanWidget nullableBooleanWidget;
  final ListWidget listWidget;
  final LabelPosition defaultLabelPosition;
  final double defaultLabelWidth;
  final FormLayout defaultFormLayout;
  final RequiredIndicator defaultRequiredIndicator;
  final int defaultDebounceDuration;
  final StepperOrientation defaultStepperOrientation;
  final TypeLayout defaultTypeLayout;
  final TypeLayout defaultGroupLayout;
  final FlutterLabelStyle labelStyle;
  final String defaultDatePattern;
  final int defaultDateFirstYear;
  final int defaultDateLastYear;
  final DateFieldMode defaultDateMode;

  const FlutterConfig({
    this.typesToSkip = const [],
    this.inputsToSkip = const [],
    this.generateTypes = true,
    this.generateInputs = false,
    this.defaultGap = 16,
    this.booleanWidget = BooleanWidget.switchWidget,
    this.nullableBooleanWidget = NullableBooleanWidget.checkbox,
    this.listWidget = ListWidget.chips,
    this.defaultLabelPosition = LabelPosition.floatingLabel,
    this.defaultLabelWidth = 120,
    this.defaultFormLayout = FormLayout.column,
    this.defaultRequiredIndicator = RequiredIndicator.asterisk,
    this.defaultDebounceDuration = 300,
    this.defaultStepperOrientation = StepperOrientation.vertical,
    this.defaultTypeLayout = TypeLayout.labeledRow,
    this.defaultGroupLayout = TypeLayout.labeledRow,
    this.labelStyle = FlutterLabelStyle.bold,
    this.defaultDatePattern = 'yyyy-MM-dd',
    this.defaultDateFirstYear = 1900,
    this.defaultDateLastYear = 2100,
    this.defaultDateMode = DateFieldMode.dialog,
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
      defaultLabelPosition: LabelPosition.values.firstWhere(
        (e) => e.name == (json['defaultLabelPosition'] as String? ?? 'floatingLabel'),
        orElse: () => LabelPosition.floatingLabel,
      ),
      defaultLabelWidth: (json['defaultLabelWidth'] as num?)?.toDouble() ?? 120,
      defaultFormLayout: FormLayout.values.firstWhere(
        (e) => e.name == (json['defaultFormLayout'] as String? ?? 'column'),
        orElse: () => FormLayout.column,
      ),
      defaultRequiredIndicator: RequiredIndicator.values.firstWhere(
        (e) => e.name == (json['defaultRequiredIndicator'] as String? ?? 'asterisk'),
        orElse: () => RequiredIndicator.asterisk,
      ),
      defaultDebounceDuration: (json['defaultDebounceDuration'] as int?) ?? 300,
      defaultStepperOrientation: StepperOrientation.values.firstWhere(
        (e) => e.name == (json['defaultStepperOrientation'] as String? ?? 'vertical'),
        orElse: () => StepperOrientation.vertical,
      ),
      defaultTypeLayout: TypeLayout.values.firstWhere(
        (e) => e.name == (json['defaultTypeLayout'] as String? ?? 'labeledRow'),
        orElse: () => TypeLayout.labeledRow,
      ),
      defaultGroupLayout: TypeLayout.values.firstWhere(
        (e) => e.name == (json['defaultGroupLayout'] as String? ?? 'labeledRow'),
        orElse: () => TypeLayout.labeledRow,
      ),
      labelStyle: FlutterLabelStyle.values.firstWhere(
        (e) => e.name == (json['labelStyle'] as String? ?? 'bold'),
        orElse: () => FlutterLabelStyle.bold,
      ),
      defaultDatePattern: (json['defaultDatePattern'] as String?) ?? 'yyyy-MM-dd',
      defaultDateFirstYear: (json['defaultDateFirstYear'] as int?) ?? 1900,
      defaultDateLastYear: (json['defaultDateLastYear'] as int?) ?? 2100,
      defaultDateMode: DateFieldMode.values.firstWhere(
        (e) => e.name == (json['defaultDateMode'] as String? ?? 'dialog'),
        orElse: () => DateFieldMode.dialog,
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
  @override final bool captureErrors;
  @override final String? defaultAlias;
  @override final int? autoGenerateQueriesArgumentLimit;

  final String? autoGenerateQueriesDefaultAlias;
  final String? packageName;
  final String? appLocalizationsImport;
  final FlutterConfig? flutter;
  final bool immutableInputFields;
  final bool generateAdapters;
  final DartHttpAdapter httpAdapter;
  @override final AutoGenerateQueriesFor? autoGenerateQueriesFor;

  DartClientConfig({
    required this.generateAllFieldsFragments,
    required this.nullableFieldsRequired,
    required this.autoGenerateQueries,
    this.autoGenerateQueriesDefaultAlias,
    required this.operationNameAsParameter,
    this.captureErrors = false,
    this.defaultAlias,
    this.packageName,
    this.appLocalizationsImport,
    this.flutter,
    this.immutableInputFields = true,
    this.immutableTypeFields = true,
    this.generateAdapters = true,
    this.httpAdapter = DartHttpAdapter.http,
    this.autoGenerateQueriesFor,
    this.autoGenerateQueriesArgumentLimit = 200,
  });

  factory DartClientConfig.fromJson(Map<String, dynamic> json) {
    return DartClientConfig(
      generateAllFieldsFragments: (json['generateAllFieldsFragments'] as bool?) ?? true,
      nullableFieldsRequired: (json['nullableFieldsRequired'] as bool?) ?? false,
      autoGenerateQueries: (json['autoGenerateQueries'] as bool?) ?? true,
      autoGenerateQueriesDefaultAlias: json['autoGenerateQueriesDefaultAlias'] as String?,
      operationNameAsParameter: (json['operationNameAsParameter'] as bool?) ?? false,
      captureErrors: (json['captureErrors'] as bool?) ?? false,
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
      autoGenerateQueriesFor: json['autoGenerateQueriesFor'] != null
          ? AutoGenerateQueriesFor.fromJson(json['autoGenerateQueriesFor'] as Map<String, dynamic>)
          : null,
      autoGenerateQueriesArgumentLimit: json['autoGenerateQueriesArgumentLimit'] as int? ?? 200,
    );
  }
}

class JavaClientConfig extends ClientLanguageConfig {
  @override final bool generateAllFieldsFragments;
  @override final bool nullableFieldsRequired;
  @override final bool autoGenerateQueries;
  @override final bool operationNameAsParameter;
  @override final bool immutableTypeFields;
  @override final bool captureErrors;
  @override final String? defaultAlias;
  @override final int? autoGenerateQueriesArgumentLimit;

  final String packageName;
  final bool immutableInputFields;
  final bool inputAsRecord;
  final bool typeAsRecord;
  final bool jspecify;
  final JavaWsAdapter wsAdapter;
  final JavaJsonCodec jsonCodec;
  final JavaAsyncStyle asyncStyle;
  final JavaReactiveHttpClient reactiveHttpClient;
  @override final AutoGenerateQueriesFor? autoGenerateQueriesFor;

  JavaClientConfig({
    required this.packageName,
    this.generateAllFieldsFragments = true,
    this.nullableFieldsRequired = false,
    this.autoGenerateQueries = true,
    this.operationNameAsParameter = false,
    this.captureErrors = false,
    this.immutableInputFields = true,
    this.immutableTypeFields = true,
    this.inputAsRecord = false,
    this.typeAsRecord = false,
    this.jspecify = false,
    this.wsAdapter = JavaWsAdapter.java11,
    this.jsonCodec = JavaJsonCodec.jackson,
    this.asyncStyle = JavaAsyncStyle.blocking,
    this.reactiveHttpClient = JavaReactiveHttpClient.jdk,
    this.defaultAlias,
    this.autoGenerateQueriesFor,
    this.autoGenerateQueriesArgumentLimit = 200,
  });

  factory JavaClientConfig.fromJson(Map<String, dynamic> json) {
    return JavaClientConfig(
      packageName: json['packageName'] as String,
      generateAllFieldsFragments: (json['generateAllFieldsFragments'] as bool?) ?? true,
      nullableFieldsRequired: (json['nullableFieldsRequired'] as bool?) ?? false,
      autoGenerateQueries: (json['autoGenerateQueries'] as bool?) ?? true,
      operationNameAsParameter: (json['operationNameAsParameter'] as bool?) ?? false,
      captureErrors: (json['captureErrors'] as bool?) ?? false,
      immutableInputFields: (json['immutableInputFields'] as bool?) ?? true,
      immutableTypeFields: (json['immutableTypeFields'] as bool?) ?? true,
      inputAsRecord: (json['inputAsRecord'] as bool?) ?? false,
      typeAsRecord: (json['typeAsRecord'] as bool?) ?? false,
      jspecify: (json['jspecify'] as bool?) ?? false,
      defaultAlias: json['defaultAlias'] as String?,
      wsAdapter: JavaWsAdapter.values.firstWhere(
        (e) => e.name == json['wsAdapter'],
        orElse: () => JavaWsAdapter.java11,
      ),
      jsonCodec: JavaJsonCodec.values.firstWhere(
        (e) => e.name == json['jsonCodec'],
        orElse: () => JavaJsonCodec.jackson,
      ),
      asyncStyle: JavaAsyncStyle.values.firstWhere(
        (e) => e.name == json['asyncStyle'],
        orElse: () => JavaAsyncStyle.blocking,
      ),
      reactiveHttpClient: JavaReactiveHttpClient.values.firstWhere(
        (e) => e.name == json['reactiveHttpClient'],
        orElse: () => JavaReactiveHttpClient.jdk,
      ),
      autoGenerateQueriesFor: json['autoGenerateQueriesFor'] != null
          ? AutoGenerateQueriesFor.fromJson(json['autoGenerateQueriesFor'] as Map<String, dynamic>)
          : null,
      autoGenerateQueriesArgumentLimit: json['autoGenerateQueriesArgumentLimit'] as int? ?? 200,
    );
  }
}

class TypeScriptClientConfig extends ClientLanguageConfig {
  @override final bool generateAllFieldsFragments;
  @override final bool autoGenerateQueries;
  @override final bool operationNameAsParameter;
  @override final bool immutableTypeFields;
  @override final bool captureErrors;
  @override final String? defaultAlias;
  @override final int? autoGenerateQueriesArgumentLimit;

  final bool optionalNullableInputFields;
  final bool generateDefaultWsAdapter;
  final bool observables;
  final TypeScriptHttpAdapter httpAdapter;
  @override final AutoGenerateQueriesFor? autoGenerateQueriesFor;

  TypeScriptClientConfig({
    this.generateAllFieldsFragments = true,
    this.autoGenerateQueries = true,
    this.operationNameAsParameter = false,
    this.immutableTypeFields = true,
    this.captureErrors = false,
    this.optionalNullableInputFields = true,
    this.generateDefaultWsAdapter = true,
    this.observables = false,
    this.httpAdapter = TypeScriptHttpAdapter.fetch,
    this.defaultAlias,
    this.autoGenerateQueriesFor,
    this.autoGenerateQueriesArgumentLimit = 200,
  });

  factory TypeScriptClientConfig.fromJson(Map<String, dynamic> json) {
    return TypeScriptClientConfig(
      generateAllFieldsFragments: (json['generateAllFieldsFragments'] as bool?) ?? true,
      autoGenerateQueries: (json['autoGenerateQueries'] as bool?) ?? true,
      operationNameAsParameter: (json['operationNameAsParameter'] as bool?) ?? false,
      immutableTypeFields: (json['immutableTypeFields'] as bool?) ?? true,
      captureErrors: (json['captureErrors'] as bool?) ?? false,
      optionalNullableInputFields: (json['optionalNullableInputFields'] as bool?) ?? true,
      generateDefaultWsAdapter: (json['generateDefaultWsAdapter'] as bool?) ?? true,
      observables: (json['observables'] as bool?) ?? false,
      httpAdapter: TypeScriptHttpAdapter.values.firstWhere(
        (e) => e.name == json['httpAdapter'],
        orElse: () => TypeScriptHttpAdapter.fetch,
      ),
      defaultAlias: json['defaultAlias'] as String?,
      autoGenerateQueriesFor: json['autoGenerateQueriesFor'] != null
          ? AutoGenerateQueriesFor.fromJson(json['autoGenerateQueriesFor'] as Map<String, dynamic>)
          : null,
      autoGenerateQueriesArgumentLimit: json['autoGenerateQueriesArgumentLimit'] as int? ?? 200,
    );
  }
}

class KotlinClientConfig extends ClientLanguageConfig {
  @override final bool generateAllFieldsFragments;
  @override final bool nullableFieldsRequired;
  @override final bool autoGenerateQueries;
  @override final bool operationNameAsParameter;
  @override final bool immutableTypeFields;
  @override final bool captureErrors;
  @override final String? defaultAlias;
  @override final int? autoGenerateQueriesArgumentLimit;

  final String packageName;
  final bool inputAsDataClass;
  final bool typeAsDataClass;
  final KotlinWsAdapter wsAdapter;
  @override final AutoGenerateQueriesFor? autoGenerateQueriesFor;

  KotlinClientConfig({
    required this.packageName,
    this.generateAllFieldsFragments = true,
    this.nullableFieldsRequired = false,
    this.autoGenerateQueries = true,
    this.operationNameAsParameter = false,
    this.captureErrors = false,
    this.immutableTypeFields = true,
    this.inputAsDataClass = true,
    this.typeAsDataClass = true,
    this.wsAdapter = KotlinWsAdapter.okhttp,
    this.defaultAlias,
    this.autoGenerateQueriesFor,
    this.autoGenerateQueriesArgumentLimit = 200,
  });

  factory KotlinClientConfig.fromJson(Map<String, dynamic> json) {
    return KotlinClientConfig(
      packageName: json['packageName'] as String,
      generateAllFieldsFragments: (json['generateAllFieldsFragments'] as bool?) ?? true,
      nullableFieldsRequired: (json['nullableFieldsRequired'] as bool?) ?? false,
      autoGenerateQueries: (json['autoGenerateQueries'] as bool?) ?? true,
      operationNameAsParameter: (json['operationNameAsParameter'] as bool?) ?? false,
      captureErrors: (json['captureErrors'] as bool?) ?? false,
      immutableTypeFields: (json['immutableTypeFields'] as bool?) ?? true,
      inputAsDataClass: (json['inputAsDataClass'] as bool?) ?? true,
      typeAsDataClass: (json['typeAsDataClass'] as bool?) ?? true,
      defaultAlias: json['defaultAlias'] as String?,
      wsAdapter: KotlinWsAdapter.values.firstWhere(
        (e) => e.name == json['wsAdapter'],
        orElse: () => KotlinWsAdapter.okhttp,
      ),
      autoGenerateQueriesFor: json['autoGenerateQueriesFor'] != null
          ? AutoGenerateQueriesFor.fromJson(json['autoGenerateQueriesFor'] as Map<String, dynamic>)
          : null,
      autoGenerateQueriesArgumentLimit: json['autoGenerateQueriesArgumentLimit'] as int? ?? 200,
    );
  }
}
