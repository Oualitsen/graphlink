import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

extension GLGrammarStrictExtension on GLParser {
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
