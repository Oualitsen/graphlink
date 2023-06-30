import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/dart_serializable.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';

class GQInterfaceDefinition extends GQTypeDefinition
    implements DartSerializable {
  final Set<GQInterfaceDefinition> parents = <GQInterfaceDefinition>{};
  final Set<String> parentNames;

  GQInterfaceDefinition({
    required super.name,
    required super.nameDeclared,
    required super.fields,
    required this.parentNames,
    required super.directives,
    required super.interfaceNames,
  });

  @override
  String toString() {
    return 'GraphQLInterface{name: $token, fields: $fields, parenNames:$parentNames}';
  }

  @override
  String serialize() {
    throw UnimplementedError();
  }

  @override
  String toDart(GQGrammar grammar) {
    final buffer = StringBuffer();

    buffer.write("abstract class $token");
    if (parents.isNotEmpty) {
      buffer.write(" extends ");

      for (var p in parents) {
        buffer.write(p.token);
        if (p != parents.last) {
          buffer.write(", ");
        }
      }
    }
    buffer.writeln("{");
    for (var element in fields) {
      buffer.writeln(element.toDart(grammar));
    }

    buffer.write("$token({");
    for (int i = 0; i < fields.length; i++) {
      final element = fields[i];
      buffer.write("required this.${element.name}, ");
    }
    buffer.writeln("});");

    buffer.writeln("}");

    return buffer.toString();
  }
}
