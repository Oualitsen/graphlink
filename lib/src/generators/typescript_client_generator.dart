import 'dart:io';

import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/io_utils.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
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

  futures.add(writeToFile(
    data: serializer.serializeGlClass(clientSerializer.generateClient()),
    fileName: 'graph-link-client${clientSerializer.fileExtension}',
    subdir: 'client',
    imports: [],
    destinationDir: destinationDir,
  ));

  if (parser.hasUploadMutations) {
    futures.add(writeToFile(
      data: serializer.serializeGlClass(clientSerializer.generateUploadsFile()),
      fileName: 'graph-link-uploads${clientSerializer.fileExtension}',
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
    ));
  }

  final adaptersModel = clientSerializer.generateAdaptersFile(tsConfig.httpAdapter);
  if (adaptersModel != null) {
    futures.add(writeToFile(
      data: serializer.serializeGlClass(adaptersModel),
      fileName: 'graph-link-adapters${clientSerializer.fileExtension}',
      subdir: 'client',
      imports: [],
      destinationDir: destinationDir,
    ));
  }

  final result = await Future.wait(futures);
  stdout.writeln('Generated ${futures.length} files in ${formatElapsedTime(started)}');
  final paths = result.map((f) => f.path).toSet();
  await cleanUpObsoleteFiles(paths);
  return paths;
}
