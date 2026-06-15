import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

extension GLGrammarStrictExtension on GLParser {
  ///
  /// @glStrict — synthesizes `<Type>Projection` for every object type and
  /// interface and stores it in [GLParser.serverProjections], keyed by the
  /// projection's own name (`<Type>Projection`).
  ///
  void populateServerProjections() {
    var newInterfaces = <GLInterfaceDefinition>[];
    for (final type in typesWithNoResolvers) {
      final projection = type.toProjectionInterface(this);
      type.addInterface(projection);
      newInterfaces.add(projection);
    }
    for (final iface in interfaces.values) {
      final projection = iface.toProjectionInterface(this);
      iface.addInterface(projection);
      newInterfaces.add(projection);
    }
    newInterfaces.forEach(addInterfaceDefinition);
  }

  ///
  /// @glServerLenient — for every object type or interface marked
  /// @glServerLenient, rewrites all of its own fields to be fully nullable
  /// (including list element types), restoring the pre-@glStrict behavior
  /// where server-generated getters/setters/constructors never enforced
  /// non-null fields. Does not affect GL<Type>Projection, which is already
  /// all-nullable by design.
  ///
  void applyServerLenientNullability() {
    final lenientTypes = [...typesWithNoResolvers, ...interfaces.values]
        .where((t) => t.hasDirective(glServerLenient));

    for (final type in lenientTypes) {
      for (final field in type.getFields()) {
        type.replaceField(field.ofType(_toFullyNullable(field.type)));
      }
    }
  }
}

/// Rewrites [type] (and, recursively, any list element type) to nullable.
GLType _toFullyNullable(GLType type) {
  if (type is GLListType) {
    return GLListType(_toFullyNullable(type.type), true);
  }
  return GLType(type.tokenInfo, true);
}
