import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  test("equals hascode on type", () {
    final text = File("test/equals_hashcode_test/equals_hashcode.graphql").readAsStringSync();
    var g = GQGrammar(identityFields: ["id"]);
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);
    expect(g.projectedTypes.keys, containsAll(["MyProduct", "Entity", "OtherEntity"]));
    var entity = g.projectedTypes["Entity"]!;
    var entityDart = entity.toDart(g);
    expect(entityDart, contains("int get hashCode => Object.hashAll([id])"));
    expect(entityDart, contains("bool operator ==(Object other)"));

    var myProduct = g.projectedTypes["MyProduct"]!;
    var productDart = myProduct.toDart(g);
    expect(productDart, contains("int get hashCode => Object.hashAll([id, name]);"));

    // should not contain
    var otherEntity = g.projectedTypes["OtherEntity"]!;
    var otherEntityDart = otherEntity.toDart(g);
    expect(otherEntityDart, isNot(contains("int get hashCode")));
  });
}
