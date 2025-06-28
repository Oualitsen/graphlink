import 'dart:io';

import 'package:retrofit_graphql/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';
import 'package:retrofit_graphql/src/serializers/java_serializer.dart';

void main() {
  test("Dart type serialization", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"]);
    final text = File("test/serializers/dart/types/type_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var user = g.getType("User");
    var javaSerialzer = DartSerializer(g);
    var class_ = javaSerialzer.serializeTypeDefinition(user);
    print(class_);
  });

  test("Dart input serialization", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"]);
    final text = File("test/serializers/dart/types/type_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var user = g.inputs["UserInput"];
    var javaSerialzer = DartSerializer(g);
    var class_ = javaSerialzer.serializeInputDefinition(user!);
    print(class_);
  });

  test("Dart interface serialization", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"]);
    final text = File("test/serializers/dart/types/interface_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var entity = g.interfaces["Interface1"]!;
    var javaSerialzer = DartSerializer(g);
    var class_ = javaSerialzer.serializeInterface(entity).trim();
    expect(class_, startsWith("abstract class Interface1 {"));
    expect(class_, endsWith("}"));
    for (var e in entity.fields) {
      expect(class_, contains(javaSerialzer.serializeGetterDeclaration(e)));
    }
  });

  test("Dart interface implementing one interface serialization", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"]);
    final text = File("test/serializers/dart/types/interface_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var entity = g.interfaces["Interface2"]!;
    var javaSerialzer = DartSerializer(g);
    var class_ = javaSerialzer.serializeInterface(entity).trim();

    expect(class_, startsWith("abstract class Interface2 extends IBase {"));
    expect(class_, endsWith("}"));
    for (var e in entity.fields) {
      expect(class_, contains(javaSerialzer.serializeGetterDeclaration(e)));
    }
  });

  test("Dart interface implementing multiple interface serialization", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"]);
    final text = File("test/serializers/dart/types/interface_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var entity = g.interfaces["Interface3"]!;
    var javaSerialzer = DartSerializer(g);
    var class_ = javaSerialzer.serializeInterface(entity).trim();
    expect(class_, startsWith("abstract class Interface3 extends IBase, IBase2 {"));
    expect(class_, endsWith("}"));
    for (var e in entity.fields) {
      expect(class_, contains(javaSerialzer.serializeGetterDeclaration(e)));
    }
    print(class_);
  });
}
