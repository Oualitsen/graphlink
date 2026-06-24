import 'dart:io';

import 'package:graphlink/src/constants.dart';

final lastGeneratedFiles = <String>{};
final _outputHashCache = <String, int>{};
var _writeCount = 0;

void resetWriteCount() => _writeCount = 0;
int get writeCount => _writeCount;

Future<void> cleanUpObsoleteFiles(Set<String> newFiles) async {
  final stale = lastGeneratedFiles.where((p) => !newFiles.contains(p)).toList();
  if (stale.isNotEmpty) {
    stdout.writeln('Cleaning up ${stale.length} obsolete files');
    for (final p in stale) {
      stdout.writeln('Cleaning up $p');
    }
    await Future.wait(stale.map((p) => File(p).delete()));
  }
  lastGeneratedFiles
    ..clear()
    ..addAll(newFiles);
}

Future<File> writeToFile({
  required String data,
  required String fileName,
  required String subdir,
  required Iterable<String> imports,
  required String destinationDir,
  String? packageName,
  bool appendStar = false,
}) {
  final path = '$destinationDir/$subdir/$fileName';
  final buffer = StringBuffer();
  if (packageName != null) {
    buffer.writeln('package $packageName.$subdir;');
  }
  if (imports.isNotEmpty) {
    buffer.writeln(imports.map((i) => appendStar ? 'import $i.*;' : 'import $i;').join('\n'));
  }
  buffer.writeln(data);
  return saveSource(data: buffer.toString(), path: path);
}

Future<File> saveSource({
  required String data,
  required String path,
  bool graphqlSource = false,
  bool typescriptSource = false,
}) {
  final header = graphqlSource
      ? graphqlHeadComment
      : typescriptSource
          ? fileHeadComment
          : "$fileHeadComment$dartIgnoreForFile\n";
  final content = '$header\n$data\n';
  final hash = content.hashCode;
  if (_outputHashCache[path] == hash) {
    return Future.value(File(path));
  }
  _outputHashCache[path] = hash;
  _writeCount++;
  var file = File(path);
  if (!file.existsSync()) {
    file.createSync(recursive: true);
  }
  // Write synchronously so each file is fully populated the instant it is
  // generated, rather than left empty until a deferred Future.wait flushes
  // thousands of concurrent writeAsString calls at the end.
  file.writeAsStringSync(content);
  return Future.value(file);
}