import 'dart:io';

import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/io_utils.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/serializers/client_serializers/swift/swift_client_serializer.dart';
import 'package:graphlink/src/serializers/swift_serializer.dart';
import 'package:graphlink/src/utils.dart';

/// Writes the Swift client: generated types/enums/inputs/interfaces plus the
/// full operation-independent and operation-level runtime (queries,
/// mutations, subscriptions, uploads, websocket).
Future<Set<String>> generateSwiftClientClasses(
    GLParser parser, GeneratorConfig config, DateTime started) async {
  final swiftConfig = config.clientConfig!.language as SwiftClientConfig;
  final serializer = SwiftSerializer(
    parser,
    immutableTypeFields: swiftConfig.immutableTypeFields,
    typeMapOverrides: config.typeMappings ?? {},
    importPrefix: swiftConfig.moduleName,
  );
  final clientSerializer = SwiftClientSerializer(
    parser,
    serializer,
    withDefaultAdapters: swiftConfig.wsAdapter != SwiftWsAdapter.none,
  );

  final futures = <Future<File>>[];
  final destinationDir = config.outputDir;

  // ── Enums ──────────────────────────────────────────────────────────────────

  parser.enums.forEach((k, def) {
    futures.add(writeToFile(
      data: serializer.serializeEnumDefinition(def),
      fileName: serializer.getFileNameFor(def),
      subdir: 'Enums',
      imports: const [],
      destinationDir: destinationDir,
    ));
  });

  // ── Inputs ─────────────────────────────────────────────────────────────────

  parser.inputs.forEach((k, def) {
    futures.add(writeToFile(
      data: serializer.serializeInputDefinition(def),
      fileName: serializer.getFileNameFor(def),
      subdir: 'Inputs',
      imports: const [],
      destinationDir: destinationDir,
    ));
  });

  // ── Types & interfaces ─────────────────────────────────────────────────────

  final allProjectedTypes = <String, GLTypeDefinition>{}
    ..addAll(parser.projectedTypes)
    ..addAll(parser.projectedInterfaces);

  allProjectedTypes.forEach((k, def) {
    final subdir = def is GLInterfaceDefinition ? 'Interfaces' : 'Types';
    futures.add(writeToFile(
      data: serializer.serializeTypeDefinition(def),
      fileName: serializer.getFileNameFor(def),
      subdir: subdir,
      imports: const [],
      destinationDir: destinationDir,
    ));
  });

  // ── Client runtime infrastructure ──────────────────────────────────────────

  // GraphLinkPayload and GraphLinkError are NOT written here — they're
  // synthetic grammar types already covered by the allProjectedTypes loop
  // above (emitted into Types/), which produces a richer, schema-accurate
  // shape (e.g. GraphLinkError.extensions/.locations) than a hand-written
  // constant could. Writing them again here previously caused a duplicate
  // `struct GraphLinkPayload`/`GraphLinkError` declaration.
  final clientFiles = <String, dynamic>{
    'GraphLinkClientAdapter.swift': clientSerializer.generateClientAdapterFile(),
    'GraphLinkJson.swift': clientSerializer.generateJsonFile(),
    'GraphLinkCacheStore.swift': clientSerializer.generateCacheStoreFile(),
    'InMemoryGraphLinkCacheStore.swift': clientSerializer.generateInMemoryCacheStoreFile(),
    'GraphLinkCacheEntry.swift': clientSerializer.generateCacheEntryFile(),
    'GraphLinkTagEntry.swift': clientSerializer.generateTagEntryFile(),
    'GraphLinkPartialQuery.swift': clientSerializer.generatePartialQueryFile(),
    'GraphLinkException.swift': clientSerializer.generateExceptionFile(),
    'DefaultGraphLinkURLSessionAdapter.swift': clientSerializer.generateDefaultAdapterFile(),
    'GraphLinkResolverBase.swift': clientSerializer.generateResolverBaseFile(),
    'GraphLinkClient.swift': clientSerializer.generateClient(),
  };

  // ── Operation classes (queries / mutations / subscriptions) ────────────────

  for (final type in GLQueryType.values) {
    final model = clientSerializer.getClassForType(type);
    if (model != null) {
      clientFiles['${clientSerializer.classNameFromType(type)}.swift'] = model;
    }
  }

  // ── Upload runtime (only if the schema has upload mutations) ───────────────

  if (parser.hasUploadMutations) {
    clientFiles['GLUpload.swift'] = clientSerializer.generateUploadsFile();
    clientFiles['UploadProgressCallback.swift'] = clientSerializer.generateUploadProgressCallbackFile();
    clientFiles['GraphLinkMultipartAdapter.swift'] = clientSerializer.generateMultipartAdapterFile();
    clientFiles['DefaultGraphLinkURLSessionMultipartAdapter.swift'] = clientSerializer.generateDefaultMultipartAdapterFile();
  }

  // ── WebSocket / subscription runtime (only if the schema has subscriptions) ─

  if (parser.hasSubscriptions) {
    clientFiles['GraphLinkWebSocketAdapter.swift'] = clientSerializer.generateWebSocketAdapterFile();
    clientFiles['GraphlinkWsMessageTypes.swift'] = clientSerializer.generateWsMessageTypesFile();
    clientFiles['GraphLinkSubscriptionHandler.swift'] = clientSerializer.generateSubscriptionHandlerFile();
    if (swiftConfig.wsAdapter != SwiftWsAdapter.none) {
      clientFiles['DefaultGraphLinkWebSocketAdapter.swift'] = clientSerializer.generateDefaultWebSocketAdapterFile();
    }
  }

  for (final entry in clientFiles.entries) {
    futures.add(writeToFile(
      data: serializer.serializeGlClass(entry.value),
      fileName: entry.key,
      subdir: 'Client',
      imports: const [],
      destinationDir: destinationDir,
    ));
  }

  final result = await Future.wait(futures);
  stdout.writeln('Generated ${futures.length} files in ${formatElapsedTime(started)}');
  final paths = result.map((f) => f.path).toSet();
  await cleanUpObsoleteFiles(paths);
  return paths;
}
