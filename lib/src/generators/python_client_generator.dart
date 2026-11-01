import 'dart:io';

import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/io_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_client_serializer.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:graphlink/src/utils.dart';

Future<Set<String>> generatePythonClientClasses(GLParser parser, GeneratorConfig config, DateTime started) async {
  final pythonConfig = config.clientConfig!.language as PythonClientConfig;
  final serializer = PythonSerializer(
    parser,
    immutableTypeFields: pythonConfig.immutableTypeFields,
    typeMapOverrides: config.typeMappings ?? {},
  );
  final clientSerializer = PythonClientSerializer(
    parser,
    serializer,
    httpAdapter: pythonConfig.httpAdapter,
    wsAdapter: pythonConfig.wsAdapter,
  );
  final destinationDir = config.outputDir;
  final files = <String, String>{};
  final models = <String>[];
  final exports = <String>[];

  void add(String subdir, String fileName, String content) {
    if (content.trim().isEmpty) return;
    files['$subdir/$fileName'] = content;
  }

  parser.enums.forEach((_, def) {
    final content = serializer.serializeEnumDefinition(def);
    add('enums', serializer.getFileNameFor(def), content);
    if (content.trim().isNotEmpty) exports.add(_exportLine('enums', serializer, def.codeName, def));
  });

  parser.inputs.forEach((_, def) {
    final content = serializer.serializeInputDefinition(def);
    add('inputs', serializer.getFileNameFor(def), content);
    if (content.trim().isNotEmpty) {
      exports.add(_exportLine('inputs', serializer, def.codeName, def));
      models.add(def.codeName);
    }
  });

  final allProjectedTypes = <String, GLTypeDefinition>{}
    ..addAll(parser.projectedTypes)
    ..addAll(parser.projectedInterfaces);
  allProjectedTypes.forEach((_, def) {
    final subdir = def is GLInterfaceDefinition ? 'interfaces' : 'types';
    final content = serializer.serializeTypeDefinition(def);
    add(subdir, serializer.getFileNameFor(def), content);
    if (content.trim().isNotEmpty) {
      exports.add(_exportLine(subdir, serializer, def.codeName, def));
      models.add(def.codeName);
    }
  });

  void addClient(String fileName, GLClassModel? model) {
    if (model == null) return;
    add('client', '$fileName.py', serializer.serializeGlClass(model));
    exports.add('from .client.$fileName import *  # noqa: F401,F403');
  }

  add('client', 'graph_link_model.py', serializer.serializeGlClass(clientSerializer.generateModelBaseFile()));
  addClient('graph_link_exception', clientSerializer.generateExceptionFile());
  addClient('graph_link_lock', clientSerializer.generateLockFile());
  addClient('graph_link_cache_entry', clientSerializer.generateCacheEntryFile());
  addClient('graph_link_tag_entry', clientSerializer.generateTagEntryFile());
  addClient('graph_link_partial_query', clientSerializer.generatePartialQueryFile());
  addClient('graph_link_cache_store', clientSerializer.generateCacheStoreFile());
  addClient('graph_link_in_memory_cache_store', clientSerializer.generateInMemoryCacheStoreFile());
  if (parser.persistedQueries) {
    addClient('graph_link_persisted_queries', clientSerializer.generatePersistedQueriesFile());
  }
  addClient('graph_link_resolver_base', clientSerializer.generateResolverBaseFile());
  for (final type in GLQueryType.values) {
    final model = clientSerializer.getClassForType(type);
    addClient(_operationFileName(type), model);
  }
  if (parser.hasUploadMutations) {
    addClient('graph_link_uploads', clientSerializer.generateUploadsFile());
    addClient('graph_link_upload_converter', clientSerializer.generateUploadConverterFile());
  }
  if (pythonConfig.httpAdapter == PythonHttpAdapter.httpx) {
    addClient('graph_link_httpx_adapter', clientSerializer.generateHttpxAdapterFile());
  }
  if (parser.hasSubscriptions) {
    addClient('graph_link_ws_message_types', clientSerializer.generateWsMessageTypesFile());
    addClient('graph_link_websocket_adapter', clientSerializer.generateWsAdapterFile());
    addClient('graph_link_subscription_handler', clientSerializer.generateSubscriptionHandlerFile());
    if (pythonConfig.wsAdapter == PythonWsAdapter.websockets) {
      addClient('graph_link_default_websocket_adapter', clientSerializer.generateDefaultWebSocketAdapterFile());
    }
  }
  addClient('graph_link_client', clientSerializer.generateClientFile());

  for (final subdir in const ['enums', 'inputs', 'types', 'interfaces', 'client']) {
    if (files.keys.any((k) => k.startsWith('$subdir/'))) files['$subdir/__init__.py'] = '';
  }
  files['__init__.py'] = _barrel(exports, models);

  final written = <Future<File>>[];
  files.forEach((path, content) {
    written.add(saveSource(data: content, path: '$destinationDir/$path', hashCommentSource: true));
  });
  final result = await Future.wait(written);
  stdout.writeln('Generated ${written.length} files in ${formatElapsedTime(started)}');
  final paths = result.map((f) => f.path).toSet();
  await cleanUpObsoleteFiles(paths);
  return paths;
}

String _exportLine(String subdir, PythonSerializer serializer, String className, dynamic def) =>
    'from .$subdir.${serializer.moduleNameFor(def)} import $className';

String _operationFileName(GLQueryType type) {
  switch (type) {
    case GLQueryType.query:
      return 'graph_link_queries';
    case GLQueryType.mutation:
      return 'graph_link_mutations';
    case GLQueryType.subscription:
      return 'graph_link_subscriptions';
  }
}

String _barrel(List<String> exports, List<String> models) {
  final buffer = StringBuffer();
  buffer.writeln('import sys as _sys');
  buffer.writeln();
  exports.forEach(buffer.writeln);
  buffer.writeln();
  buffer.writeln('_models = [${models.join(', ')}]');
  buffer.writeln('_namespace = {model.__name__: model for model in _models}');
  buffer.writeln();
  buffer.writeln('for _model in _models:');
  buffer.writeln('    _module = _sys.modules[_model.__module__]');
  buffer.writeln('    for _name, _value in _namespace.items():');
  buffer.writeln('        _module.__dict__.setdefault(_name, _value)');
  buffer.writeln();
  buffer.writeln('for _model in _models:');
  buffer.writeln('    _model.model_rebuild()');
  return buffer.toString();
}
