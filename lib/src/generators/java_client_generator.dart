import 'dart:io';

import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/io_utils.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/java_client_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/utils.dart';

Future<Set<String>> generateJavaClientClasses(
    GLParser parser, GeneratorConfig config, DateTime started,
    {String? pack}) async {
  final javaConfig = config.clientConfig!.language as JavaClientConfig;
  final jsonCodec = javaConfig.jsonCodec;
  final serializer = JavaSerializer(
    parser,
    generateJsonMethods: true,
    immutableInputFields: javaConfig.immutableInputFields,
    immutableTypeFields: javaConfig.immutableTypeFields,
    inputsAsRecords: javaConfig.inputAsRecord,
    typesAsRecords: javaConfig.typeAsRecord,
    typeMapOverrides: config.typeMappings ?? {},
  );
  final clientSerializer = JavaClientSerializer(parser, serializer, jsonCodec: jsonCodec);
  final futures = <Future<File>>[];
  final destinationDir = config.outputDir;
  final packageName = javaConfig.packageName;
  final prefix = packageName;
  final wsAdapter = javaConfig.wsAdapter;

  parser.enums.forEach((k, def) {
    futures.add(writeToFile(
      data: serializer.serializeEnumDefinition(def, ''),
      fileName: serializer.getFileNameFor(def),
      subdir: 'enums',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
  });

  parser.inputs.forEach((k, def) {
    futures.add(writeToFile(
      data: serializer.serializeInputDefinition(def, prefix),
      fileName: serializer.getFileNameFor(def),
      subdir: 'inputs',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
  });

  final allProjectedTypes = <String, GLTypeDefinition>{}
    ..addAll(parser.projectedTypes)
    ..addAll(parser.projectedInterfaces);
  ['GraphLinkClientAdapter', 'GraphLinkJsonEncoder', 'GraphLinkJsonDecoder']
      .map((e) => parser.interfaces[e]!)
      .forEach((def) => allProjectedTypes[def.token] = def);

  allProjectedTypes.forEach((k, def) {
    final subdir = def is GLInterfaceDefinition ? 'interfaces' : 'types';
    futures.add(writeToFile(
      data: serializer.serializeTypeDefinition(def, prefix),
      fileName: serializer.getFileNameFor(def),
      subdir: subdir,
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
  });

  futures.add(writeToFile(
    data: serializer.serializeGlClass(clientSerializer.generateClient(prefix, hasDefaultAdapters: wsAdapter != JavaWsAdapter.none), importPrefix: prefix),
    fileName: 'GraphLinkClient${clientSerializer.fileExtension}',
    subdir: 'client',
    imports: [],
    destinationDir: destinationDir,
    packageName: packageName,
  ));
  futures.add(writeToFile(
    data: serializer.serializeGlClass(clientSerializer.generateGraphLinkResolverBaseFile(prefix), importPrefix: prefix),
    fileName: 'GraphLinkResolverBase.java',
    subdir: 'client',
    imports: [],
    destinationDir: destinationDir,
    packageName: packageName,
  ));

  for (final type in GLQueryType.values) {
    final model = clientSerializer.generateQueriesClassFile(type, prefix);
    if (model != null) {
      futures.add(writeToFile(
        data: serializer.serializeGlClass(model, importPrefix: prefix),
        fileName: '${clientSerializer.classNameFromType(type)}.java',
        subdir: 'client',
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
      ));
    }
  }

  for (final entry in {
    'GraphLinkPartialQuery.java': clientSerializer.generateGraphLinkPartialQueryFile(prefix),
    'GraphLinkCacheEntry.java': clientSerializer.generateGraphLinkCacheEntryFile(),
    'GraphLinkTagEntry.java': clientSerializer.generateGraphLinkTagEntryFile(),
    'GraphLinkCacheStore.java': clientSerializer.generateGraphLinkCacheStoreFile(),
    'InMemoryGraphLinkCacheStore.java': clientSerializer.generateInMemoryGraphLinkCacheStoreFile(),
  }.entries) {
    futures.add(writeToFile(
      data: serializer.serializeGlClass(entry.value, importPrefix: prefix),
      fileName: entry.key,
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
  }

  futures.add(writeToFile(
    data: serializer.serializeGlClass(clientSerializer.generateGraphLinkExceptionFile(prefix), importPrefix: prefix),
    fileName: clientSerializer.exceptionFileName,
    subdir: 'client',
    imports: [],
    destinationDir: destinationDir,
    packageName: packageName,
  ));

  if (parser.hasUploadMutations) {
    for (final entry in {
      'GLUpload.java': clientSerializer.generateGLUploadFile(),
      'UploadProgressCallback.java': clientSerializer.generateUploadProgressCallbackFile(),
    }.entries) {
      futures.add(writeToFile(
        data: serializer.serializeGlClass(entry.value, importPrefix: prefix),
        fileName: entry.key,
        subdir: 'client',
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
      ));
    }
    futures.add(writeToFile(
      data: serializer.serializeGlClass(clientSerializer.generateMultipartAdapterFile(prefix), importPrefix: prefix),
      fileName: 'GraphLinkMultipartAdapter.java',
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
  }

  if (wsAdapter != JavaWsAdapter.none) {
    futures.add(writeToFile(
      data: serializer.serializeGlClass(clientSerializer.generateDefaultClientAdapterFile(wsAdapter.name, prefix), importPrefix: prefix),
      fileName: 'DefaultGraphLinkClientAdapter.java',
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
  }

  if (jsonCodec != JavaJsonCodec.none) {
    futures.add(writeToFile(
      data: serializer.serializeGlClass(clientSerializer.generateJsonCodecFile(jsonCodec.name, prefix), importPrefix: prefix),
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
    for (final entry in {
      'GraphLinkWebSocketAdapter.java': clientSerializer.generateWebSocketAdapterFile(),
      'GraphLinkSubscriptionListener.java': clientSerializer.generateSubscriptionListenerFile(),
      'GraphqlWsMessageTypes.java': clientSerializer.generateGraphqlWsMessageTypesFile(),
    }.entries) {
      futures.add(writeToFile(
        data: serializer.serializeGlClass(entry.value, importPrefix: prefix),
        fileName: entry.key,
        subdir: 'client',
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
      ));
    }
    futures.add(writeToFile(
      data: serializer.serializeGlClass(clientSerializer.generateGraphLinkSubscriptionHandlerFile(prefix), importPrefix: prefix),
      fileName: 'GraphLinkSubscriptionHandler.java',
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
    if (wsAdapter != JavaWsAdapter.none) {
      futures.add(writeToFile(
        data: serializer.serializeGlClass(clientSerializer.generateDefaultWebSocketAdapterFile(wsAdapter.name, prefix), importPrefix: prefix),
        fileName: 'DefaultGraphLinkWebSocketAdapter.java',
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
