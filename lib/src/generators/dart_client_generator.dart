import 'dart:io';

import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/io_utils.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/dart_client_serializer.dart';
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
      generateJsonMethods: true,
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

  final clientFileName = 'graph_link_client${clientSerializer.fileExtension}';
  clientFiles.add(clientFileName);
  futures.add(writeToFile(
    data: serializer.serializeGlClass(clientSerializer.generateClient()),
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
      final wsFileName = 'graph_link_websocket_adapter${clientSerializer.fileExtension}';
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
