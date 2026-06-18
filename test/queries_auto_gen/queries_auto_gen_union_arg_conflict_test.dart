import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  test(
      "union members sharing a field with different arg types do not cause a variable type conflict",
      () {
    final text = File(
            "test/queries_auto_gen/queries_auto_gen_union_arg_conflict.graphql")
        .readAsStringSync();
    final g = GLParser(
        generateAllFieldsFragments: true, autoGenerateQueries: true);

    // Before the fix this throws a ParseException:
    // "Variable $bFilter is used for arguments of different types (AFilter vs BFilter)"
    expect(() => g.parse(text), returnsNormally);

    // Variables from the auto-generated query must have the correct types —
    // no cross-type contamination from the union's synthetic interface.
    final query = g.queries['getContainer']!;
    final argsByName = {for (var a in query.arguments) a.token: a.type.token};
    // $aFilter (from TypeA's all-fields fragment) must be typed AFilter, not BFilter.
    if (argsByName.containsKey(r'$aFilter')) {
      expect(argsByName[r'$aFilter'], equals('AFilter'));
    }
    if (argsByName.containsKey(r'$bFilter')) {
      expect(argsByName[r'$bFilter'], equals('BFilter'));
    }
  });
}
