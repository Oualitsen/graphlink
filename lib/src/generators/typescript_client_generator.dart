import 'dart:io';

import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/io_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/generators/barrel_file_handler.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:graphlink/src/utils.dart';

Future<Set<String>> generateTypeScriptClientClasses(
    GLParser parser, GeneratorConfig config, DateTime started,
    {String? pack}) async {
  final tsConfig = config.clientConfig!.language as TypeScriptClientConfig;
  final serializer = TypeScriptSerializer(parser,
      typeMapOverrides: config.typeMappings ?? {}, importPrefix: '');
  final cs = TypeScriptClientSerializer(
    parser,
    serializer,
    generateDefaultWsAdapter: tsConfig.generateDefaultWsAdapter,
    observables: tsConfig.observables,
  );
  final futures = <Future<File>>[];
  final destinationDir = config.outputDir;

  // ── Schema types ──────────────────────────────────────────────────────────

  parser.enums.forEach((k, def) {
    futures.add(writeToFile(
      data: serializer.serializeEnumDefinition(def),
      fileName: serializer.getFileNameFor(def),
      subdir: 'enums',
      imports: [],
      destinationDir: destinationDir,
    ));
  });

  parser.inputs.forEach((k, def) {
    futures.add(writeToFile(
      data: serializer.serializeInputDefinition(def),
      fileName: serializer.getFileNameFor(def),
      subdir: 'inputs',
      imports: [],
      destinationDir: destinationDir,
    ));
  });

  final allProjectedTypes = <String, GLTypeDefinition>{}
    ..addAll(parser.projectedTypes)
    ..addAll(parser.projectedInterfaces);
  allProjectedTypes.forEach((k, def) {
    final subdir = def is GLInterfaceDefinition ? 'interfaces' : 'types';
    futures.add(writeToFile(
      data: serializer.serializeTypeDefinition(def),
      fileName: serializer.getFileNameFor(def),
      subdir: subdir,
      imports: [],
      destinationDir: destinationDir,
    ));
  });

  // ── Client infrastructure files ───────────────────────────────────────────

  void emitClient(String fileName, GLClassModel model) {
    futures.add(writeToFile(
      data: serializer.serializeGlClass(model),
      fileName: fileName,
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
    ));
  }

  final clientFiles = <String>[];

  void addClient(String fileName, GLClassModel? model) {
    if (model == null) return;
    clientFiles.add(fileName);
    emitClient(fileName, model);
  }

  final ext = cs.fileExtension;

  // Always-present infra
  addClient('graph-link-adapter$ext', cs.generateAdapterTypeFile());
  addClient('graph-link-cache-store$ext', cs.generateCacheStoreFile());
  addClient('graph-link-in-memory-cache-store$ext', cs.generateInMemoryCacheStoreFile());
  addClient('graph-link-cache-entry$ext', cs.generateCacheEntryFile());
  addClient('graph-link-tag-entry$ext', cs.generateTagEntryFile());
  addClient('graph-link-lock$ext', cs.generateLockFile());
  addClient('graph-link-partial-query$ext', cs.generatePartialQueryFile());
  addClient('graph-link-resolver-base$ext', cs.generateResolverBaseFile());

  // WebSocket infrastructure (only when subscriptions exist)
  if (parser.hasSubscriptions) {
    addClient('graph-link-ws-adapter$ext', cs.generateWsAdapterFile());
    addClient('graph-link-ws-message-types$ext', cs.generateWsMessageTypesFile());
    addClient('graph-link-subscription-handler$ext', cs.generateSubscriptionHandlerFile());
    if (tsConfig.generateDefaultWsAdapter) {
      addClient('graph-link-default-ws-adapter$ext', cs.generateDefaultWsAdapterFile());
    }
  }

  // Operation classes (null when no operations of that type exist)
  addClient('graph-link-queries$ext', cs.generateQueriesFile());
  addClient('graph-link-mutations$ext', cs.generateMutationsFile());
  addClient('graph-link-subscriptions$ext', cs.generateSubscriptionsFile());

  // Top-level client wrapper
  addClient('graph-link-client$ext', cs.generateClientOnlyFile());

  // Uploads helper (conditional)
  if (parser.hasUploadMutations) {
    addClient('graph-link-uploads$ext', cs.generateUploadsFile());
  }

  // HTTP adapters (conditional)
  final adaptersModel = cs.generateAdaptersFile(tsConfig.httpAdapter);
  if (adaptersModel != null) {
    addClient('graph-link-adapters$ext', adaptersModel);
  }

  final result = await Future.wait(futures);
  final barrelFile = await TypeScriptBarrelFileHandler(
    parser, destinationDir, serializer,
    clientFiles: clientFiles,
  ).generate();

  stdout.writeln('Generated ${futures.length + 1} files in ${formatElapsedTime(started)}');

  final paths = result.map((f) => f.path).toSet()..add(barrelFile.path);
  await cleanUpObsoleteFiles(paths);
  return paths;
}
