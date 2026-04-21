import 'dart:io';

import 'package:graphlink/src/constants.dart';

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