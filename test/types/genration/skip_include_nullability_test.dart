import 'dart:io';

import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("skip_include_nullability_test", () {
    final GLGrammar g = GLGrammar();
    var parser = g.buildFrom(g.fullGrammar().end());

    var parsed = parser.parse(
        File("test/types/genration/skip_include_nullability_test.graphql").readAsStringSync());
    expect(parsed is Success, true);
    GLQueryDefinition products = g.queries["products"]!;
    var productTypeDef = products.getGeneratedTypeDefinition();
    GLField getProduct =
        productTypeDef.fields.where((field) => field.name.token == "getProduct").first;

    var getProductType = g.projectedTypes[getProduct.type.token]!;
    var nameField = getProductType.fields.where((element) => element.name.token == "name").first;
    expect(nameField.type.nullable, false);
    var serilaizer = DartSerializer(g);
    expect(serilaizer.serializeField(nameField, true), contains("String?"));

    GLField getProductList =
        productTypeDef.fields.where((field) => field.name.token == "getProductList").first;

    var getProductListType = g.projectedTypes[getProductList.type.inlineType.token]!;
    var descriptionField =
        getProductListType.fields.where((element) => element.name.token == "description").first;
    expect(descriptionField.type.nullable, false);
    var serializer = DartSerializer(g);
    expect(serializer.serializeField(descriptionField, true), contains("String?"));
  });
}
