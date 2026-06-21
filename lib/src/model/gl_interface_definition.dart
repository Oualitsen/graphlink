import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/utils.dart';

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

  Set<GLTypeDefinition> getSerializableImplementations(CodeGenerationMode mode) {
    return Set.unmodifiable(_collectImplementations(mode, <String>{}));
  }

  /// Flattens implementations transitively. A member of [_implementations] may
  /// itself be a sub-interface (e.g. `Vehicle implements Entity` registers the
  /// `Vehicle` interface against `Entity`). Sub-interfaces are never valid
  /// `__typename` values on the wire, so we never emit them as concrete cases;
  /// instead we descend into their own concrete implementations. [visited]
  /// guards against cyclic interface graphs.
  Set<GLTypeDefinition> _collectImplementations(
      CodeGenerationMode mode, Set<String> visited) {
    final result = <GLTypeDefinition>{};
    for (final type in _implementations) {
      if (type is GLInterfaceDefinition) {
        if (visited.add(type.token)) {
          result.addAll(type._collectImplementations(mode, visited));
        }
      } else if (filterByParserMode(type, mode)) {
        result.add(type);
      }
    }
    return result;
  }

  void addImplementation(GLTypeDefinition token) {
    _implementations.add(token);
  }

  void removeImplementation(String token) {
    _implementations.removeWhere((impl) => impl.token == token);
  }
}
