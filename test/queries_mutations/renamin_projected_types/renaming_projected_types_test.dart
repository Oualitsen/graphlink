import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("renaming projected types test", () {
    final GLParser g = GLParser();

    final text = File(
            "test/queries_mutations/renamin_projected_types/renaming_projected_types_test.graphql")
        .readAsStringSync();
    g.parse(text);

    //renamed product input
    var productInput = g.inputs["ProductInput"]!;

    expect(productInput.token, contains("MyProductInput"));
    //renamed responses
    expect(g.queries["getAllProducts"]!.getGeneratedTypeDefinition().token,
        equals("MyProductResp"));
  });
}
