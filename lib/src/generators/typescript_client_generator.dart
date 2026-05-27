import 'dart:io';

import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/io_utils.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/generators/barrel_file_handler.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript_client_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:graphlink/src/utils.dart';

Future<Set<String>> generateTypeScriptClientClasses(
    GLParser parser, GeneratorConfig config, DateTime started,
    {String? pack}) async {
  final tsConfig = config.clientConfig!.language as TypeScriptClientConfig;
  final serializer = TypeScriptSerializer(parser,
      typeMapOverrides: config.typeMappings ?? {}, importPrefix: '');
  final clientSerializer = TypeScriptClientSerializer(
    parser,
    serializer,
    generateDefaultWsAdapter: tsConfig.generateDefaultWsAdapter,
    observables: tsConfig.observables,
  );
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

  final clientFiles = <String>[];

  final clientFileName = 'graph-link-client${clientSerializer.fileExtension}';
  clientFiles.add(clientFileName);
  futures.add(writeToFile(
    data: serializer.serializeGlClass(clientSerializer.generateClient()),
    fileName: clientFileName,
    subdir: 'client',
    imports: [],
    destinationDir: destinationDir,
  ));

  if (parser.hasUploadMutations) {
    final uploadsFileName = 'graph-link-uploads${clientSerializer.fileExtension}';
    clientFiles.add(uploadsFileName);
    futures.add(writeToFile(
      data: serializer.serializeGlClass(clientSerializer.generateUploadsFile()),
      fileName: uploadsFileName,
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
    ));
  }

  final adaptersModel = clientSerializer.generateAdaptersFile(tsConfig.httpAdapter);
  if (adaptersModel != null) {
    final adaptersFileName = 'graph-link-adapters${clientSerializer.fileExtension}';
    clientFiles.add(adaptersFileName);
    futures.add(writeToFile(
      data: serializer.serializeGlClass(adaptersModel),
      fileName: adaptersFileName,
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
    ));
  }

  final result = await Future.wait(futures);
  final barrelFile = await TypeScriptBarrelFileHandler(parser, destinationDir, serializer, clientFiles: clientFiles).generate();
  stdout.writeln('Generated ${futures.length + 1} files in ${formatElapsedTime(started)}');
  final paths = result.map((f) => f.path).toSet()..add(barrelFile.path);
  await cleanUpObsoleteFiles(paths);
  return paths;
}
