import 'dart:io';

import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/serializers/java_serializer.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:petitparser/petitparser.dart';
import 'package:retrofit_graphql/src/serializers/spring_server_serializer.dart';

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
  parser.parse(schema);

  final serialzer = JavaSerializer(grammar);
  final springSeriaalizer = SpringServerSerializer(grammar);
  // lets generate some code!

  grammar.getSerializableTypes().forEach((def) {
    var text = serialzer.serializeTypeDefinition(def);
    writeToFile(text, "${def.token}.java", "types", ["$packageName.enums", "$packageName.interfaces"]);
  });
  grammar.interfaces.forEach((k, def) {
    var text = serialzer.serializeInterface(def);
    writeToFile(text, "$k.java", "interfaces", ["$packageName.enums", "$packageName.types"]);
  });
  grammar.enums.forEach((k, def) {
    var text = serialzer.serializeEnumDefinition(def);
    writeToFile(text, "$k.java", "enums", []);
  });
  grammar.inputs.forEach((k, def) {
    var text = serialzer.serializeInputDefinition(def);
    writeToFile(text, "$k.java", "inputs", ["$packageName.enums"]);
  });

  grammar.services.forEach((k, def) {
    var text = springSeriaalizer.serializeService(def);
    writeToFile(
        text, "$k.java", "services", ["$packageName.enums", "$packageName.types", "$packageName.inputs"]);
  });

  grammar.services.forEach((k, def) {
    var text = springSeriaalizer.serializeController(def);
    writeToFile(text, "${k}Controller.java", "controllers",
        ["$packageName.enums", "$packageName.types", "$packageName.inputs", "$packageName.services"]);
  });

  grammar.repositories.forEach((k, def) {
    var text = springSeriaalizer.serializeRepository(def);
    writeToFile(text, "${k}.java", "repositories", ["$packageName.enums", "$packageName.types"]);
  });
}

void writeToFile(String data, String fileName, String subpackage, List<String> imports) {
  var file = File("$destinationDir/$subpackage/$fileName");
  if (!file.existsSync()) {
    file.createSync(recursive: true);
  }
  var importsText = imports.map((i) => "import $i.*;").join("\n");
  file.writeAsStringSync("""
package $packageName.$subpackage;

$importsText

$data
""");
  print("Done wrting to  $fileName");
}
