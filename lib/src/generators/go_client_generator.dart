import 'dart:io';

import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/io_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/serializers/client_serializers/go/go_client_serializer.dart';
import 'package:graphlink/src/serializers/go_serializer.dart';
import 'package:graphlink/src/utils.dart';

Future<Set<String>> generateGoClientClasses(GLParser parser, GeneratorConfig config, DateTime started) async {
  final goConfig = config.clientConfig!.language as GoClientConfig;
  final serializer = GoSerializer(
    parser,
    packageName: goConfig.packageName,
    typeMapOverrides: config.typeMappings ?? {},
  );
  final clientSerializer = GoClientSerializer(
    parser,
    serializer,
    httpAdapter: goConfig.httpAdapter,
    wsAdapter: goConfig.wsAdapter,
  );
  final destinationDir = config.outputDir;
  final files = <String, String>{};

  void add(String fileName, String content) {
    if (content.trim().isEmpty) return;
    files[fileName] = content;
  }

  void addClient(String fileName, GLClassModel? model) {
    if (model == null) return;
    add('$fileName.go', serializer.serializeGlClass(model));
  }

  parser.enums.forEach((_, def) {
    add(serializer.getFileNameFor(def), serializer.serializeEnumDefinition(def));
  });
  parser.inputs.forEach((_, def) {
    add(serializer.getFileNameFor(def), serializer.serializeInputDefinition(def));
  });
  final allProjectedTypes = <String, GLTypeDefinition>{}
    ..addAll(parser.projectedTypes)
    ..addAll(parser.projectedInterfaces);
  allProjectedTypes.forEach((_, def) {
    add(serializer.getFileNameFor(def), serializer.serializeTypeDefinition(def));
  });

  addClient('graph_link_util', clientSerializer.generateUtilFile());
  addClient('graph_link_exception', clientSerializer.generateExceptionFile());
  addClient('graph_link_cache', clientSerializer.generateCacheFile());
  addClient('graph_link_partial_query', clientSerializer.generatePartialQueryFile());
  addClient('graph_link_resolver_base', clientSerializer.generateResolverBaseFile());
  if (parser.persistedQueries) {
    addClient('graph_link_persisted_queries', clientSerializer.generatePersistedQueriesFile());
  }
  for (final type in GLQueryType.values) {
    addClient('graph_link_${_operationFileSuffix(type)}', clientSerializer.getClassForType(type));
  }
  if (parser.hasUploadMutations) {
    addClient('graph_link_uploads', clientSerializer.generateUploadsFile());
  }
  if (goConfig.httpAdapter == GoHttpAdapter.nethttp) {
    addClient('graph_link_http_adapter', clientSerializer.generateHttpAdapterFile());
  }
  if (parser.hasSubscriptions) {
    addClient('graph_link_ws_message_types', clientSerializer.generateWsMessageTypesFile());
    addClient('graph_link_websocket_adapter', clientSerializer.generateWsAdapterFile());
    addClient('graph_link_subscription_handler', clientSerializer.generateSubscriptionHandlerFile());
    if (goConfig.wsAdapter == GoWsAdapter.coder) {
      addClient('graph_link_default_websocket_adapter', clientSerializer.generateDefaultWebSocketAdapterFile());
    }
  }
  addClient('graph_link_client', clientSerializer.generateClientFile());

  final written = <Future<File>>[];
  files.forEach((name, content) {
    written.add(saveSource(data: content, path: '$destinationDir/$name', typescriptSource: true));
  });
  final result = await Future.wait(written);
  stdout.writeln('Generated ${written.length} files in ${formatElapsedTime(started)}');
  final paths = result.map((f) => f.path).toSet();
  await cleanUpObsoleteFiles(paths);
  return paths;
}

String _operationFileSuffix(GLQueryType type) {
  switch (type) {
    case GLQueryType.query:
      return 'queries';
    case GLQueryType.mutation:
      return 'mutations';
    case GLQueryType.subscription:
      return 'subscriptions';
  }
}
