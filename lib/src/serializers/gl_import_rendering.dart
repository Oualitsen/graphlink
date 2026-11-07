import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/serializers/gl_type_naming.dart';

abstract class GLImportRendering extends GLTypeNaming {
  GLImportRendering(super.grammar, {super.typeMapOverrides, required super.importPrefix});

  String getFileNameFor(GLToken token);

  String serializeImportToken(GLToken token);
  String serializeImport(String import);

  String serializeWithImport(GLToken token, String data) {
    var imports = serializeImports(token);
    var buffer = StringBuffer();
    buffer.writeln(imports);
    buffer.writeln();
    buffer.writeln(data);
    return buffer.toString();
  }

  String serializeImports(GLToken token) {
    var deps = token.getImportDependecies(grammar).where((d) => d != token).toSet();
    if (token is GLInterfaceDefinition) {
      deps = {...deps, ...token.getSerializableImplementations(mode)};
    }
    var imports = token.getImports(grammar);
    if (deps.isEmpty && imports.isEmpty) {
      return "";
    }
    var buffer = StringBuffer();
    for (var dep in deps) {
      var import = serializeImportToken(dep);
      if (import.isNotEmpty) {
        buffer.writeln(import);
      }
    }
    for (var i in imports) {
      var import = serializeImport(i);
      if (import.isNotEmpty) {
        buffer.writeln(import);
      }
    }
    return buffer.toString();
  }

  /// Serializes a [GLClassModel] to a source file string.
  ///
  /// When [withImports] is `true` (default) the import block is prepended to
  /// the body, producing a self-contained file.  Pass `false` to get just the
  /// class body — useful when embedding the class inside a larger file that
  /// already manages its own imports (e.g. the Dart single-file output).
  ///
  /// [importPrefix] is forwarded to [serializeImportToken] when resolving
  /// [GLClassModel.importDepencies] into language-specific import lines.
  /// Language-specific subclasses should override this to handle token
  /// dependencies via [serializeImportToken].
  String serializeGlClass(GLClassModel theClass,
      {bool withImports = true}) {
    if (!withImports) return theClass.body.trim();
    return theClass.toFileContent();
  }
}
