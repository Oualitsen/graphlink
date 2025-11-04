import 'dart:io';

import 'package:retrofit_graphql/src/config.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/io_utils.dart';
import 'package:retrofit_graphql/src/serializers/graphq_serializer.dart';
import 'package:retrofit_graphql/src/serializers/java_serializer.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:retrofit_graphql/src/serializers/spring_server_serializer.dart';
import 'package:retrofit_graphql/src/utils.dart';

class FileWritter {
  final GQGrammar grammar;
  final GeneratorConfig config;
  final JavaSerializer serializer;
  late final SpringServerSerializer springSerializer;
  final _lastGeneratedFiles = <String>{};

  FileWritter(this.grammar, this.config)
      : serializer = JavaSerializer(
          grammar,
          inputsAsRecords: config.serverConfig?.spring?.inputAsRecord ?? false,
          typesAsRecords: config.serverConfig?.spring?.typeAsRecord ?? false,
          typesCheckForNulls: grammar.mode == CodeGenerationMode.client,
          inputsCheckForNulls: true,
        ) {
    final springConfig = config.serverConfig!.spring!;
    springSerializer = SpringServerSerializer(grammar,
        javaSerializer: serializer,
        generateSchema: springConfig.generateSchema,
        injectDataFetching: config.serverConfig?.spring?.injectDataFetching ?? false);
  }

  Future<Set<String>> generateServerClasses(
      GQGrammar grammar, DateTime started, bool dolarEscape) async {
    final springConfig = config.serverConfig!.spring!;
    final destinationDir = config.outputDir;

    final List<Future<File>> futures = [];

    for (var def in [
      ...grammar.getSerializableTypes(),
      ...grammar.interfaces.values,
      ...grammar.inputs.values,
      ...grammar.enums.values
    ]) {
      var packageName = config.serverConfig!.spring!.basePackage;
      var text = serializer.serializeToken(def, packageName);
      var imports = serializer.serializeImports(def, destinationDir);
      var fileName = serializer.getFileNameFor(def);
      var path = '${destinationDir}/${fileName}';
      var buffer = StringBuffer();
      buffer.writeln("package ${packageName}");
      buffer.writeln(imports);
      buffer.writeln(text);
      var r = saveFile(buffer.toString(), path);
      futures.add(r);
    }

    if (springConfig.generateSchema) {
      var text = GraphqSerializer(grammar).generateSchema();
      var r = saveSource(data: text, path: springConfig.schemaTargetPath!, graphqlSource: true);
      futures.add(r);
    }

    var result = await Future.wait(futures);
    stdout.writeln("Generated ${futures.length} files in ${formatElapsedTime(started)}");
    var paths = result.map((f) => f.path).toSet();
    await cleanUpObsoleteFiles(paths);
    return paths;
  }

  Future<void> cleanUpObsoleteFiles(Set<String> newFiles) async {
    var paths = _lastGeneratedFiles.where((path) => !newFiles.contains(path));
    stdout.writeln("Cleaning up ${paths.length} obsolete files");
    for (var p in paths) {
      stdout.writeln("Cleaning up ${p}");
    }
    var filesToDelete = paths.map((p) => File(p)).map((f) => f.delete());
    await Future.wait(filesToDelete);
    _lastGeneratedFiles.clear();
    _lastGeneratedFiles.addAll(newFiles);
  }

  Future<File> saveFile(String data, String path) async {
    var file = File(path);
    return file.writeAsString(data);
  }
}
