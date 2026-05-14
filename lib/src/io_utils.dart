import 'dart:io';

import 'package:graphlink/src/constants.dart';

final lastGeneratedFiles = <String>{};

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
  var file = File(path);
  if (!file.existsSync()) {
    file.createSync(recursive: true);
  }
  final header = graphqlSource
      ? graphqlHeadComment
      : typescriptSource
          ? fileHeadComment
          : "$fileHeadComment$dartIgnoreForFile\n";
  return file.writeAsString('''
$header
$data
''');
}