import 'dart:async';
import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:retrofit_graphql/src/config.dart';
import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/io_utils.dart';
import 'package:retrofit_graphql/src/serializers/dart_client_serializer.dart';
import 'package:retrofit_graphql/src/serializers/dart_serializer.dart';
import 'package:retrofit_graphql/src/serializers/graphq_serializer.dart';
import 'package:retrofit_graphql/src/serializers/java_serializer.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:petitparser/petitparser.dart';
import 'package:retrofit_graphql/src/serializers/spring_server_serializer.dart';
import 'package:args/args.dart';
import 'dart:convert';

import 'package:retrofit_graphql/src/utils.dart';

const _clientTpes = {
  'GQPayload',
  'GQError',
  'GQErrorLocation',
  'GQSubscriptionPayload',
  'GQSubscriptionErrorMessage',
  'GQSubscriptionMessage'
};
const _clientInterfaces = {'GQSubscriptionErrorMessageBase'};
const _clientObjects = '''
scalar gqlMapStrObj @gqExternal(gqFQCN: "Map<String, dynamic>")
scalar dartDynamic @gqExternal(gqFQCN: "dynamic")

type GQPayload {
  query: String!
  operationName: String!
  variables: gqlMapStrObj!
}

type GQError {
  message: String!
  path: [dartDynamic!]
  extensions: gqlMapStrObj
  locations: [GQErrorLocation!]
}

type GQErrorLocation {
  line: Int!
  column: Int!
}



type GQSubscriptionPayload {
  query: String
  operationName: String
  variables: gqlMapStrObj
  data: gqlMapStrObj
}

enum GQAckStatus {none progress acknoledged }

interface GQSubscriptionErrorMessageBase {
  type: GQSubscriptionMessageType
  id: String
}

type GQSubscriptionErrorMessage implements GQSubscriptionErrorMessageBase {
  id: String
  type: GQSubscriptionMessageType
  payload: [GQError!]
}

type GQSubscriptionMessage implements GQSubscriptionErrorMessageBase {
  id: String
  type: GQSubscriptionMessageType
  payload: GQSubscriptionPayload
}

enum GQSubscriptionMessageType {
  connection_init connection_ack subscribe next complete error
}

''';
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'config',
      abbr: 'c',
      help: 'Path to the config file',
    )
    ..addFlag(
      'watch',
      abbr: 'w',
      help: 'Watch schema files for changes',
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

  if (args['help'] as bool) {
    stdout.write('''
Usage: gqlcodegen [options]

Options:
${parser.usage}
''');
    exit(0);
  }

  final configPath = args['config'] as String?;
  if (configPath == null) {
    stdout.write('''
Usage: gqlcodegen generate [options]

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
    json = jsonDecode(raw) as Map<String, dynamic>;
  } on FormatException catch (e) {
    stderr.writeln('❌ Invalid JSON in $configPath: ${e.message}');
    exit(1);
  }

  // 3) Parse into your config class
  late GeneratorConfig config;
  try {
    config = GeneratorConfig.fromJson(json);
    if (!["server", "client"].contains(config.mode)) {
      stderr.writeln('❌ Error parsing config: mode must be one of "server" or "client"');
    }
  } catch (e) {
    stderr.writeln('❌ Error parsing config: $e');
    exit(1);
  }
  config.typeMappings ??= {
    "ID": "String",
    "String": "String",
    "Float": "Double",
    "Int": "Integer",
    "Boolean": "Boolean",
    "Null": "null"
  };

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

void watchAndGenerate(GeneratorConfig config) {
  final lastModifiedMap = <String, DateTime>{};

  List<File> resolveWatchedFiles() {
    final files = <File>{};

    for (var pattern in config.schemaPaths) {
      final glob = Glob(pattern);
      final matched = glob.listSync().whereType<File>();
      files.addAll(matched);
    }

    return files.toList();
  }

  List<File> watchedFiles = resolveWatchedFiles();

  for (var file in watchedFiles) {
    if (file.existsSync()) {
      lastModifiedMap[file.path] = file.lastModifiedSync();
    } else {
      stderr.writeln('❌ Schema file "${file.path}" not found');
      exit(1);
    }
  }

  // Initial run
  handleGeneration(config);

  Timer.periodic(const Duration(seconds: 1), (timer) {
    final currentFiles = resolveWatchedFiles();

    for (var file in currentFiles) {
      try {
        final newModified = file.lastModifiedSync();
        final prevModified = lastModifiedMap[file.path];

        if (prevModified == null || newModified.isAfter(prevModified)) {
          stdout.writeln('🔄 Detected change in: ${file.path}');
          lastModifiedMap[file.path] = newModified;
          handleGeneration(config);
          break;
        }
      } catch (_) {
        // Ignore if file temporarily unavailable
      }
    }

    // Also check if new files were added that match the globs
    for (var file in currentFiles) {
      if (!lastModifiedMap.containsKey(file.path)) {
        stdout.writeln('🆕 New matching file detected: ${file.path}');
        lastModifiedMap[file.path] = file.lastModifiedSync();
        handleGeneration(config);
        break;
      }
    }

    watchedFiles = currentFiles;
  });
}

void handleGeneration(GeneratorConfig config) async {
  final now = DateTime.now();
  var filePaths = <String>[];
  for (var pattern in config.schemaPaths) {
    final glob = Glob(pattern);
    final files = glob.listSync().whereType<File>();

    if (files.isEmpty) {
      stderr.writeln('❌ No schema files matched "$pattern"');
      exit(1);
    }

    for (var file in files) {
      filePaths.add(file.path);
    }
  }

  final grammar = createGrammar(config);
  try {
    var extra = grammar.mode == CodeGenerationMode.client ? _clientObjects : null;
    var result = await grammar.parseFiles(filePaths, extraGql: extra);
    var failures = result.whereType<Failure>().toList();
    if (failures.isNotEmpty) {
      for (var f in failures) {
        stderr.writeln("at file ${grammar.lastParsedFile}: ${f.message}");
      }

      throw """
messasge: ${failures.first.message}
position: ${failures.first.position}
""";
    }

    var mode = config.getMode();
    if (mode == CodeGenerationMode.server) {
      await generateServerClasses(grammar, config, now);
    } else if (mode == CodeGenerationMode.client) {
      for (var type in _clientTpes) {
        grammar.projectedTypes[type] = grammar.getType(type.toToken());
      }

      for (var type in _clientInterfaces) {
        grammar.projectedTypes[type] = grammar.getType(type.toToken());
      }
      await generateClientClasses(grammar, config, now);
    }
  } catch (ex, st) {
    // ignore parse errors
    stderr.writeln(st);
    rethrow;
  }
}

final _lastGeneratedFiles = <String>{};

GQGrammar createGrammar(GeneratorConfig config) {
  var mode = config.getMode();
  if (mode == CodeGenerationMode.server) {
    return GQGrammar(mode: mode, typeMap: config.typeMappings!, identityFields: config.identityFields);
  } else {
    var clientConfig = config.clientConfig;

    return GQGrammar(
      mode: mode,
      typeMap: config.typeMappings!,
      identityFields: config.identityFields,
      generateAllFieldsFragments: clientConfig?.generateAllFieldsFragments ?? false,
      nullableFieldsRequired: clientConfig?.nullableFieldsRequired ?? false,
      autoGenerateQueries: clientConfig?.autoGenerateQueries ?? false,
      defaultAlias: clientConfig?.defaultAlias,
      operationNameAsParameter: clientConfig?.operationNameAsParameter ?? false,
    );
  }
}

Future<Set<String>> generateClientClasses(GQGrammar grammar, GeneratorConfig config, DateTime started) async {
  final DartSerializer serializer = DartSerializer(grammar);
  final dcs = DartClientSerializer(grammar, serializer);
  final fileExtension = dcs.fileExtension;
  final List<Future<File>> futures = [];
  final destinationDir = config.outputDir;

  var enumFiles = grammar.enums.values.map((e) => "'../enums/${e.token}${fileExtension}'").toSet();
  var inputFiles = grammar.inputs.values.map((e) => "'../inputs/${e.token}${fileExtension}'").toSet();
  var typeFiles = grammar.projectedTypes.values.map((e) => "'../types/${e.token}${fileExtension}'").toSet();

  grammar.enums.forEach((k, def) {
    var text = serializer.serializeEnumDefinition(def);
    var r = writeToFile(
      data: text,
      fileName: "${k}${fileExtension}",
      subdir: "enums",
      imports: enumFiles,
      destinationDir: destinationDir,
    );
    futures.add(r);
  });

  grammar.inputs.forEach((k, def) {
    var text = serializer.serializeInputDefinition(def);
    var r = writeToFile(
        data: text,
        fileName: "$k${fileExtension}",
        subdir: "inputs",
        imports: [...enumFiles, ...inputFiles],
        destinationDir: destinationDir);
    futures.add(r);
  });

  grammar.projectedTypes.forEach((k, def) {
    var text = serializer.serializeTypeDefinition(def);
    var r = writeToFile(
        data: text,
        fileName: "$k${fileExtension}",
        subdir: "types",
        imports: [...enumFiles, ...inputFiles, ...typeFiles],
        destinationDir: destinationDir);
    futures.add(r);
  });

  String client = dcs.generateClient();
  var r = writeToFile(
      data: client,
      fileName: 'GQClient${fileExtension}',
      subdir: 'client',
      imports: [...enumFiles, ...inputFiles, ...typeFiles],
      destinationDir: destinationDir);
  futures.add(r);
  var result = await Future.wait(futures);
  stdout.writeln("Generated ${futures.length} files in ${formatElapsedTime(started)}");
  var paths = result.map((f) => f.path).toSet();
  await cleanUpObsoleteFiles(paths);
  return paths;
}

Future<Set<String>> generateServerClasses(GQGrammar grammar, GeneratorConfig config, DateTime started) async {
  final springConfig = config.serverConfig!.spring!;
  final packageName = springConfig.basePackage;
  final destinationDir = config.outputDir;
  final serializer = JavaSerializer(grammar,
      inputsAsRecords: config.serverConfig?.spring?.inputAsRecord ?? false,
      typesAsRecords: config.serverConfig?.spring?.typeAsRecord ?? false);
  final springSerializer =
      SpringServerSerializer(grammar, javaSerializer: serializer, generateSchema: springConfig.generateSchema);
  final List<Future<File>> futures = [];
  const fileExtension = ".java";

  grammar.getSerializableTypes().forEach((def) {
    var text = serializer.serializeTypeDefinition(def);
    var r = writeToFile(
        data: text,
        fileName: "${def.tokenInfo}${fileExtension}",
        subdir: "types",
        imports: [
          if (grammar.enums.isNotEmpty) "$packageName.enums",
          if (grammar.interfaces.isNotEmpty) "$packageName.interfaces"
        ],
        destinationDir: destinationDir,
        packageName: packageName,
        appendStar: true);
    futures.add(r);
  });
  grammar.interfaces.forEach((k, def) {
    var text = serializer.serializeInterface(def);
    var r = writeToFile(
        data: text,
        fileName: "$k${fileExtension}",
        subdir: "interfaces",
        imports: [
          if (grammar.enums.isNotEmpty) "$packageName.enums",
          if (grammar.types.isNotEmpty) "$packageName.types"
        ],
        destinationDir: destinationDir,
        packageName: packageName,
        appendStar: true);
    futures.add(r);
  });
  grammar.enums.forEach((k, def) {
    var text = serializer.serializeEnumDefinition(def);
    var r = writeToFile(
        data: text,
        fileName: "$k${fileExtension}",
        subdir: "enums",
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
        appendStar: true);
    futures.add(r);
  });
  grammar.inputs.forEach((k, def) {
    var text = serializer.serializeInputDefinition(def);
    var r = writeToFile(
        data: text,
        fileName: "$k${fileExtension}",
        subdir: "inputs",
        imports: [if (grammar.enums.isNotEmpty) "$packageName.enums"],
        destinationDir: destinationDir,
        packageName: packageName,
        appendStar: true);
    futures.add(r);
  });

  grammar.services.forEach((k, def) {
    var text = springSerializer.serializeService(def);
    var r = writeToFile(
        data: text,
        fileName: "$k${fileExtension}",
        subdir: "services",
        imports: [
          if (grammar.enums.isNotEmpty) "$packageName.enums",
          if (grammar.types.isNotEmpty) "$packageName.types",
          if (grammar.inputs.isNotEmpty) "$packageName.inputs",
          if (grammar.interfaces.isNotEmpty) "$packageName.interfaces",
        ],
        destinationDir: destinationDir,
        packageName: packageName,
        appendStar: true);
    futures.add(r);
  });

  grammar.services.forEach((k, def) {
    var text = springSerializer.serializeController(def);
    var r = writeToFile(
        data: text,
        fileName: "${k}Controller${fileExtension}",
        subdir: "controllers",
        imports: [
          if (grammar.enums.isNotEmpty) "$packageName.enums",
          if (grammar.types.isNotEmpty) "$packageName.types",
          if (grammar.inputs.isNotEmpty) "$packageName.inputs",
          if (grammar.services.isNotEmpty) "$packageName.services",
          if (grammar.interfaces.isNotEmpty) "$packageName.interfaces",
        ],
        destinationDir: destinationDir,
        packageName: packageName,
        appendStar: true);
    futures.add(r);
  });

  grammar.repositories.forEach((k, def) {
    var text = springSerializer.serializeRepository(def);
    var r = writeToFile(
        data: text,
        fileName: "${k}${fileExtension}",
        subdir: "repositories",
        imports: [
          if (grammar.enums.isNotEmpty) "$packageName.enums",
          if (grammar.types.isNotEmpty) "$packageName.types"
        ],
        destinationDir: destinationDir,
        packageName: packageName,
        appendStar: true);
    futures.add(r);
  });
  if (springConfig.generateSchema) {
    var text = GraphqSerializer(grammar).generateSchema();
    var r = saveSource(data: text, path: springConfig.schemaTargetPath!, graphqlSource: true);
    futures.add(r);
  }

  var result = await Future.wait(futures);
  stdout.writeln("Generated ${futures.length} files in ${formatElapsedTime(started)}");
  var paths = result.map((f) => f.path).toSet();
  await cleanUpObsoleteFiles(paths);
  return paths;
}

Future<void> cleanUpObsoleteFiles(Set<String> newFiles) async {
  var paths = _lastGeneratedFiles.where((path) => !newFiles.contains(path));
  stdout.writeln("Cleaning up ${paths.length} obsolete files");
  for (var p in paths) {
    stdout.writeln("Cleaning up ${p}");
  }
  var filesToDelete = paths.map((p) => File(p)).map((f) => f.delete());
  await Future.wait(filesToDelete);
  _lastGeneratedFiles.clear();
  _lastGeneratedFiles.addAll(newFiles);
}

Future<File> writeToFile(
    {required String data,
    required String fileName,
    required String subdir,
    required Iterable<String> imports,
    required String destinationDir,
    String? packageName,
    bool appendStar = false}) {
  final path = "$destinationDir/$subdir/$fileName";
  var buffer = StringBuffer();
  if (packageName != null) {
    buffer.writeln('package ${packageName}.${subdir};');
  }
  if (imports.isNotEmpty) {
    buffer.writeln(imports.map((i) => "import $i").map((e) {
      if (appendStar) {
        return '${e}.*;';
      } else {
        return '${e};';
      }
    }).join("\n"));
  }
  buffer.writeln(data);

  return saveSource(data: buffer.toString(), path: path);
}
