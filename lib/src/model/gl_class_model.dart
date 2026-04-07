import 'package:graphlink/src/model/gl_token.dart';

/// A language-agnostic model for a generated source file.
///
/// Holds a list of fully-rendered import lines and the class/file body.
/// Each import line should already be formatted for the target language,
/// e.g. `'import java.util.Map;'` or `"import 'dart:convert';"`.
///
/// Call [toFileContent] to assemble the final file string.
class GLClassModel {
  /// Fully-rendered import lines.
  final List<String> imports;

  final List<GLToken> importDepencies;

  /// The class or file body.
  final String body;

  const GLClassModel({this.imports = const [], this.importDepencies = const[], required this.body});

  /// Assembles [imports] and [body] into the full file content string.
  String toFileContent() {
    final buf = StringBuffer();
    final nonEmpty = imports.where((l) => l.trim().isNotEmpty);
    for (final line in nonEmpty) {
      buf.writeln(line.trimRight());
    }
    if (nonEmpty.isNotEmpty) buf.writeln();
    buf.write(body.trim());
    return buf.toString();
  }
}


class GLImportContainer {
  /// Fully-rendered import lines.
  final List<String> imports = [];

  final List<GLToken> importDepencies = [];

  GLImportContainer();
  
}