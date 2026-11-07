import 'dart:io';

import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/io_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_reactive_flavor.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:graphlink/src/utils.dart';

Future<Set<String>> generateJavaClientClasses(
    GLParser parser, String importPrefix, GeneratorConfig config, DateTime started) async {
  final javaConfig = config.clientConfig!.language as JavaClientConfig;
  final jsonCodec = javaConfig.jsonCodec;
  final serializer = JavaSerializer(
    parser,
    immutableInputFields: javaConfig.immutableInputFields,
    immutableTypeFields: javaConfig.immutableTypeFields,
    inputsAsRecords: javaConfig.inputAsRecord,
    typesAsRecords: javaConfig.typeAsRecord,
    jspecify: javaConfig.jspecify,
    typeMapOverrides: config.typeMappings ?? {},
    importPrefix: importPrefix,
  );
  final flavor = JavaReactiveFlavor.of(javaConfig.asyncStyle);
  if (flavor.isReactive &&
      javaConfig.reactiveHttpClient == JavaReactiveHttpClient.webclient &&
      javaConfig.asyncStyle != JavaAsyncStyle.reactor) {
    throw ArgumentError('reactiveHttpClient "webclient" requires asyncStyle "reactor" '
        '(got "${javaConfig.asyncStyle.name}"). Use "jdk" for rxjava3/mutiny.');
  }
  final clientSerializer = JavaClientSerializer(parser, serializer,
      jsonCodec: jsonCodec,
      flavor: flavor,
      restHttpAdapter: javaConfig.restHttpAdapter,
      reactiveHttpClient: javaConfig.reactiveHttpClient,
      commaQueryLists: javaConfig.queryListStyle == RestQueryListStyle.comma,
      bracketFormNesting: javaConfig.formNesting == RestFormNesting.bracket);
  final futures = <Future<File>>[];
  final destinationDir = config.outputDir;
  final packageName = javaConfig.packageName;
  final prefix = packageName;
  final wsAdapter = javaConfig.wsAdapter;

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

  final allProjectedTypes = <String, GLTypeDefinition>{}
    ..addAll(parser.projectedTypes)
    ..addAll(parser.projectedInterfaces);
  ['GraphLinkClientAdapter', 'GraphLinkJsonEncoder', 'GraphLinkJsonDecoder', 'GraphLinkFullResponse']
      .map((e) => parser.interfaces[e])
      .where((e) => e != null)
      .map((e) => e!)
      .forEach((def) => allProjectedTypes[def.token] = def);

  allProjectedTypes.forEach((k, def) {
    final subdir = def is GLInterfaceDefinition ? 'interfaces' : 'types';
    // The reactive adapter interface can't be expressed via the GraphQL type
    // map (Mono/Single/Uni<String>), so emit a raw-Java reactive variant when
    // an async style is selected. The GraphQL-registered token still exists so
    // every import/reference resolves unchanged.
    final isReactiveAdapter =
        flavor.isReactive && def.token == 'GraphLinkClientAdapter';
    futures.add(writeToFile(
      data: isReactiveAdapter
          ? serializer.serializeGlClass(
              clientSerializer.adapters.generateReactiveClientAdapterInterfaceFile())
          : serializer.serializeTypeDefinition(def),
      fileName: serializer.getFileNameFor(def),
      subdir: subdir,
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
  });

  futures.add(writeToFile(
    data: serializer.serializeGlClass(clientSerializer.generateClient(hasDefaultAdapters: wsAdapter != JavaWsAdapter.none)),
    fileName: 'GraphLinkClient${clientSerializer.fileExtension}',
    subdir: 'client',
    imports: [],
    destinationDir: destinationDir,
    packageName: packageName,
  ));
  futures.add(writeToFile(
    data: serializer.serializeGlClass(clientSerializer.runtime.generateGraphLinkResolverBaseFile(prefix)),
    fileName: 'GraphLinkResolverBase.java',
    subdir: 'client',
    imports: [],
    destinationDir: destinationDir,
    packageName: packageName,
  ));

  for (final type in GLQueryType.values) {
    final model = clientSerializer.generateQueriesClassFile(type);
    if (model != null) {
      futures.add(writeToFile(
        data: serializer.serializeGlClass(model),
        fileName: '${clientSerializer.classNameFromType(type)}.java',
        subdir: 'client',
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
      ));
    }
  }

  for (final entry in {
    'GraphLinkPartialQuery.java': clientSerializer.runtime.generateGraphLinkPartialQueryFile(prefix),
    'GraphLinkCacheEntry.java': clientSerializer.runtime.generateGraphLinkCacheEntryFile(),
    'GraphLinkTagEntry.java': clientSerializer.runtime.generateGraphLinkTagEntryFile(),
    'GraphLinkCacheStore.java': clientSerializer.runtime.generateGraphLinkCacheStoreFile(),
    'InMemoryGraphLinkCacheStore.java': clientSerializer.runtime.generateInMemoryGraphLinkCacheStoreFile(),
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
    data: serializer.serializeGlClass(clientSerializer.runtime.generateGraphLinkExceptionFile(prefix)),
    fileName: clientSerializer.exceptionFileName,
    subdir: 'client',
    imports: [],
    destinationDir: destinationDir,
    packageName: packageName,
  ));

  if (parser.hasUploadMutations || clientSerializer.hasRest) {
    for (final entry in {
      'GLUpload.java': clientSerializer.generateUploadsFile(),
      'GLMultipartBody.java': clientSerializer.generateMultipartBodyFile(),
      'UploadProgressCallback.java': clientSerializer.runtime.generateUploadProgressCallbackFile(),
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

  if (clientSerializer.hasRest) {
    for (final entry in clientSerializer.generateRestFiles().entries) {
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

  if (parser.hasUploadMutations) {
    futures.add(writeToFile(
      data: serializer.serializeGlClass(clientSerializer.runtime.generateMultipartAdapterFile(prefix)),
      fileName: 'GraphLinkMultipartAdapter.java',
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
  }

  if (parser.persistedQueries) {
    for (final entry in {
      'GraphLinkSha256.java': clientSerializer.runtime.generateSha256File(),
      'GraphLinkPersistedQueries.java': clientSerializer.runtime.generatePersistedQueriesFile(),
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
    if (parser.persistedQueriesUseGet) {
      for (final entry in {
        'GraphLinkGetNotSupported.java': clientSerializer.runtime.generateGetNotSupportedFile(),
        'GraphLinkGetRequest.java': clientSerializer.runtime.generateGetRequestFile(),
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
    if (parser.persistedQueriesUseGet && wsAdapter != JavaWsAdapter.none) {
      futures.add(writeToFile(
        data: serializer.serializeGlClass(
            _reactiveDefaultGetAdapter(clientSerializer, javaConfig, flavor) ??
                clientSerializer.runtime.generateDefaultGetAdapterFile(wsAdapter.name)),
        fileName: 'DefaultGraphLinkGetAdapter.java',
        subdir: 'client',
        imports: [],
        destinationDir: destinationDir,
        packageName: packageName,
      ));
    }
  }

  if (wsAdapter != JavaWsAdapter.none) {
    futures.add(writeToFile(
      data: serializer.serializeGlClass(
          _reactiveDefaultAdapter(clientSerializer, javaConfig, flavor) ??
              clientSerializer.adapters.generateDefaultClientAdapterFile(
                  wsAdapter.name, prefix)),
      fileName: 'DefaultGraphLinkClientAdapter.java',
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
  }

  if (jsonCodec != JavaJsonCodec.none) {
    futures.add(writeToFile(
      data: serializer.serializeGlClass(clientSerializer.adapters.generateJsonCodecFile(jsonCodec.name, prefix)),
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
      'GraphLinkWebSocketAdapter.java': clientSerializer.runtime.generateWebSocketAdapterFile(),
      'GraphLinkSubscriptionListener.java': clientSerializer.runtime.generateSubscriptionListenerFile(),
      'GraphqlWsMessageTypes.java': clientSerializer.runtime.generateGraphqlWsMessageTypesFile(),
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
      data: serializer.serializeGlClass(clientSerializer.runtime.generateGraphLinkSubscriptionHandlerFile(prefix)),
      fileName: 'GraphLinkSubscriptionHandler.java',
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
    if (wsAdapter != JavaWsAdapter.none) {
      futures.add(writeToFile(
        data: serializer.serializeGlClass(clientSerializer.adapters.generateDefaultWebSocketAdapterFile(wsAdapter.name, prefix)),
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

/// Selects the reactive default `GraphLinkClientAdapter` impl based on the
/// configured [JavaReactiveHttpClient], or returns `null` for the blocking
/// flavor (so the caller falls back to the synchronous okhttp/java11 adapter).
GLClassModel? _reactiveDefaultAdapter(JavaClientSerializer clientSerializer,
    JavaClientConfig javaConfig, JavaReactiveFlavor flavor) {
  if (!flavor.isReactive) return null;
  switch (javaConfig.reactiveHttpClient) {
    case JavaReactiveHttpClient.jdk:
      return clientSerializer.adapters.generateReactiveDefaultClientAdapterFile();
    case JavaReactiveHttpClient.webclient:
      if (javaConfig.asyncStyle != JavaAsyncStyle.reactor) {
        throw ArgumentError(
            'reactiveHttpClient "webclient" requires asyncStyle "reactor" '
            '(got "${javaConfig.asyncStyle.name}"). Use "jdk" for rxjava3/mutiny.');
      }
      return clientSerializer.adapters.generateWebClientDefaultClientAdapterFile();
  }
}

/// GET counterpart of [_reactiveDefaultAdapter]: same transport selection, or
/// `null` for the blocking flavor.
GLClassModel? _reactiveDefaultGetAdapter(JavaClientSerializer clientSerializer,
    JavaClientConfig javaConfig, JavaReactiveFlavor flavor) {
  if (!flavor.isReactive) return null;
  switch (javaConfig.reactiveHttpClient) {
    case JavaReactiveHttpClient.jdk:
      return clientSerializer.adapters.generateReactiveDefaultGetAdapterFile();
    case JavaReactiveHttpClient.webclient:
      return clientSerializer.adapters.generateWebClientDefaultGetAdapterFile();
  }
}
