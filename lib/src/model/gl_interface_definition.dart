import 'package:graphlink/src/model/gl_type_definition.dart';

class GLInterfaceDefinition extends GLTypeDefinition {
  final bool fromUnion;

  ///
  /// Used only when generating type for interfaces.
  /// This will be a super class of one or more base types.
  ///
  final Set<GLTypeDefinition> _implementations = {};

  GLInterfaceDefinition({
    required super.name,
    required super.nameDeclared,
    required super.fields,
    required super.directives,
    required super.interfaceNames,
    this.fromUnion = false,
    super.derivedFromType,
    required super.extension,
    super.documentation,
  });

  @override
  String toString() {
    return 'GraphQLInterface{name: $tokenInfo, fields: $fields}';
  }

  Set<GLTypeDefinition> get implementations => Set.unmodifiable(_implementations);

  void addImplementation(GLTypeDefinition token) {
    _implementations.add(token);
  }

  void removeImplementation(String token) {
    _implementations.removeWhere((impl) => impl.token == token);
  }
}
