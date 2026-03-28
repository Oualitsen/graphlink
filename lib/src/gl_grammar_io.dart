import 'dart:io';

import 'package:graphlink/src/gl_grammar.dart';
import 'package:graphlink/src/model/gl_logical_file.dart';
import 'package:petitparser/petitparser.dart';

Future<GLLogicalFile> readLogicalFile(String path) async {
  final data = await File(path).readAsString();
  return GLLogicalFile(data, path);
}

Result parseFile(GLGrammar grammar, GLLogicalFile file,
    {bool validate = true}) {
  return grammar.parseFile(file, validate: validate);
}

List<Result> parseFiles(GLGrammar grammar, List<GLLogicalFile> files,
    {String? extraGql}) {
  return grammar.parseFiles(files, extraGql: extraGql);
}
