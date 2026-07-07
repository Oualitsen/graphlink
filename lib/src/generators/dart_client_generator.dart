import 'dart:io';

import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/io_utils.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/flutter_inputs/flutter_inputs_serializer.dart';
import 'package:graphlink/src/serializers/flutter_types_serializer.dart';
import 'package:graphlink/src/generators/barrel_file_handler.dart';
import 'package:graphlink/src/utils.dart';

Future<Set<String>> generateDartClientClasses(
    GLParser parser, String importPrefix, GeneratorConfig config, DateTime started,
    ) async {
  final dartConfig = config.clientConfig!.language as DartClientConfig;
  final serializer = DartSerializer(parser,
      typeMapOverrides: config.typeMappings ?? {}, importPrefix: importPrefix);
  final clientSerializer = DartClientSerializer(parser, serializer,
      generateAdapters: dartConfig.generateAdapters,
      httpAdapter: dartConfig.httpAdapter);
  final futures = <Future<File>>[];
  final destinationDir = config.outputDir;

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

  final flutterConfig = dartConfig.flutter;
  if (flutterConfig != null && flutterConfig.generateTypes) {
    
    final flutterSerializer = FlutterTypesSerializer(parser, serializer, flutterConfig, importPrefix);

    parser.enums.forEach((k, def) {
      if (flutterSerializer.shouldSkipEnum(def)) return;
      futures.add(writeToFile(
        data: flutterSerializer.serializeEnumLabels(def),
        fileName: flutterSerializer.getEnumLabelsFileNameFor(def),
        subdir: 'widgets/enums',
        imports: [],
        destinationDir: destinationDir,
      ));
    });

    parser.projectedTypes.forEach((k, def) {
      final content = flutterSerializer.serializeTypeWidget(def);
      if (content.isNotEmpty) {
        futures.add(writeToFile(
          data: content,
          fileName: flutterSerializer.getWidgetFileNameFor(def),
          subdir: 'widgets/types',
          imports: [],
          destinationDir: destinationDir,
        ));
      }
    });
  }

  if (flutterConfig != null && flutterConfig.generateInputs) {
    final inputsSerializer = FlutterInputsSerializer(parser, serializer, flutterConfig, importPrefix);

    // shared once-generated files
    futures.add(writeToFile(
      data: inputsSerializer.serializeSharedInputFormWidget(),
      fileName: 'input_form_widget.dart',
      subdir: 'widgets/inputs',
      imports: [],
      destinationDir: destinationDir,
    ));
    futures.add(writeToFile(
      data: inputsSerializer.serializeSharedInputReadException(),
      fileName: 'input_read_exception.dart',
      subdir: 'widgets/inputs',
      imports: [],
      destinationDir: destinationDir,
    ));
    futures.add(writeToFile(
      data: inputsSerializer.serializeSharedBooleanLabels(),
      fileName: 'boolean_labels.dart',
      subdir: 'widgets/inputs',
      imports: [],
      destinationDir: destinationDir,
    ));
    futures.add(writeToFile(
      data: inputsSerializer.serializeSharedFieldWidgets(),
      fileName: 'field_widgets.dart',
      subdir: 'widgets/inputs',
      imports: [],
      destinationDir: destinationDir,
    ));
    futures.add(writeToFile(
      data: inputsSerializer.serializeSharedTextFieldOptions(),
      fileName: 'text_field_options.dart',
      subdir: 'widgets/inputs',
      imports: [],
      destinationDir: destinationDir,
    ));
    futures.add(writeToFile(
      data: inputsSerializer.serializeSharedRequiredIndicator(),
      fileName: 'required_indicator.dart',
      subdir: 'widgets/inputs',
      imports: [],
      destinationDir: destinationDir,
    ));
    futures.add(writeToFile(
      data: inputsSerializer.serializeSharedFormStrings(),
      fileName: 'form_strings.dart',
      subdir: 'widgets/inputs',
      imports: [],
      destinationDir: destinationDir,
    ));
    futures.add(writeToFile(
      data: inputsSerializer.serializeSharedDateInputConfig(),
      fileName: 'date_input_config.dart',
      subdir: 'widgets/inputs',
      imports: [],
      destinationDir: destinationDir,
    ));
    futures.add(writeToFile(
      data: inputsSerializer.serializeSharedDateInputFormatter(),
      fileName: 'date_input_formatter.dart',
      subdir: 'widgets/inputs',
      imports: [],
      destinationDir: destinationDir,
    ));
    futures.add(writeToFile(
      data: inputsSerializer.serializeSharedFieldVisibility(),
      fileName: 'field_visibility.dart',
      subdir: 'widgets/inputs',
      imports: [],
      destinationDir: destinationDir,
    ));
    futures.add(writeToFile(
      data: inputsSerializer.serializeSharedSimpleFieldForm(),
      fileName: 'simple_field_form.dart',
      subdir: 'widgets/inputs',
      imports: [],
      destinationDir: destinationDir,
    ));

    futures.add(writeToFile(
      data: inputsSerializer.serializeSharedInputStepOptions(),
      fileName: 'input_step_options.dart',
      subdir: 'widgets/inputs',
      imports: [],
      destinationDir: destinationDir,
    ));

    futures.add(writeToFile(
      data: inputsSerializer.serializeSharedStepperStrings(),
      fileName: 'stepper_strings.dart',
      subdir: 'widgets/inputs',
      imports: [],
      destinationDir: destinationDir,
    ));
    futures.add(writeToFile(
      data: inputsSerializer.serializeSharedSelectFieldConfig(),
      fileName: 'select_field_config.dart',
      subdir: 'widgets/inputs',
      imports: [],
      destinationDir: destinationDir,
    ));

    parser.inputs.forEach((k, def) {
      final content = inputsSerializer.serializeInputForm(def);
      if (content.isNotEmpty) {
        futures.add(writeToFile(
          data: content,
          fileName: inputsSerializer.getFormFileNameFor(def),
          subdir: 'widgets/inputs',
          imports: [],
          destinationDir: destinationDir,
        ));
      }
    });
  }


  final clientFiles = <String>[];

  // GraphLinkCacheEntry — separate public file
  const cacheEntryFileName = 'graph_link_cache_entry.dart';
  clientFiles.add(cacheEntryFileName);
  futures.add(writeToFile(
    data: serializer.serializeGlClass(clientSerializer.generateCacheEntryFile()),
    fileName: cacheEntryFileName,
    subdir: 'client',
    imports: [],
    destinationDir: destinationDir,
  ));

  // GraphLinkLock — separate public file
  const lockFileName = 'graph_link_lock.dart';
  clientFiles.add(lockFileName);
  futures.add(writeToFile(
    data: serializer.serializeGlClass(clientSerializer.generateLockFile()),
    fileName: lockFileName,
    subdir: 'client',
    imports: [],
    destinationDir: destinationDir,
  ));

  // Remaining cache infra — each in its own file
  for (final entry in {
    'graph_link_tag_entry.dart': clientSerializer.generateTagEntryFile(),
    'graph_link_partial_query.dart': clientSerializer.generatePartialQueryFile(),
    'graph_link_cache_store.dart': clientSerializer.generateCacheStoreFile(),
    'graph_link_in_memory_cache_store.dart': clientSerializer.generateInMemoryCacheStoreFile(),
  }.entries) {
    clientFiles.add(entry.key);
    futures.add(writeToFile(
      data: serializer.serializeGlClass(entry.value),
      fileName: entry.key,
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
    ));
  }

  // GraphLinkResolverBase
  const resolverBaseFileName = 'graph_link_resolver_base.dart';
  clientFiles.add(resolverBaseFileName);
  futures.add(writeToFile(
    data: serializer.serializeGlClass(clientSerializer.generateResolverBaseFile()),
    fileName: resolverBaseFileName,
    subdir: 'client',
    imports: [],
    destinationDir: destinationDir,
  ));

  // Per-type operation classes (GraphLinkQueries, GraphLinkMutations, GraphLinkSubscriptions)
  for (final type in GLQueryType.values) {
    final model = clientSerializer.getClassForType(type);
    if (model != null) {
      final fileName = _dartFileNameForType(type, clientSerializer.fileExtension);
      clientFiles.add(fileName);
      futures.add(writeToFile(
        data: serializer.serializeGlClass(model),
        fileName: fileName,
        subdir: 'client',
        imports: [],
        destinationDir: destinationDir,
      ));
    }
  }

  // Main client class only
  final clientFileName = 'graph_link_client${clientSerializer.fileExtension}';
  clientFiles.add(clientFileName);
  futures.add(writeToFile(
    data: serializer.serializeGlClass(clientSerializer.generateClientOnlyFile()),
    fileName: clientFileName,
    subdir: 'client',
    imports: [],
    destinationDir: destinationDir,
  ));

  if (parser.hasUploadMutations) {
    final uploadsFileName = 'graph_link_uploads${clientSerializer.fileExtension}';
    clientFiles.add(uploadsFileName);
    futures.add(writeToFile(
      data: serializer.serializeGlClass(clientSerializer.generateUploadsFile()),
      fileName: uploadsFileName,
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
    ));

    const uploadConverterFileName = 'graph_link_upload_converter.dart';
    clientFiles.add(uploadConverterFileName);
    futures.add(writeToFile(
      data: serializer.serializeGlClass(clientSerializer.generateUploadConverterFile()),
      fileName: uploadConverterFileName,
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
    ));
  }

  if (dartConfig.generateAdapters) {
    final httpAdapter = dartConfig.httpAdapter;
    if (httpAdapter != DartHttpAdapter.none) {
      final adapterFileName = httpAdapter == DartHttpAdapter.dio
          ? 'graph_link_dio_adapter${clientSerializer.fileExtension}'
          : 'graph_link_http_adapter${clientSerializer.fileExtension}';
      clientFiles.add(adapterFileName);
      futures.add(writeToFile(
        data: serializer.serializeGlClass(
            httpAdapter == DartHttpAdapter.dio
                ? clientSerializer.generateDioAdapterFile()
                : clientSerializer.generateHttpAdapterFile(),
           ),
        fileName: adapterFileName,
        subdir: 'client',
        imports: [],
        destinationDir: destinationDir,
      ));
    }
    if (parser.hasSubscriptions) {
      for (final entry in {
        'graph_link_handshake_status.dart': clientSerializer.generateHandshakeStatusFile(),
        'graph_link_stream_sink.dart': clientSerializer.generateStreamSinkFile(),
        'graph_link_websocket_adapter.dart': clientSerializer.generateWsAdapterFile(),
        'graph_link_ws_message_types.dart': clientSerializer.generateWsMessageTypesFile(),
        'graph_link_subscription_handler.dart': clientSerializer.generateSubscriptionHandlerFile(),
      }.entries) {
        clientFiles.add(entry.key);
        futures.add(writeToFile(
          data: serializer.serializeGlClass(entry.value),
          fileName: entry.key,
          subdir: 'client',
          imports: [],
          destinationDir: destinationDir,
        ));
      }
      final wsFileName = 'graph_link_default_websocket_adapter${clientSerializer.fileExtension}';
      clientFiles.add(wsFileName);
      futures.add(writeToFile(
        data: serializer.serializeGlClass(clientSerializer.generateDefaultWebSocketAdapterFile()),
        fileName: wsFileName,
        subdir: 'client',
        imports: [],
        destinationDir: destinationDir,
      ));
    }
  }

  final result = await Future.wait(futures);
  final barrelFile = await DartBarrelFileHandler(parser, destinationDir, serializer, clientFiles: clientFiles).generate();
  stdout.writeln('Generated ${futures.length + 1} files in ${formatElapsedTime(started)}');
  final paths = result.map((f) => f.path).toSet()..add(barrelFile.path);
  await cleanUpObsoleteFiles(paths);
  return paths;
}

String _dartFileNameForType(GLQueryType type, String ext) {
  switch (type) {
    case GLQueryType.query:
      return 'graph_link_queries$ext';
    case GLQueryType.mutation:
      return 'graph_link_mutations$ext';
    case GLQueryType.subscription:
      return 'graph_link_subscriptions$ext';
  }
}
