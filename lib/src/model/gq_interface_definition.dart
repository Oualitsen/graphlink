import 'package:retrofit_graphql/src/model/gq_type_definition.dart';

class GQInterfaceDefinition extends GQTypeDefinition {
  final bool fromUnion;

  ///
  /// Used only when generating type for interfaces.
  /// This will be a super class of one or more base types.
  ///
  final Set<GQTypeDefinition> _implementations = {};

  GQInterfaceDefinition({
    required super.name,
    required super.nameDeclared,
    required super.fields,
    required super.directives,
    required super.interfaceNames,
    this.fromUnion = false,
    super.derivedFromType,
    required super.extension,
  });

  @override
  String toString() {
    return 'GraphQLInterface{name: $tokenInfo, fields: $fields}';
  }

  Set<GQTypeDefinition> get implementations => Set.unmodifiable(_implementations);

  void addImplementation(GQTypeDefinition token) {
    _implementations.add(token);
  }

  void removeImplementation(String token) {
    _implementations.removeWhere((impl) => impl.token == token);
  }
}
