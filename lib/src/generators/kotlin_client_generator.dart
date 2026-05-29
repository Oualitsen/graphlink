import 'dart:io';

import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/io_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin_client_serializer.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:graphlink/src/utils.dart';

Future<Set<String>> generateKotlinClientClasses(
    GLParser parser, String importPrefix, GeneratorConfig config, DateTime started) async {
  final kotlinConfig = config.clientConfig!.language as KotlinClientConfig;
  final serializer = KotlinSerializer(
    parser,
    generateJsonMethods: true,
    inputsAsDataClass: kotlinConfig.inputAsDataClass,
    typesAsDataClass: kotlinConfig.typeAsDataClass,
    typeMapOverrides: config.typeMappings ?? {},
    importPrefix: importPrefix,
  );
  final clientSerializer = KotlinClientSerializer(
    parser,
    serializer,
    wsAdapter: kotlinConfig.wsAdapter,
  );

  final futures = <Future<File>>[];
  final destinationDir = config.outputDir;
  final packageName = kotlinConfig.packageName;

  // ── Enums ──────────────────────────────────────────────────────────────────

  parser.enums.forEach((k, def) {
    futures.add(writeToFile(
      data: serializer.serializeEnumDefinition(def),
      fileName: serializer.getFileNameFor(def),
      subdir: 'enums',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
  });

  // ── Inputs ─────────────────────────────────────────────────────────────────

  parser.inputs.forEach((k, def) {
    futures.add(writeToFile(
      data: serializer.serializeInputDefinition(def),
      fileName: serializer.getFileNameFor(def),
      subdir: 'inputs',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
  });

  // ── Types & interfaces ─────────────────────────────────────────────────────

  final allProjectedTypes = <String, GLTypeDefinition>{}
    ..addAll(parser.projectedTypes)
    ..addAll(parser.projectedInterfaces);
  // GraphLinkFullResponse is serialized via the type system; the adapter/codec
  // interfaces are written as raw Kotlin constants to interfaces/ below.
  ['GraphLinkFullResponse']
      .map((e) => parser.interfaces[e])
      .where((e) => e != null)
      .map((e) => e!)
      .forEach((def) => allProjectedTypes[def.token] = def);

  allProjectedTypes.forEach((k, def) {
    final subdir = def is GLInterfaceDefinition ? 'interfaces' : 'types';
    futures.add(writeToFile(
      data: serializer.serializeTypeDefinition(def),
      fileName: serializer.getFileNameFor(def),
      subdir: subdir,
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
  });

  // ── Core client files ──────────────────────────────────────────────────────

  futures.add(writeToFile(
    data: serializer.serializeGlClass(clientSerializer.generateClient(
        hasDefaultAdapters: kotlinConfig.wsAdapter != KotlinWsAdapter.none)),
    fileName: 'GraphLinkClient.kt',
    subdir: 'client',
    imports: [],
    destinationDir: destinationDir,
    packageName: packageName,
  ));

  futures.add(writeToFile(
    data: serializer.serializeGlClass(clientSerializer.generateGraphLinkResolverBaseFile(packageName)),
    fileName: 'GraphLinkResolverBase.kt',
    subdir: 'client',
    imports: [],
    destinationDir: destinationDir,
    packageName: packageName,
  ));

  for (final type in GLQueryType.values) {
    GLClassModel? model;
    if (type == GLQueryType.query) {
      model = clientSerializer.getQueriesClass();
    } else if (type == GLQueryType.mutation) {
      model = clientSerializer.getMutationsClass();
    } else {
      model = clientSerializer.getSubscriptionsClass();
    }
    if (model != null) {
      futures.add(writeToFile(
        data: serializer.serializeGlClass(model),
        fileName: '${_classNameFromType(type)}.kt',
        subdir: 'client',
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
      ));
    }
  }

  // ── Infrastructure files ───────────────────────────────────────────────────

  // Adapter/codec interfaces — written to interfaces/ so imports resolve correctly.
  for (final entry in {
    'GraphLinkClientAdapter.kt': clientSerializer.generateClientAdapterFile(),
    'GraphLinkJsonEncoder.kt': clientSerializer.generateJsonEncoderFile(),
    'GraphLinkJsonDecoder.kt': clientSerializer.generateJsonDecoderFile(),
  }.entries) {
    futures.add(writeToFile(
      data: serializer.serializeGlClass(entry.value),
      fileName: entry.key,
      subdir: 'interfaces',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
  }

  // Other client infrastructure — written to client/.
  for (final entry in {
    'GraphLinkPartialQuery.kt': clientSerializer.generatePartialQueryFile(),
    'GraphLinkCacheEntry.kt': clientSerializer.generateCacheEntryFile(),
    'GraphLinkTagEntry.kt': clientSerializer.generateTagEntryFile(),
    'GraphLinkCacheStore.kt': clientSerializer.generateCacheStoreFile(),
    'InMemoryGraphLinkCacheStore.kt': clientSerializer.generateInMemoryCacheStoreFile(),
  }.entries) {
    futures.add(writeToFile(
      data: serializer.serializeGlClass(entry.value),
      fileName: entry.key,
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
  }

  futures.add(writeToFile(
    data: serializer.serializeGlClass(clientSerializer.generateExceptionFile()),
    fileName: 'GraphLinkException.kt',
    subdir: 'client',
    imports: [],
    destinationDir: destinationDir,
    packageName: packageName,
  ));

  // ── Codec ──────────────────────────────────────────────────────────────────

  futures.add(writeToFile(
    data: serializer.serializeGlClass(clientSerializer.generateCodecFile()),
    fileName: 'KotlinxSerializationGraphLinkJsonCodec.kt',
    subdir: 'client',
    imports: [],
    destinationDir: destinationDir,
    packageName: packageName,
  ));

  // ── Default HTTP adapter ───────────────────────────────────────────────────

  if (kotlinConfig.wsAdapter != KotlinWsAdapter.none) {
    futures.add(writeToFile(
      data: serializer.serializeGlClass(clientSerializer.generateDefaultClientAdapterFile()),
      fileName: 'DefaultGraphLinkClientAdapter.kt',
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
  }

  // ── Upload files ───────────────────────────────────────────────────────────

  if (parser.hasUploadMutations) {
    for (final entry in {
      'GLUpload.kt': clientSerializer.generateUploadsFile(),
      'UploadProgressCallback.kt': clientSerializer.generateUploadProgressCallbackFile(),
      'GraphLinkMultipartAdapter.kt': clientSerializer.generateMultipartAdapterFile(),
    }.entries) {
      futures.add(writeToFile(
        data: serializer.serializeGlClass(entry.value),
        fileName: entry.key,
        subdir: 'client',
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
      ));
    }
  }

  // ── WebSocket / subscription files ────────────────────────────────────────

  if (parser.hasSubscriptions) {
    for (final entry in {
      'GraphLinkWebSocketAdapter.kt': clientSerializer.generateWebSocketAdapterFile(),
      'GraphlinkWsMessageTypes.kt': clientSerializer.generateWsMessageTypesFile(),
      'GraphLinkAckStatus.kt': clientSerializer.generateAckStatusFile(),
      'GraphLinkSubscriptionHandler.kt': clientSerializer.generateSubscriptionHandlerFile(),
    }.entries) {
      futures.add(writeToFile(
        data: serializer.serializeGlClass(entry.value),
        fileName: entry.key,
        subdir: 'client',
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
      ));
    }
    if (kotlinConfig.wsAdapter != KotlinWsAdapter.none) {
      futures.add(writeToFile(
        data: serializer.serializeGlClass(clientSerializer.generateDefaultWebSocketAdapterFile()),
        fileName: 'DefaultGraphLinkWebSocketAdapter.kt',
        subdir: 'client',
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
      ));
    }
  }

  final result = await Future.wait(futures);
  stdout.writeln('Generated ${futures.length} files in ${formatElapsedTime(started)}');
  final paths = result.map((f) => f.path).toSet();
  await cleanUpObsoleteFiles(paths);
  return paths;
}

String _classNameFromType(GLQueryType type) {
  switch (type) {
    case GLQueryType.query:
      return 'GraphLinkQueries';
    case GLQueryType.mutation:
      return 'GraphLinkMutations';
    case GLQueryType.subscription:
      return 'GraphLinkSubscriptions';
  }
}
