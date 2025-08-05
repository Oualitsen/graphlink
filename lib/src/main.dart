import 'dart:async';
import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:retrofit_graphql/src/config.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/io_utils.dart';
import 'package:retrofit_graphql/src/serializers/dart_client_serializer.dart';
import 'package:retrofit_graphql/src/serializers/dart_serializer.dart';
import 'package:retrofit_graphql/src/serializers/gq_serializer.dart';
import 'package:retrofit_graphql/src/serializers/graphq_serializer.dart';
import 'package:retrofit_graphql/src/serializers/java_serializer.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:petitparser/petitparser.dart';
import 'package:retrofit_graphql/src/serializers/spring_server_serializer.dart';
import 'package:args/args.dart';
import 'dart:convert';

import 'package:retrofit_graphql/src/utils.dart';

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
    var result = await grammar.parseFiles(filePaths);
    var failures = result.whereType<Failure>().toList();
    if(failures.isNotEmpty) {
      
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
      await generateClientClasses(grammar, config, now);
    }
  } catch (ex, st) {
    // ignore parse errors
    stderr.writeln(st);
    throw ex;
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

 Future<void> generateClientClasses(GQGrammar grammar, GeneratorConfig config, DateTime started) async {
  final GqSerializer serializer = DartSerializer(grammar);
  final dcs = DartClientSerializer(grammar);
  
  var outputDir = config.outputDir;
  var futures = [
    saveSource(data: dcs.generateInputs(serializer), path: '$outputDir/$inputsFileName.dart'),
    saveSource(data: dcs.generateEnums(serializer), path: '$outputDir/$enumsFileName.dart'),
    saveSource(data: dcs.generateTypes(serializer), path: '$outputDir/$typesFileName.dart'),
    saveSource(data: dcs.generateClient(), path: '$outputDir/$clientFileName.dart'),
  ];
  await Future.wait(futures);
  stdout.writeln("Generated client in ${formatElapsedTime(started)}");
}

Future<Set<String>> generateServerClasses(GQGrammar grammar, GeneratorConfig config, DateTime started) async {
  final springConfig = config.serverConfig!.spring!;
  final packageName = springConfig.basePackage;
  final destinationDir = config.outputDir;
  final serialzer = JavaSerializer(grammar, inputsAsRecords: config.serverConfig?.spring?.inputAsRecord ?? false,
  typesAsRecords: config.serverConfig?.spring?.typeAsRecord ?? false);
  final springSerializer = SpringServerSerializer(grammar, javaSerializer: serialzer, generateSchema: springConfig.generateSchema);
  final List<Future<File>> futures = [];

  grammar.getSerializableTypes().forEach((def) {
    var text = serialzer.serializeTypeDefinition(def);
    var r = writeToFile(
        data: text,
        fileName: "${def.tokenInfo}.java",
        subpackage: "types",
        imports: ["$packageName.enums", "$packageName.interfaces"],
        destinationDir: destinationDir,
        packageName: packageName);
    futures.add(r);
  });
  grammar.interfaces.forEach((k, def) {
    var text = serialzer.serializeInterface(def);
    var r = writeToFile(
        data: text,
        fileName: "$k.java",
        subpackage: "interfaces",
        imports: ["$packageName.enums", "$packageName.types"],
        destinationDir: destinationDir,
        packageName: packageName);
    futures.add(r);
  });
  grammar.enums.forEach((k, def) {
    var text = serialzer.serializeEnumDefinition(def);
    var r = writeToFile(
        data: text,
        fileName: "$k.java",
        subpackage: "enums",
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName);
    futures.add(r);
  });
  grammar.inputs.forEach((k, def) {
    var text = serialzer.serializeInputDefinition(def);
    var r = writeToFile(
        data: text,
        fileName: "$k.java",
        subpackage: "inputs",
        imports: ["$packageName.enums"],
        destinationDir: destinationDir,
        packageName: packageName);
    futures.add(r);
  });

  grammar.services.forEach((k, def) {
    var text = springSerializer.serializeService(def);
    var r = writeToFile(
        data: text,
        fileName: "$k.java",
        subpackage: "services",
        imports: ["$packageName.enums", "$packageName.types", "$packageName.inputs"],
        destinationDir: destinationDir,
        packageName: packageName);
    futures.add(r);
  });

  grammar.services.forEach((k, def) {
    var text = springSerializer.serializeController(def);
    var r = writeToFile(
        data: text,
        fileName: "${k}Controller.java",
        subpackage: "controllers",
        imports: ["$packageName.enums", "$packageName.types", "$packageName.inputs", "$packageName.services"],
        destinationDir: destinationDir,
        packageName: packageName);
    futures.add(r);
  });

  grammar.repositories.forEach((k, def) {
    var text = springSerializer.serializeRepository(def);
    var r = writeToFile(
        data: text,
        fileName: "${k}.java",
        subpackage: "repositories",
        imports: ["$packageName.enums", "$packageName.types"],
        destinationDir: destinationDir,
        packageName: packageName);
    futures.add(r);
  });
  if(springConfig.generateSchema) {
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
  var filesToDelete = paths
  .map((p) => File(p)).map((f) => f.delete());
  await Future.wait(filesToDelete);
  _lastGeneratedFiles.clear();
  _lastGeneratedFiles.addAll(newFiles);
}

Future<File> writeToFile(
    {required String data,
    required String fileName,
    required String subpackage,
    required List<String> imports,
    required String destinationDir,
    required String packageName}) {
      final path = "$destinationDir/$subpackage/$fileName";
  var importsText = imports.map((i) => "import $i.*;").join("\n");
  final source = """
package $packageName.$subpackage;

$importsText

$data
""";
return saveSource(data: source, path: path);

}


