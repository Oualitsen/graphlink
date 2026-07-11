import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:graphlink/src/cli_help.dart';
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
    stdout.write(buildHelpText(parser.usage));
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
    await handleGeneration(config);
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

Future<void> handleGeneration(GeneratorConfig config) async {
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

    for (final skipped in grammar.skippedAutoQueries) {
      stderr.writeln(
        '⚠ Auto-generated ${skipped.type.name} "${skipped.name}" skipped: '
        '${skipped.count} propagated args exceed the limit of ${skipped.cap}. '
        'Write a custom query with a narrower selection, or raise '
        'autoGenerateQueriesArgumentLimit in your config.',
      );
    }

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
