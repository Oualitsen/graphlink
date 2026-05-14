import 'dart:io';

import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/io_utils.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/flutter_type_widget_serializer.dart';
import 'package:graphlink/src/utils.dart';

Future<Set<String>> generateDartClientClasses(
    GLParser parser, GeneratorConfig config, DateTime started,
    {String? pack}) async {
  final dartConfig = config.clientConfig!.language as DartClientConfig;
  final serializer = DartSerializer(parser,
      generateJsonMethods: true,
      typeMapOverrides: config.typeMappings ?? {});
  final clientSerializer = DartClientSerializer(parser, serializer,
      generateAdapters: dartConfig.generateAdapters,
      httpAdapter: dartConfig.httpAdapter);
  final futures = <Future<File>>[];
  final destinationDir = config.outputDir;
  final packageName = dartConfig.packageName;
  final prefix =
      'package:$packageName/${(pack ?? config.outputDir).replaceFirst("lib/", "")}';
  final viewSerializer = FlutterTypeWidgetSerializer(parser, serializer, true);

  parser.enums.forEach((k, def) {
    futures.add(writeToFile(
      data: serializer.serializeEnumDefinition(def, ''),
      fileName: serializer.getFileNameFor(def),
      subdir: 'enums',
      imports: [],
      destinationDir: destinationDir,
    ));
  });

  parser.inputs.forEach((k, def) {
    futures.add(writeToFile(
      data: serializer.serializeInputDefinition(def, prefix),
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
      data: serializer.serializeTypeDefinition(def, prefix),
      fileName: serializer.getFileNameFor(def),
      subdir: subdir,
      imports: [],
      destinationDir: destinationDir,
    ));
  });

  if (dartConfig.generateUiTypes) {
    parser.views.forEach((k, def) {
      final appLocImport = dartConfig.appLocalizationsImport;
      if (appLocImport != null) {
        def.addImport(appLocImport);
      }
      futures.add(writeToFile(
        data: viewSerializer.serializeType(def, prefix),
        fileName: serializer.getFileNameFor(def),
        subdir: 'widgets',
        imports: [],
        destinationDir: destinationDir,
      ));
    });
  }

  futures.add(writeToFile(
    data: serializer.serializeGlClass(clientSerializer.generateClient(prefix), importPrefix: prefix),
    fileName: 'graph_link_client${clientSerializer.fileExtension}',
    subdir: 'client',
    imports: [],
    destinationDir: destinationDir,
  ));

  if (parser.hasUploadMutations) {
    futures.add(writeToFile(
      data: serializer.serializeGlClass(clientSerializer.generateUploadsFile(), importPrefix: prefix),
      fileName: 'graph_link_uploads${clientSerializer.fileExtension}',
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
    ));
  }

  if (dartConfig.generateAdapters) {
    final httpAdapter = dartConfig.httpAdapter;
    if (httpAdapter != DartHttpAdapter.none) {
      futures.add(writeToFile(
        data: serializer.serializeGlClass(
            httpAdapter == DartHttpAdapter.dio
                ? clientSerializer.generateDioAdapterFile()
                : clientSerializer.generateHttpAdapterFile(),
            importPrefix: prefix),
        fileName: httpAdapter == DartHttpAdapter.dio
            ? 'graph_link_dio_adapter${clientSerializer.fileExtension}'
            : 'graph_link_http_adapter${clientSerializer.fileExtension}',
        subdir: 'client',
        imports: [],
        destinationDir: destinationDir,
      ));
    }
    if (parser.hasSubscriptions) {
      futures.add(writeToFile(
        data: serializer.serializeGlClass(clientSerializer.generateDefaultWebSocketAdapterFile(), importPrefix: prefix),
        fileName: 'graph_link_websocket_adapter${clientSerializer.fileExtension}',
        subdir: 'client',
        imports: [],
        destinationDir: destinationDir,
      ));
    }
  }

  final result = await Future.wait(futures);
  stdout.writeln('Generated ${futures.length} files in ${formatElapsedTime(started)}');
  final paths = result.map((f) => f.path).toSet();
  await cleanUpObsoleteFiles(paths);
  return paths;
}
