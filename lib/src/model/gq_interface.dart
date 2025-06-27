import 'package:retrofit_graphql/src/model/gq_type_definition.dart';

class GQInterfaceDefinition extends GQTypeDefinition {
  final Set<GQInterfaceDefinition> parents = <GQInterfaceDefinition>{};
  final Set<String> parentNames;

  GQInterfaceDefinition({
    required super.name,
    required super.nameDeclared,
    required super.fields,
    required this.parentNames,
    required super.directives,
    required super.interfaceNames,
  }) : super(derivedFromType: null);

  @override
  String toString() {
    return 'GraphQLInterface{name: $token, fields: $fields, parenNames:$parentNames}';
  }

  @override
  String serialize() {
    throw UnimplementedError();
  }
  
}
