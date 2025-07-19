import 'dart:async';
import 'dart:io';

import 'package:retrofit_graphql/src/config.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/serializers/dart_client_serializer.dart';
import 'package:retrofit_graphql/src/serializers/dart_serializer.dart';
import 'package:retrofit_graphql/src/serializers/gq_serializer.dart';
import 'package:retrofit_graphql/src/serializers/java_serializer.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:petitparser/petitparser.dart';
import 'package:retrofit_graphql/src/serializers/spring_server_serializer.dart';
import 'package:args/args.dart';
import 'dart:convert';

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
  final watchedFiles = config.schemaPaths.map((p) => File(p)).toList();
  final lastModifiedMap = <String, DateTime>{};

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
    for (var file in watchedFiles) {
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
  });
}

void handleGeneration(GeneratorConfig config) async {
  stdout.writeln("Generating classes");
  StringBuffer sb = StringBuffer();
  for (var path in config.schemaPaths) {
    var file = File(path);
    if (!await file.exists()) {
      stderr.writeln('❌ Schema file "$path" not found');
      exit(1);
    } else {
      sb.write(file.readAsStringSync());
      sb.write("\n");
    }
  }

  final grammar = createGrammar(config);
  var gqParser = grammar.buildFrom(grammar.fullGrammar().end());
  try {
    gqParser.parse(sb.toString());
    var mode = config.getMode();
    if (mode == CodeGenerationMode.server) {
      generateServerClasses(grammar, config);
    } else if (mode == CodeGenerationMode.client) {
      generateClientClasses(grammar, config);
    }
  } catch (ex, st) {
    // ignore parse errors
    stderr.writeln(st);
  }
}

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

void generateClientClasses(GQGrammar grammar, GeneratorConfig config) async {
  final GqSerializer serializer = DartSerializer(grammar);
  final dcs = DartClientSerializer(grammar);
  final inputs = dcs.serializeInputs(serializer);
  final enums = dcs.generateEnums(serializer);
  final types = dcs.generateTypes(serializer);
  final client = dcs.serializeClient();
  var outputDir = config.outputDir;
  await File('$outputDir/$inputsFileName.dart').writeAsString(inputs);
  await File('$outputDir/$enumsFileName.dart').writeAsString(enums);
  await File('$outputDir/$typesFileName.dart').writeAsString(types);
  await File('$outputDir/$clientFileName.dart').writeAsString(client);
}

void generateServerClasses(GQGrammar grammar, GeneratorConfig config) {
  final packageName = config.serverConfig!.spring!.basePackage;
  final destinationDir = config.outputDir;
  final serialzer = JavaSerializer(grammar);
  final springSeriaalizer = SpringServerSerializer(grammar);
  grammar.getSerializableTypes().forEach((def) {
    var text = serialzer.serializeTypeDefinition(def);
    writeToFile(
        data: text,
        fileName: "${def.token}.java",
        subpackage: "types",
        imports: ["$packageName.enums", "$packageName.interfaces"],
        destinationDir: destinationDir,
        packageName: packageName);
  });
  grammar.interfaces.forEach((k, def) {
    var text = serialzer.serializeInterface(def);
    writeToFile(
        data: text,
        fileName: "$k.java",
        subpackage: "interfaces",
        imports: ["$packageName.enums", "$packageName.types"],
        destinationDir: destinationDir,
        packageName: packageName);
  });
  grammar.enums.forEach((k, def) {
    var text = serialzer.serializeEnumDefinition(def);
    writeToFile(
        data: text,
        fileName: "$k.java",
        subpackage: "enums",
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName);
  });
  grammar.inputs.forEach((k, def) {
    var text = serialzer.serializeInputDefinition(def);
    writeToFile(
        data: text,
        fileName: "$k.java",
        subpackage: "inputs",
        imports: ["$packageName.enums"],
        destinationDir: destinationDir,
        packageName: packageName);
  });

  grammar.services.forEach((k, def) {
    var text = springSeriaalizer.serializeService(def);
    writeToFile(
        data: text,
        fileName: "$k.java",
        subpackage: "services",
        imports: ["$packageName.enums", "$packageName.types", "$packageName.inputs"],
        destinationDir: destinationDir,
        packageName: packageName);
  });

  grammar.services.forEach((k, def) {
    var text = springSeriaalizer.serializeController(def);
    writeToFile(
        data: text,
        fileName: "${k}Controller.java",
        subpackage: "controllers",
        imports: ["$packageName.enums", "$packageName.types", "$packageName.inputs", "$packageName.services"],
        destinationDir: destinationDir,
        packageName: packageName);
  });

  grammar.repositories.forEach((k, def) {
    var text = springSeriaalizer.serializeRepository(def);
    writeToFile(
        data: text,
        fileName: "${k}.java",
        subpackage: "repositories",
        imports: ["$packageName.enums", "$packageName.types"],
        destinationDir: destinationDir,
        packageName: packageName);
  });
}

void writeToFile(
    {required String data,
    required String fileName,
    required String subpackage,
    required List<String> imports,
    required String destinationDir,
    required String packageName}) {
  var file = File("$destinationDir/$subpackage/$fileName");
  if (!file.existsSync()) {
    file.createSync(recursive: true);
  }
  var importsText = imports.map((i) => "import $i.*;").join("\n");
  file.writeAsStringSync("""
package $packageName.$subpackage;

$importsText

$data
""");
  stdout.writeln("$fileName created");
}
