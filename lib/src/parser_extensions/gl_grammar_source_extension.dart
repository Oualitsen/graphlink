import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

/// Key under which a server controller keeps the real object next to the map it returns, so a schema
/// mapping receives the instance its service returned. GraphQL reserves the `__` prefix, so no field can collide.
const glSourceKey = '__glSource__';

extension GLGrammarSourceExtension on GLParser {
  /// Types whose values are parents of a schema mapping: the type itself, or the `@glSkipOnServer(mapTo:)` source
  /// when the mapped type is a wrapper around it.
  Set<String> get sourceTypeNames {
    final names = <String>{};
    for (final service in services.values) {
      for (final mapping in service.mappings) {
        if (mapping.forbid || mapping.identity) continue;
        final mapTo = mapping.type.getDirectiveByName(glSkipOnServer)?.getArgValueAsString(glMapTo);
        names.add(mapping.type.token);
        if (mapTo != null) names.add(mapTo);
      }
    }
    return names;
  }

  bool get carriesSources => sourceTypeNames.isNotEmpty;
}
