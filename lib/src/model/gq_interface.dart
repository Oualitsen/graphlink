import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';

class GQInterfaceDefinition extends GQTypeDefinition {
  final Set<GQInterfaceDefinition> parents = <GQInterfaceDefinition>{};
  final Set<TokenInfo> parentNames;
  final bool fromUnion;

  GQInterfaceDefinition({
    required super.name,
    required super.nameDeclared,
    required super.fields,
    required this.parentNames,
    required super.directives,
    required super.interfaceNames,
    this.fromUnion = false,
  }) : super(derivedFromType: null);

  @override
  String toString() {
    return 'GraphQLInterface{name: $tokenInfo, fields: $fields, parenNames:$parentNames}';
  }

  Set<String> getParentNames() => parentNames.map((e) => e.token).toSet();
  
}
