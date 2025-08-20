import 'package:retrofit_graphql/src/model/gq_type_definition.dart';

class GQInterfaceDefinition extends GQTypeDefinition {
  final bool fromUnion;

  GQInterfaceDefinition({
    required super.name,
    required super.nameDeclared,
    required super.fields,
    required super.directives,
    required super.interfaceNames,
    this.fromUnion = false,
  }) : super(derivedFromType: null);

  @override
  String toString() {
    return 'GraphQLInterface{name: $tokenInfo, fields: $fields}';
  }

  
}
