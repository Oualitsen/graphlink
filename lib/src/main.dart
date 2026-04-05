import 'dart:async';
import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/io_utils.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/serializers/client_serializers/dart_client_serializer.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/serializers/client_serializers/java_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/flutter_type_widget_serializer.dart';
import 'package:graphlink/src/serializers/graphq_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/language.dart';
import 'package:graphlink/src/serializers/spring_server_serializer.dart';
import 'package:args/args.dart';
import 'dart:convert';

import 'package:graphlink/src/gl_grammar_io.dart' as grammar_io;
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/utils.dart';

const String appVersion =
    String.fromEnvironment('version', defaultValue: 'dev');

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
Usage: glink -c <config.json> [options]

Options:
${parser.usage}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 config.json reference
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Top-level
  schemaPaths      string[]  Glob patterns for schema files
                             e.g. ["schema/*.gql"]
  mode             string    "client" or "server"
  outputDir        string    Directory where files are generated
  typeMappings     object    Scalar → language type mappings
                             e.g. { "ID": "String", "Float": "Double" }
  identityFields   string[]  Fields used for equals/hashCode  e.g. ["id"]

━━ mode: client ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

clientConfig.dart
  packageName                     string  Dart package name used in imports
  generateAllFieldsFragments      bool    Generate _all_fields fragments          [false]
  nullableFieldsRequired          bool    Nullable fields required in ctors       [false]
  autoGenerateQueries             bool    Auto-generate queries from schema        [false]
  autoGenerateQueriesDefaultAlias string  Default alias for auto-generated queries
  operationNameAsParameter        bool    Pass operation name as a parameter      [false]
  generateUiTypes                 bool    Generate Flutter UI type widgets        [false]
  generateUiInputs                bool    Generate Flutter UI input widgets       [false]
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

  final configPath = args['config'] as String?;
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
      stderr.writeln(
          '❌ Error parsing config: mode must be one of "server" or "client"');
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
    var extra = _buildExtraGql(grammar, config);
    final logicalFiles =
        await Future.wait(filePaths.map((p) => grammar_io.readLogicalFile(p)));
    grammar_io.parseFiles(grammar, logicalFiles, extraGql: extra);

    var mode = config.getMode();
    if (mode == CodeGenerationMode.server) {
      await generateServerClasses(grammar, config, now);
    } else if (mode == CodeGenerationMode.client) {
      if (config.clientConfig?.java != null) {
        await generateJavaClientClasses(grammar, config, now);
      } else {
        await generateDartClientClasses(grammar, config, now);
      }
    }
  } catch (ex, st) {
    // ignore parse errors
    stderr.writeln(st);
    rethrow;
  }
}

final _lastGeneratedFiles = <String>{};

String? _buildExtraGql(GLParser parser, GeneratorConfig config) {
  if (parser.mode != CodeGenerationMode.client) return null;
  if (config.clientConfig?.java != null) {
    return [
      getClientObjects("Java"),
      javaJsonEncoderDecorder,
      javaClientAdapterNoParamSync,
      javaGraphLinkWebSocketAdapter,  // scalars only now, no interface
    ].join();
  }
  return getClientObjects("dart");
}

GLParser createGrammar(GeneratorConfig config) {
  var mode = config.getMode();
  if (mode == CodeGenerationMode.server) {
    return GLParser(
        mode: mode,
        typeMap: config.typeMappings!,
        identityFields: config.identityFields);
  } else {
    final dart = config.clientConfig?.dart;
    final java = config.clientConfig?.java;

    return GLParser(
      mode: mode,
      typeMap: config.typeMappings!,
      identityFields: config.identityFields,
      generateAllFieldsFragments: dart?.generateAllFieldsFragments ??
          java?.generateAllFieldsFragments ??
          false,
      nullableFieldsRequired:
          dart?.nullableFieldsRequired ?? java?.nullableFieldsRequired ?? false,
      autoGenerateQueries:
          dart?.autoGenerateQueries ?? java?.autoGenerateQueries ?? false,
      defaultAlias: dart?.defaultAlias,
      operationNameAsParameter: dart?.operationNameAsParameter ??
          java?.operationNameAsParameter ??
          false,
    );
  }
}

Future<Set<String>> generateDartClientClasses(
    GLParser parser, GeneratorConfig config, DateTime started,
    {String? pack, noClient = false}) async {
  final serializer = DartSerializer(parser, generateJsonMethods: true);
  final clientSerializer = DartClientSerializer(parser, serializer,
      generateAdapters: config.clientConfig?.dart?.generateAdapters ?? true,
      httpAdapter: config.clientConfig?.dart?.httpAdapter ?? DartHttpAdapter.http);
  final List<Future<File>> futures = [];
  final destinationDir = config.outputDir;
  final packageName = config.clientConfig?.dart?.packageName;
  final prefix =
      "package:${packageName}/${(pack ?? config.outputDir).replaceFirst("lib/", "")}";
  final viewSerializeer = FlutterTypeWidgetSerializer(parser, serializer, true);
  parser.enums.forEach((k, def) {
    var text = serializer.serializeEnumDefinition(def, "");
    var r = writeToFile(
      data: text,
      fileName: serializer.getFileNameFor(def),
      subdir: "enums",
      imports: [],
      destinationDir: destinationDir,
    );
    futures.add(r);
  });

  parser.inputs.forEach((k, def) {
    var text = serializer.serializeInputDefinition(def, prefix);
    var r = writeToFile(
        data: text,
        fileName: serializer.getFileNameFor(def),
        subdir: "inputs",
        imports: [],
        destinationDir: destinationDir);
    futures.add(r);
  });

  var allProjectedTypes = <String, GLTypeDefinition>{};
  allProjectedTypes.addAll(parser.projectedTypes);
  allProjectedTypes.addAll(parser.projectedInterfaces);
  allProjectedTypes.forEach((k, def) {
    final subdir = def is GLInterfaceDefinition ? "interfaces" : "types";

    var text = serializer.serializeTypeDefinition(def, prefix);
    var r = writeToFile(
        data: text,
        fileName: serializer.getFileNameFor(def),
        subdir: subdir,
        imports: [],
        destinationDir: destinationDir);
    futures.add(r);
  });
  if (config.clientConfig?.dart?.generateUiTypes ?? false) {
    parser.views.forEach((k, def) {
      var appLocImport = config.clientConfig?.dart?.appLocalizationsImport;
      // @TODO add an assertion here
      if (appLocImport != null) {
        def.addImport(appLocImport);
      }
      var text = viewSerializeer.serializeType(def, prefix);
      var r = writeToFile(
          data: text,
          fileName: serializer.getFileNameFor(def),
          subdir: "widgets",
          imports: [],
          destinationDir: destinationDir);
      futures.add(r);
    });
  }

  if (!noClient) {
    String client = clientSerializer.generateClient(prefix);
    var r = writeToFile(
        data: client,
        fileName: 'graph_link_client${clientSerializer.fileExtension}',
        subdir: 'client',
        imports: [],
        destinationDir: destinationDir);
    futures.add(r);

    if (parser.hasUploadMutations) {
      futures.add(writeToFile(
          data: clientSerializer.generateUploadsFile(),
          fileName: 'graph_link_uploads${clientSerializer.fileExtension}',
          subdir: 'client',
          imports: [],
          destinationDir: destinationDir));
    }

    if (config.clientConfig?.dart?.generateAdapters ?? true) {
      final httpAdapter = config.clientConfig?.dart?.httpAdapter ?? DartHttpAdapter.http;
      if (httpAdapter != DartHttpAdapter.none) {
        futures.add(writeToFile(
            data: httpAdapter == DartHttpAdapter.dio
                ? clientSerializer.generateDioAdapterFile()
                : clientSerializer.generateHttpAdapterFile(),
            fileName: httpAdapter == DartHttpAdapter.dio
                ? 'graph_link_dio_adapter${clientSerializer.fileExtension}'
                : 'graph_link_http_adapter${clientSerializer.fileExtension}',
            subdir: 'client',
            imports: [],
            destinationDir: destinationDir));
      }
      if (parser.hasSubscriptions) {
        futures.add(writeToFile(
            data: clientSerializer.generateDefaultWebSocketAdapterFile(),
            fileName: 'graph_link_websocket_adapter${clientSerializer.fileExtension}',
            subdir: 'client',
            imports: [],
            destinationDir: destinationDir));
      }
    }
  }
  var result = await Future.wait(futures);
  stdout.writeln(
      "Generated ${futures.length} files in ${formatElapsedTime(started)}");
  var paths = result.map((f) => f.path).toSet();
  await cleanUpObsoleteFiles(paths);
  return paths;
}

Future<Set<String>> generateJavaClientClasses(
    GLParser parser, GeneratorConfig config, DateTime started,
    {String? pack, noClient = false}) async {
  final javaClientConfig = config.clientConfig?.java;
  final serializer = JavaSerializer(
    parser,
    generateJsonMethods: true,
    immutableInputFields: javaClientConfig?.immutableInputFields ?? true,
    immutableTypeFields: javaClientConfig?.immutableTypeFields ?? true,
    inputsAsRecords: javaClientConfig?.inputAsRecord ?? false,
    typesAsRecords: javaClientConfig?.typeAsRecord ?? false,
  );
  final clientSerializer = JavaClientSerializer(parser, serializer);
  final List<Future<File>> futures = [];
  final destinationDir = config.outputDir;
  final packageName = config.clientConfig?.java?.packageName;
  final prefix = packageName ?? '';
  parser.enums.forEach((k, def) {
    var text = serializer.serializeEnumDefinition(def, "");
    var r = writeToFile(
      data: text,
      fileName: serializer.getFileNameFor(def),
      subdir: "enums",
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    );
    futures.add(r);
  });

  parser.inputs.forEach((k, def) {
    var text = serializer.serializeInputDefinition(def, prefix);
    var r = writeToFile(
      data: text,
      fileName: serializer.getFileNameFor(def),
      subdir: "inputs",
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    );
    futures.add(r);
  });

  var allProjectedTypes = <String, GLTypeDefinition>{};
  allProjectedTypes.addAll(parser.projectedTypes);
  allProjectedTypes.addAll(parser.projectedInterfaces);
  ['GraphLinkClientAdapter', 'GraphLinkJsonEncoder', 'GraphLinkJsonDecoder']
      .map((e) => parser.interfaces[e]!)
      .forEach((def) {
    allProjectedTypes[def.token] = def;
  });

  allProjectedTypes.forEach((k, def) {
    final subdir = def is GLInterfaceDefinition ? "interfaces" : "types";
    var text = serializer.serializeTypeDefinition(def, prefix);
    var r = writeToFile(
      data: text,
      fileName: serializer.getFileNameFor(def),
      subdir: subdir,
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    );
    futures.add(r);
  });

  final wsAdapter = config.clientConfig?.java?.wsAdapter ?? JavaWsAdapter.java11;
  final jsonCodec = config.clientConfig?.java?.jsonCodec ?? JavaJsonCodec.jackson;

  if (!noClient) {
    String client = clientSerializer.generateClient(prefix, hasDefaultAdapters: wsAdapter != JavaWsAdapter.none);
    var r = writeToFile(
      data: client,
      fileName: 'GraphLinkClient${clientSerializer.fileExtension}',
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    );
    futures.add(r);

    futures.add(writeToFile(
      data: clientSerializer.generateGraphLinkResolverBaseFile(prefix),
      fileName: 'GraphLinkResolverBase.java',
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
    for (var type in GLQueryType.values) {
      final content = clientSerializer.generateQueriesClassFile(type, prefix);
      if (content != null) {
        futures.add(writeToFile(
          data: content,
          fileName: '${clientSerializer.classNameFromType(type)}.java',
          subdir: 'client',
          imports: [],
          destinationDir: destinationDir,
          packageName: packageName,
        ));
      }
    }

    futures.add(writeToFile(
      data: clientSerializer.generateGraphLinkPartialQueryFile(prefix),
      fileName: 'GraphLinkPartialQuery.java',
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
    futures.add(writeToFile(
      data: clientSerializer.generateGraphLinkCacheEntryFile(),
      fileName: 'GraphLinkCacheEntry.java',
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
    futures.add(writeToFile(
      data: clientSerializer.generateGraphLinkTagEntryFile(),
      fileName: 'GraphLinkTagEntry.java',
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
    futures.add(writeToFile(
      data: clientSerializer.generateGraphLinkCacheStoreFile(),
      fileName: 'GraphLinkCacheStore.java',
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
    futures.add(writeToFile(
      data: clientSerializer.generateInMemoryGraphLinkCacheStoreFile(),
      fileName: 'InMemoryGraphLinkCacheStore.java',
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
    futures.add(writeToFile(
      data: clientSerializer.generateGraphLinkExceptionFile(prefix),
      fileName: clientSerializer.exceptionFileName,
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));

    if (wsAdapter != JavaWsAdapter.none) {
      futures.add(writeToFile(
        data: clientSerializer.generateDefaultClientAdapterFile(wsAdapter.name, prefix),
        fileName: 'DefaultGraphLinkClientAdapter.java',
        subdir: 'client',
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
      ));
    }

    if (jsonCodec != JavaJsonCodec.none) {
      futures.add(writeToFile(
        data: clientSerializer.generateJsonCodecFile(jsonCodec.name, prefix),
        fileName: jsonCodec == JavaJsonCodec.jackson
            ? 'JacksonGraphLinkJsonCodec.java'
            : 'GsonGraphLinkJsonCodec.java',
        subdir: 'client',
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
      ));
    }

    if (parser.hasSubscriptions) {
      futures.add(writeToFile(
        data: clientSerializer.generateWebSocketAdapterFile(),
        fileName: 'GraphLinkWebSocketAdapter.java',
        subdir: 'interfaces',
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
      ));
      futures.add(writeToFile(
        data: clientSerializer.generateSubscriptionListenerFile(),
        fileName: 'GraphLinkSubscriptionListener.java',
        subdir: 'client',
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
      ));
      futures.add(writeToFile(
        data: clientSerializer.generateGraphqlWsMessageTypesFile(),
        fileName: 'GraphqlWsMessageTypes.java',
        subdir: 'client',
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
      ));
      futures.add(writeToFile(
        data: clientSerializer.generateGraphLinkSubscriptionHandlerFile(prefix),
        fileName: 'GraphLinkSubscriptionHandler.java',
        subdir: 'client',
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
      ));
      if (wsAdapter != JavaWsAdapter.none) {
        futures.add(writeToFile(
          data: clientSerializer.generateDefaultWebSocketAdapterFile(wsAdapter.name, prefix),
          fileName: 'DefaultGraphLinkWebSocketAdapter.java',
          subdir: 'client',
          imports: [],
          destinationDir: destinationDir,
          packageName: packageName,
        ));
      }
    }
  }
  var result = await Future.wait(futures);
  stdout.writeln(
      "Generated ${futures.length} files in ${formatElapsedTime(started)}");
  var paths = result.map((f) => f.path).toSet();
  await cleanUpObsoleteFiles(paths);
  return paths;
}

Future<Set<String>> generateServerClasses(
    GLParser grammar, GeneratorConfig config, DateTime started) async {
  final springConfig = config.serverConfig!.spring!;
  final packageName = springConfig.basePackage;
  final destinationDir = config.outputDir;
  final serializer = JavaSerializer(
    grammar,
    inputsAsRecords: config.serverConfig?.spring?.inputAsRecord ?? false,
    typesAsRecords: config.serverConfig?.spring?.typeAsRecord ?? false,
    inputsCheckForNulls: true,
    typesCheckForNulls: grammar.mode == CodeGenerationMode.client,
    immutableInputFields: config.serverConfig?.spring?.immutableInputFields ?? true,
    immutableTypeFields: config.serverConfig?.spring?.immutableTypeFields?? false,
  );
  final springSerializer = SpringServerSerializer(grammar,
      javaSerializer: serializer,
      generateSchema: springConfig.generateSchema,
      injectDataFetching:
          config.serverConfig?.spring?.injectDataFetching ?? false);
  final List<Future<File>> futures = [];
  const fileExtension = ".java";

  grammar.getSerializableTypes().forEach((def) {
    var text = serializer.serializeTypeDefinition(def, packageName);
    var r = writeToFile(
        data: text,
        fileName: serializer.getFileNameFor(def),
        subdir: "types",
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
        appendStar: true);
    futures.add(r);
  });
  grammar.getSerializableInterfaces().forEach((def) {
    var text = serializer.serializeTypeDefinition(def, packageName);
    var r = writeToFile(
        data: text,
        fileName: serializer.getFileNameFor(def),
        subdir: "interfaces",
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
        appendStar: true);
    futures.add(r);
  });
  grammar.getSerializableEnums().forEach((def) {
    var text = serializer.serializeEnumDefinition(def, packageName);
    var r = writeToFile(
        data: text,
        fileName: serializer.getFileNameFor(def),
        subdir: "enums",
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
        appendStar: true);
    futures.add(r);
  });
  grammar.getSerializableInputs().forEach((def) {
    var text = serializer.serializeInputDefinition(def, packageName);
    var r = writeToFile(
        data: text,
        fileName: serializer.getFileNameFor(def),
        subdir: "inputs",
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
        appendStar: true);
    futures.add(r);
  });

  grammar.services.forEach((k, def) {
    var text = springSerializer.serializeService(def, packageName);
    var r = writeToFile(
        data: text,
        fileName: serializer.getFileNameFor(def),
        subdir: "services",
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
        appendStar: true);
    futures.add(r);
  });

  grammar.controllers.forEach((k, def) {
    var text = springSerializer.serializeController(def, packageName);
    var r = writeToFile(
        data: text,
        fileName: serializer.getFileNameFor(def),
        subdir: "controllers",
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
        appendStar: true);
    futures.add(r);
  });

  grammar.repositories.forEach((k, def) {
    var text = springSerializer.serializeRepository(def, packageName);
    var r = writeToFile(
        data: text,
        fileName: "${k}${fileExtension}",
        subdir: "repositories",
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
        appendStar: true);
    futures.add(r);
  });

  if (springConfig.generateSchema) {
    var text = GLGraphqSerializer(grammar).generateSchema();
    var r = saveSource(
        data: text, path: springConfig.schemaTargetPath!, graphqlSource: true);
    futures.add(r);
  }

  var result = await Future.wait(futures);
  stdout.writeln(
      "Generated ${futures.length} files in ${formatElapsedTime(started)}");
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
