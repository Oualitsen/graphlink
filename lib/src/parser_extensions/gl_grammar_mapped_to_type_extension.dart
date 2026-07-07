import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

extension GLGrammarMappedToTypeExtension on GLParser {
  /// Server-mode only. Resolves each type's/interface's `@glSkipOnServer(mapTo: "X")`
  /// into `GLTypeDefinition.mappedToType`. Must run after `validateSkipOnServerMapTo()`
  /// and `validateTypeFieldSkipOnServerDirectives()` have confirmed every `mapTo`
  /// value is legal (target exists and isn't itself skipped).
  void populateMappedToTypes() {
    for (final typeDef in [...types.values, ...interfaces.values]) {
      final mapTo =
          typeDef.getDirectiveByName(glSkipOnServer)?.getArgValueAsString(glMapTo);
      if (mapTo == null) continue;
      typeDef.mappedToType = types[mapTo] ?? interfaces[mapTo];
    }
  }
}
