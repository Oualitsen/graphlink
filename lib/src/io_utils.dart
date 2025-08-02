import 'dart:io';

import 'package:retrofit_graphql/src/constants.dart';

Future<File> saveSource({
  required String data,
  required String path,
  bool graphqlSource = false
  
}) {
  var file = File(path);
  if (!file.existsSync()) {
    file.createSync(recursive: true);
  }
  final header = graphqlSource ? graphqlHeadComment : fileHeadComment;
  return file.writeAsString('''
$header
$data
''');
}