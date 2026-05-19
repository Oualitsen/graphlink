import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:logger/logger.dart';
import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/grammar_factory.dart';
import 'package:graphlink/src/generators/dart_client_generator.dart';
import 'package:yaml/yaml.dart';

/// Option keys that are not type mappings and must be excluded from [typeMappings].
const _knownOptions = {
  'packageName',
  'httpAdapter',
  'generateAdapters',
  'generateAllFieldsFragments',
  'autoGenerateQueries',
  'autoGenerateQueriesDefaultAlias',
  'defaultAlias',
  'operationNameAsParameter',
  'nullableFieldsRequired',
  'immutableInputFields',
  'immutableTypeFields',
  'flutter',
  'appLocalizationsImport',
  'identityFields',
  'disableCache',
};

/// A `build_runner` [Builder] that generates a fully typed GraphQL client
/// from `.graphql` / `.graphqls` schema files inside `lib/`.
///
/// GraphLink reads your GraphQL schema and emits:
///
/// - Typed response classes for every query, mutation, and subscription
/// - Input classes with immutable fields and named-parameter constructors
/// - Enum classes with `toJson` / `fromJson`
/// - A `GraphLinkClient` with `.queries`, `.mutations`, and `.subscriptions`
///   namespaces
/// - HTTP and WebSocket adapters (Dio or `package:http`)
///
/// This builder is normally invoked through `build_runner`. For project-wide
/// or CI generation the standalone `glink` CLI is recommended instead —
/// it supports JSON and YAML configs, watch mode, and multi-language targets.
///
/// ## Minimal `build.yaml`
///
/// ```yaml
/// targets:
///   $default:
///     builders:
///       graphlink|graphlinkGeneratorBuilder:
///         options:
///           packageName: my_app
///           generateAllFieldsFragments: true
///           autoGenerateQueries: true
/// ```
///
/// ## Supported options
///
/// | Option | Type | Default |
/// |---|---|---|
/// | `packageName` | `string` | — |
/// | `httpAdapter` | `"http"` \| `"dio"` \| `"none"` | `"http"` |
/// | `generateAdapters` | `bool` | `true` |
/// | `generateAllFieldsFragments` | `bool` | `false` |
/// | `autoGenerateQueries` | `bool` | `false` |
/// | `autoGenerateQueriesDefaultAlias` | `string` | `null` |
/// | `defaultAlias` | `string` | `null` |
/// | `operationNameAsParameter` | `bool` | `false` |
/// | `nullableFieldsRequired` | `bool` | `false` |
/// | `immutableInputFields` | `bool` | `true` |
/// | `immutableTypeFields` | `bool` | `true` |
/// | `flutter` | `map` | `null` |
/// | `appLocalizationsImport` | `string` | `null` |
/// | `identityFields` | `string[]` | `[]` |
/// | `disableCache` | `bool` | `false` |
///
/// Any additional string entries are treated as scalar → Dart type mappings
/// (e.g. `ID: String`, `Float: double`). The GraphQL built-in scalars are
/// pre-seeded.
class GraphlinkGeneratorBuilder implements Builder {
  /// The raw `build.yaml` options passed to this builder.
  final BuilderOptions options;

  /// Logger used to report generation progress and errors.
  final logger = Logger();

  /// Glob that matches `.graphql` schema files under `lib/`.
  static final inputFiles = Glob('lib/**/*.graphql');

  /// Glob that matches `.graphqls` schema files under `lib/`.
  static final inputFiles2 = Glob('lib/**/*.graphqls');

  /// Creates a builder from the given [BuilderOptions].
  GraphlinkGeneratorBuilder(this.options);

  /// Output directory for generated Dart files.
  static const outputDir = 'lib/generated';

  /// Scalar-to-Dart type mappings, seeded with the GraphQL built-in scalars.
  /// Any unknown string entries in `build.yaml` options are merged in at build
  /// time, allowing custom scalars to be mapped without a separate config key.
  final typeMappings = <String, String>{
    "ID": "String",
    "String": "String",
    "Float": "double",
    "Int": "int",
    "Boolean": "bool",
    "Null": "null",
  };

  /// Resolved schema asset IDs collected during [initAssets].
  final List<AssetId> assets = [];

  @override
  Map<String, List<String>> get buildExtensions => {
        '.graphql': ['.gq.dart'],
      };

  /// Runs the GraphLink code generator for the current [BuildStep].
  ///
  /// Reads all `.graphql` / `.graphqls` files under `lib/`, parses the merged
  /// schema, and writes generated Dart files to [outputDir].
  @override
  Future<void> build(BuildStep buildStep) async {
    final now = DateTime.now();
    await initAssets(buildStep);

    // Merge any unknown string options into type mappings (custom scalars).
    options.config.entries
        .where((e) => e.value is String && !_knownOptions.contains(e.key))
        .forEach((e) => typeMappings[e.key] = e.value as String);

    final config = _buildConfig();
    final grammar = createGrammar(config);

    final schema = await readSchema(buildStep);
    grammar.parse(schema);

    await generateDartClientClasses(grammar, config, now);
  }

  /// Builds a [GeneratorConfig] from the current [options].
  GeneratorConfig _buildConfig() {
    bool b(String key, bool defaultValue) =>
        options.config[key] as bool? ?? defaultValue;
    String? s(String key) => options.config[key] as String?;

    final dartConfig = DartClientConfig(
      packageName: s('packageName'),
      httpAdapter: DartHttpAdapter.values.firstWhere(
        (e) => e.name == s('httpAdapter'),
        orElse: () => DartHttpAdapter.http,
      ),
      generateAdapters: b('generateAdapters', true),
      generateAllFieldsFragments: b('generateAllFieldsFragments', false),
      autoGenerateQueries: b('autoGenerateQueries', false),
      autoGenerateQueriesDefaultAlias: s('autoGenerateQueriesDefaultAlias'),
      defaultAlias: s('defaultAlias'),
      operationNameAsParameter: b('operationNameAsParameter', false),
      nullableFieldsRequired: b('nullableFieldsRequired', false),
      immutableInputFields: b('immutableInputFields', true),
      immutableTypeFields: b('immutableTypeFields', true),
      flutter: options.config['flutter'] is Map
          ? FlutterConfig.fromJson(
              Map<String, dynamic>.from(options.config['flutter'] as Map))
          : null,
      appLocalizationsImport: s('appLocalizationsImport'),
    );

    return GeneratorConfig(
      schemaPaths: [],
      mode: 'client',
      identityFields:
          (options.config['identityFields'] as YamlList?)?.cast<String>() ?? [],
      typeMappings: typeMappings,
      outputDir: outputDir,
      disableCache: options.config['disableCache'] as bool? ?? false,
      clientConfig: ClientConfig(dartConfig),
    );
  }

  /// Populates [assets] with all `.graphql` and `.graphqls` files found
  /// under `lib/` for the current [BuildStep].
  Future<void> initAssets(BuildStep buildStep) async {
    assets.clear();
    assets.addAll(await buildStep.findAssets(inputFiles).toList());
    assets.addAll(await buildStep.findAssets(inputFiles2).toList());
  }

  /// Reads and concatenates the contents of all schema [assets] into a single
  /// GraphQL document string.
  Future<String> readSchema(BuildStep buildStep) async {
    final contents =
        await Future.wait(assets.map((asset) => buildStep.readAsString(asset)));
    return contents.join('\n');
  }
}
