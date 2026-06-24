import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/generators/dart_client_generator.dart';
import 'package:graphlink/src/generators/java_client_generator.dart';
import 'package:graphlink/src/generators/kotlin_client_generator.dart';
import 'package:graphlink/src/generators/server_generator.dart';
import 'package:graphlink/src/generators/typescript_client_generator.dart';
import 'package:graphlink/src/gl_grammar_io.dart' as grammar_io;
import 'package:graphlink/src/grammar_factory.dart';
import 'package:graphlink/src/io_utils.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/utils.dart';
import 'package:yaml/yaml.dart';

export 'package:graphlink/src/generators/dart_client_generator.dart' show generateDartClientClasses;
export 'package:graphlink/src/generators/java_client_generator.dart' show generateJavaClientClasses;
export 'package:graphlink/src/generators/kotlin_client_generator.dart' show generateKotlinClientClasses;
export 'package:graphlink/src/generators/server_generator.dart' show generateServerClasses;
export 'package:graphlink/src/generators/typescript_client_generator.dart' show generateTypeScriptClientClasses;
export 'package:graphlink/src/config.dart' show KotlinClientConfig, KotlinWsAdapter;
export 'package:graphlink/src/grammar_factory.dart' show createGrammar, buildExtraGql;
export 'package:graphlink/src/io_utils.dart' show writeToFile, cleanUpObsoleteFiles;

extension on YamlMap {
  Map<String, dynamic> toMap() => Map.fromEntries(
        entries.map((e) => MapEntry(e.key as String, _convertYaml(e.value))),
      );
}

dynamic _convertYaml(dynamic value) {
  if (value is YamlMap) return value.toMap();
  if (value is YamlList) return value.map(_convertYaml).toList();
  return value;
}

const String appVersion =
    String.fromEnvironment('version', defaultValue: 'dev');

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'config',
      abbr: 'c',
      help: 'Path to the config file (.json, .yaml, or .yml)',
    )
    ..addFlag(
      'watch',
      abbr: 'w',
      help: 'Watch schema files for changes',
      negatable: false,
    )
    ..addFlag(
      'version',
      abbr: 'v',
      help: 'Print version',
      negatable: false,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Show this help message',
      negatable: false,
    );

  final args = parser.parse(arguments);

  final watch = args['watch'] as bool;

  if (args['version'] as bool) {
    stdout.writeln('glink v$appVersion');
    exit(0);
  }

  if (args['help'] as bool) {
    stdout.write('''
Usage: glink [-c <config>] [options]

Options:
${parser.usage}

If -c is omitted, glink searches for glink.json, glink.yaml, or glink.yml
starting from the current directory and walking up to the filesystem root.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 config reference  (JSON, YAML, and YML are all accepted)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Top-level
  schemaPaths      string[]  Glob patterns for schema files
                             e.g. ["schema/*.gql"]
  mode             string    "client" or "server"
  outputDir        string    Directory where files are generated
  typeMappings     object    Scalar → language type mappings
                             e.g. { "ID": "String", "Float": "Double" }
  unknownScalarType string   Target type for custom scalars not in typeMappings
                             e.g. "String" (Dart), "string" (TS), "Object" (Java)
  identityFields   string[]  Fields used for equals/hashCode  e.g. ["id"]

━━ mode: client ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

clientConfig.dart
  packageName                     string  Dart package name used in imports
  generateAllFieldsFragments      bool    Generate _all_fields fragments          [false]
  nullableFieldsRequired          bool    Nullable fields required in ctors       [false]
  autoGenerateQueries             bool    Auto-generate queries from schema        [false]
  autoGenerateQueriesDefaultAlias string  Default alias for auto-generated queries
  operationNameAsParameter        bool    Pass operation name as a parameter      [false]
  flutter.generateTypes           bool    Generate Flutter UI type widgets        [true]
  flutter.generateInputs          bool    Generate Flutter UI input widgets       [false]
  flutter.typesToSkip             list    Type names to exclude from UI gen       []
  flutter.defaultGap              number  Default spacing between field rows      [16]
  immutableInputFields            bool    Generate input fields as final          [true]
  immutableTypeFields             bool    Generate type fields as final           [true]

clientConfig.java
  packageName                     string  Java package name (required)
  generateAllFieldsFragments      bool    Generate _all_fields fragments          [false]
  nullableFieldsRequired          bool    Nullable fields required                [false]
  autoGenerateQueries             bool    Auto-generate queries from schema        [false]
  operationNameAsParameter        bool    Pass operation name as a parameter      [false]
  immutableInputFields            bool    Generate input fields as final          [true]
  immutableTypeFields             bool    Generate type fields as final           [true]
  inputAsRecord                   bool    Generate inputs as Java records         [false]
  typeAsRecord                    bool    Generate types as Java records          [false]

clientConfig.kotlin
  packageName                     string  Kotlin package name (required)
  generateAllFieldsFragments      bool    Generate _all_fields fragments          [true]
  nullableFieldsRequired          bool    Nullable fields required in ctors       [false]
  autoGenerateQueries             bool    Auto-generate queries from schema        [true]
  operationNameAsParameter        bool    Pass operation name as a parameter      [false]
  captureErrors                   bool    Return full response including errors   [false]
  inputAsDataClass                bool    Generate inputs as data class           [true]
  typeAsDataClass                 bool    Generate types as data class            [true]
  wsAdapter                       string  WS adapter: "okhttp" | "none"          [okhttp]

clientConfig.typescript
  generateAllFieldsFragments      bool    Generate _all_fields fragments          [false]
  autoGenerateQueries             bool    Auto-generate queries from schema        [false]
  autoGenerateQueriesDefaultAlias string  Default alias for auto-generated queries
  operationNameAsParameter        bool    Pass operation name as a parameter      [false]
  immutableTypeFields             bool    Generate type fields as final           [true]
  optionalNullableInputFields     bool    Nullable input fields are optional      [true]
  generateDefaultWsAdapter        bool    Generate default WebSocket adapter      [true]
  observables                     bool    Use RxJS observables instead of promises [false]
  httpAdapter                     string  HTTP adapter: "fetch" | "axios" | "none" [fetch]

━━ mode: server ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

serverConfig.spring
  basePackage           string  Java base package name (required)
  generateControllers   bool    Generate Spring controllers                       [true]
  generateInputs        bool    Generate input classes                            [true]
  generateTypes         bool    Generate type classes                             [true]
  generateRepositories  bool    Generate repository interfaces                    [false]
  inputAsRecord         bool    Generate inputs as Java records                   [false]
  typeAsRecord          bool    Generate types as Java records                    [false]
  generateSchema        bool    Copy schema file to outputDir                     [false]
  schemaTargetPath      string  Target path for schema (required if generateSchema)
  injectDataFetching    bool    Inject @SchemaMapping data-fetching annotations   [false]
  immutableInputFields  bool    Generate input fields as final                    [true]
  immutableTypeFields   bool    Generate type fields as final                     [false]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''');
    exit(0);
  }

  final configPath = args['config'] as String? ?? _findDefaultConfig();
  if (configPath == null) {
    stdout.write('''
Usage: glink generate [options]

Options:
${parser.usage}
''');
    exit(1);
  }
  final configFile = File(configPath);

  if (!await configFile.exists()) {
    stderr.writeln('❌ Config file not found at: $configPath');
    exit(1);
  }

  final raw = await configFile.readAsString();
  Map<String, dynamic> json;
  try {
    final isYaml = configPath.endsWith('.yaml') || configPath.endsWith('.yml');
    if (isYaml) {
      json = (loadYaml(raw) as YamlMap).toMap();
    } else {
      json = jsonDecode(raw) as Map<String, dynamic>;
    }
  } on FormatException catch (e) {
    stderr.writeln('❌ Invalid JSON in $configPath: ${e.message}');
    exit(1);
  } catch (e) {
    stderr.writeln('❌ Failed to parse config $configPath: $e');
    exit(1);
  }

  late GeneratorConfig config;
  try {
    config = GeneratorConfig.fromJson(json);
    if (!['server', 'client'].contains(config.mode)) {
      stderr.writeln('❌ Error parsing config: mode must be one of "server" or "client"');
    }
  } catch (e) {
    stderr.writeln('❌ Error parsing config: $e');
    exit(1);
  }
  if (config.schemaPaths.isEmpty) {
    stderr.writeln('❌ schema_paths is empty, please provide at least one file');
    exit(1);
  }

  if (watch) {
    watchAndGenerate(config);
  } else {
    handleGeneration(config);
  }
}

String? _findDefaultConfig() {
  const candidates = ['glink.json', 'glink.yaml', 'glink.yml'];
  var dir = Directory.current;
  while (true) {
    for (final name in candidates) {
      final file = File('${dir.path}/$name');
      if (file.existsSync()) return file.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null; // filesystem root
    dir = parent;
  }
}

void watchAndGenerate(GeneratorConfig config) {
  final lastModifiedMap = <String, DateTime>{};

  List<File> resolveWatchedFiles() {
    final files = <File>{};
    for (final pattern in config.schemaPaths) {
      files.addAll(Glob(pattern).listSync().whereType<File>());
    }
    return files.toList();
  }

  final watchedFiles = resolveWatchedFiles();
  for (final file in watchedFiles) {
    if (file.existsSync()) {
      lastModifiedMap[file.path] = file.lastModifiedSync();
    } else {
      stderr.writeln('❌ Schema file "${file.path}" not found');
      exit(1);
    }
  }

  handleGeneration(config);

  Timer.periodic(const Duration(seconds: 1), (timer) {
    final currentFiles = resolveWatchedFiles();

    for (final file in currentFiles) {
      try {
        final newModified = file.lastModifiedSync();
        final prevModified = lastModifiedMap[file.path];
        if (prevModified == null || newModified.isAfter(prevModified)) {
          stdout.writeln('🔄 Detected change in: ${file.path}');
          lastModifiedMap[file.path] = newModified;
          handleGeneration(config);
          break;
        }
      } catch (_) {}
    }

    for (final file in currentFiles) {
      if (!lastModifiedMap.containsKey(file.path)) {
        stdout.writeln('🆕 New matching file detected: ${file.path}');
        lastModifiedMap[file.path] = file.lastModifiedSync();
        handleGeneration(config);
        break;
      }
    }
  });
}

void handleGeneration(GeneratorConfig config) async {
  resetWriteCount();
  final now = DateTime.now();
  final filePaths = <String>[];
  for (final pattern in config.schemaPaths) {
    final files = Glob(pattern).listSync().whereType<File>().toList();
    if (files.isEmpty) {
      stderr.writeln('❌ No schema files matched "$pattern"');
      exit(1);
    }
    filePaths.addAll(files.map((f) => f.path));
  }

  final grammar = createGrammar(config);
  try {
    final extra = buildExtraGql(grammar, config);
    final logicalFiles =
        await Future.wait(filePaths.map((p) => grammar_io.readLogicalFile(p)));
    grammar_io.parseFiles(grammar, logicalFiles, extraGql: extra);

    final mode = config.getMode();
    if (mode == CodeGenerationMode.server) {
      await generateServerClasses(grammar,  config, now);
    } else if (mode == CodeGenerationMode.client) {
      final lang = config.clientConfig!.language;
      if (lang is JavaClientConfig) {
        await generateJavaClientClasses(grammar, lang.packageName, config, now);
      } else if (lang is DartClientConfig) {
        await generateDartClientClasses(grammar, createPrifix(config.outputDir, lang.packageName ?? '') , config, now);
      } else if (lang is TypeScriptClientConfig) {
        await generateTypeScriptClientClasses(grammar, config, now);
      } else if (lang is KotlinClientConfig) {
        await generateKotlinClientClasses(grammar, lang.packageName, config, now);
      }
    }
    stdout.writeln('✅ $writeCount file(s) written.');
  } catch (ex, st) {
    stderr.writeln(ex);
    stderr.writeln(st);
  }
}
