import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/graphql_parser/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("renamin projected types test", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.fullGrammar().end());

    final text = File(
            "test/queries_mutations/renamin_projected_types/renaming_projected_types_test.graphql")
        .readAsStringSync();
    var parsed = parser.parse(text);
    var types = g.generateTypes();
    print(types);
    var file =
        File("./test/queries_mutations/renamin_projected_types/types.gq.dart");
    file.writeAsStringSync(types);

    var inputsFile =
        File("./test/queries_mutations/renamin_projected_types/inputs.gq.dart");
    inputsFile.writeAsStringSync(g.generateInputs());
    expect(parsed.isSuccess, true);
  });
}
