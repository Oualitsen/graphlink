import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("query_depency_test", () {
    final GLParser g = GLParser();

    final text = File("test/queries_mutations/query_depency_test.graphql")
        .readAsStringSync();
    g.parse(text);

    expect(g.queries["ProductQuery"]!.fragments(g).map((e) => e.token),
        contains("ProductFragment"));
  });
}
