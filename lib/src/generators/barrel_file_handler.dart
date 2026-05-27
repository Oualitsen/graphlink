import 'dart:io';

import 'package:graphlink/src/io_utils.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';

abstract class GLBarrelFileHandler {
  final GLParser parser;
  final String destinationDir;
  final List<String> clientFiles;

  GLBarrelFileHandler(this.parser, this.destinationDir, {this.clientFiles = const []});

  String get barrelFileName;
  bool get isTypeScript;
  String exportLine(String subdir, String fileName);
  String fileNameFor(GLToken def);

  Future<File> generate() {
    final lines = <String>[];

    parser.enums.forEach((_, def) {
      lines.add(exportLine('enums', fileNameFor(def)));
    });

    parser.inputs.forEach((_, def) {
      lines.add(exportLine('inputs', fileNameFor(def)));
    });

    final isClient = parser.mode == CodeGenerationMode.client;
    final types = isClient ? parser.projectedTypes : parser.types;
    final interfaces = isClient ? parser.projectedInterfaces : parser.interfaces;

    types.forEach((_, def) {
      lines.add(exportLine('types', fileNameFor(def)));
    });

    interfaces.forEach((_, def) {
      lines.add(exportLine('interfaces', fileNameFor(def)));
    });

    for (final fileName in clientFiles) {
      lines.add(exportLine('client', fileName));
    }

    return saveSource(
      data: lines.join('\n'),
      path: '$destinationDir/$barrelFileName',
      typescriptSource: isTypeScript,
    );
  }
}

class DartBarrelFileHandler extends GLBarrelFileHandler {
  final DartSerializer serializer;

  DartBarrelFileHandler(super.parser, super.destinationDir, this.serializer, {super.clientFiles = const []});

  @override
  String get barrelFileName => 'graphlink.dart';

  @override
  bool get isTypeScript => false;

  @override
  String exportLine(String subdir, String fileName) => "export '$subdir/$fileName';";

  @override
  String fileNameFor(GLToken def) => serializer.getFileNameFor(def);
}

class TypeScriptBarrelFileHandler extends GLBarrelFileHandler {
  final TypeScriptSerializer serializer;

  TypeScriptBarrelFileHandler(super.parser, super.destinationDir, this.serializer, {super.clientFiles = const []});

  @override
  String get barrelFileName => 'graphlink.ts';

  @override
  bool get isTypeScript => true;

  @override
  String exportLine(String subdir, String fileName) =>
      "export * from './$subdir/${fileName.replaceFirst('.ts', '')}';";

  @override
  String fileNameFor(GLToken def) => serializer.getFileNameFor(def);
}
