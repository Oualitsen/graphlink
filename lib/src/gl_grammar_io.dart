import 'dart:io';

import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_logical_file.dart';

Future<GLLogicalFile> readLogicalFile(String path) async {
  final data = await File(path).readAsString();
  return GLLogicalFile(data, path);
}

void parseFile(GLParser grammar, GLLogicalFile file, {bool validate = true}) {
  grammar.parseFile(file, validate: validate);
}

parseFiles(GLParser grammar, List<GLLogicalFile> files, {String? extraGql}) {
  grammar.parseFiles(files, extraGql: extraGql);
}
