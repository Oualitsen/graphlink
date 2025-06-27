import 'dart:io';

import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_queries.dart';
import 'package:retrofit_graphql/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("skip_include_nullability_test", () {
    final GQGrammar g = GQGrammar();
    var parser = g.buildFrom(g.fullGrammar().end());

    var parsed = parser.parse(
        File("test/types/genration/skip_include_nullability_test.graphql")
            .readAsStringSync());
    expect(parsed is Success, true);
    GQQueryDefinition products = g.queries["products"]!;
    var productTypeDef = products.getGeneratedTypeDefinition();
    GQField getProduct = productTypeDef.fields
        .where((field) => field.name == "getProduct")
        .first;

    var getProductType = g.projectedTypes[getProduct.type.token]!;
    var nameField =
        getProductType.fields.where((element) => element.name == "name").first;
    expect(nameField.type.nullable, false);
    var serilaizer = DartSerializer(g);
    expect(serilaizer.serializeField(nameField), contains("String?"));

    GQField getProductList = productTypeDef.fields
        .where((field) => field.name == "getProductList")
        .first;

    var getProductListType =
        g.projectedTypes[getProductList.type.inlineType.token]!;
    var descriptionField = getProductListType.fields
        .where((element) => element.name == "description")
        .first;
    expect(descriptionField.type.nullable, false);
    var serializer = DartSerializer(g);
    expect(serializer.serializeField(descriptionField), contains("String?"));
  });
}
