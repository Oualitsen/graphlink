import 'dart:io';

import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/serializers/java_serializer.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:petitparser/petitparser.dart';

const destinationDir =
    "C:/Users/Ramdane/Documents/Projects/Dentilynx/dentilynx-back/src/main/java/com/dentlynx/generated";
const packageName = "com.dentlynx.generated";
const graphqlFile =
    "C:/Users/Ramdane/Documents/Projects/Dentilynx/dentilynx-back/src/main/resources/graphql/schema.graphqls";

void main() {
  final map = {
    "ID": "String",
    "String": "String",
    "Float": "Double",
    "Int": "Integer",
    "Boolean": "Boolean",
    "Null": "null"
  };
  final grammar = GQGrammar(typeMap: map, mode: CodeGenerationMode.server);
  var file = File(graphqlFile);
  var schema = file.readAsLinesSync().join("\n");
  var parser = grammar.buildFrom(grammar.fullGrammar().end());
  var parsed = parser.parse(schema);
  final serialzer = JavaSerializer(grammar);
  // lets generate some code!

  grammar.types.forEach((k, def) {
    var text = serialzer.serializeTypeDefinition(def);
    writeToFile(text, "$k.java");
  });
  grammar.interfaces.forEach((k, def) {
    var text = serialzer.serializeInterface(def);
    writeToFile(text, "$k.java");
  });
  grammar.enums.forEach((k, def) {
    var text = serialzer.serializeEnumDefinition(def);
    writeToFile(text, "$k.java");
  });
  grammar.inputs.forEach((k, def) {
    var text = serialzer.serializeInputDefinition(def);
    writeToFile(text, "$k.java");
  });
}

void writeToFile(String data, String fileName) {
  File("$destinationDir/$fileName").writeAsStringSync("""
package $packageName;
$data
""");
  print("Done wrting to  $fileName");
}
