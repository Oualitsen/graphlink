import 'package:retrofit_graphql/src/config.dart';
import 'package:retrofit_graphql/src/main.dart';
import 'package:retrofit_graphql/src/serializers/dart_serializer.dart';
import 'package:retrofit_graphql/src/serializers/flutter_type_widget_serializer.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

const outputDir = "../my_web_app/lib/generated";

getConfig(GQGrammar g) {
  return GeneratorConfig(
      schemaPaths: [],
      mode: g.mode.name,
      identityFields: [],
      typeMappings: g.typeMap,
      outputDir: outputDir,
      clientConfig: ClientConfig(
        appLocalizationsImport: 'package:my_web_app/generated/i18n/app_localizations.dart',
          targetLanguage: "dart",
          generateAllFieldsFragments: g.generateAllFieldsFragments,
          nullableFieldsRequired: false,
          autoGenerateQueries: g.autoGenerateQueries,
          operationNameAsParameter: false,
          packageName: "my_web_app"));
}

void main() {
  test("UI View gen", () async {
    var g = GQGrammar(
        autoGenerateQueries: true,
        mode: CodeGenerationMode.client,
        generateAllFieldsFragments: true);
    var result = g.parse('''
  type SingleLabelData {
    name: String!
  }

  type Query {
    getSingleLabelData: SingleLabelData
  }

''');

    expect(result is Success, true);
    await generateClientClasses(g, getConfig(g), DateTime.now(),
        pack: 'lib/generated');
  });


  test("UI View gen enum", () async {
    var g = GQGrammar(
        autoGenerateQueries: true,
        mode: CodeGenerationMode.client,
        generateAllFieldsFragments: true);
    var result = g.parse('''
enum Gender {male, female}
  type WidgetEnumValue {
    gender: Gender
  }

  type Query {
    getSingleLabelData: WidgetEnumValue
  }

''');

    expect(result is Success, true);
    await generateClientClasses(g, getConfig(g), DateTime.now(),
        pack: 'lib/generated');
  });


  test("UI View gen nullable", () async {
    var g = GQGrammar(
        autoGenerateQueries: true,
        mode: CodeGenerationMode.client,
        generateAllFieldsFragments: true);
    var result = g.parse('''
  type SingleLabelDataNullable {
    name: String
  }

  type Query {
    getSingleLabelData: SingleLabelDataNullable
  }

''');

    expect(result is Success, true);
    await generateClientClasses(g, getConfig(g), DateTime.now(),
        pack: 'lib/generated');
  });


  test("UI View gen when field is not a string", () async {
    var g = GQGrammar(
        autoGenerateQueries: true,
        mode: CodeGenerationMode.client,
        generateAllFieldsFragments: true);
    var result = g.parse('''
  type SingleLabelDataNumber {
    age: Int!
  }

  type Query {
    getSingleLabelData: SingleLabelDataNumber
  }

''');

    expect(result is Success, true);
    await generateClientClasses(g, getConfig(g), DateTime.now(),
        pack: 'lib/generated');
  });


  test("UI View gen when field is a list", () async {
    var g = GQGrammar(
        autoGenerateQueries: true,
        mode: CodeGenerationMode.client,
        generateAllFieldsFragments: true);
    var result = g.parse('''
  type ListLabelData {
    names: [String!]!
  }

  type Query {
    getSingleLabelData: ListLabelData
  }

''');

    expect(result is Success, true);
    await generateClientClasses(g, getConfig(g), DateTime.now(),
        pack: 'lib/generated');
  });

   test("UI View gen when field is a nullable list", () async {
    var g = GQGrammar(
        autoGenerateQueries: true,
        mode: CodeGenerationMode.client,
        generateAllFieldsFragments: true);
    var result = g.parse('''
  type NullableListLabelData {
    names: [String]
  }

  type Query {
    getNullableListLabelData: NullableListLabelData
  }

''');

    expect(result is Success, true);
    await generateClientClasses(g, getConfig(g), DateTime.now(),
        pack: 'lib/generated');
  });


  test("UI View gen when field is another type", () async {
    var g = GQGrammar(
        autoGenerateQueries: true,
        mode: CodeGenerationMode.client,
        generateAllFieldsFragments: true);
    var result = g.parse('''
  type Driver {
    car: Car
  }

  type Car  {
    model: String
  }

  type Query {
    getDriver: Driver
  }

''');

    expect(result is Success, true);
    await generateClientClasses(g, getConfig(g), DateTime.now(),
        pack: 'lib/generated');
  });


  test("UI View gen when field is another type as List", () async {
    var g = GQGrammar(
        autoGenerateQueries: true,
        mode: CodeGenerationMode.client,
        generateAllFieldsFragments: true);
    var result = g.parse('''
  type Driver2 {
    cars: [Car2]
  }

  type Car2  {
    model: String
  }

  type Query {
    getDriver: Driver2
  }

''');

    expect(result is Success, true);
    await generateClientClasses(g, getConfig(g), DateTime.now(),
        pack: 'lib/generated');
  });


  test("UI View DriverWidget should import CarWidget", () async {
    var g = GQGrammar(
        autoGenerateQueries: true,
        mode: CodeGenerationMode.client,
        generateAllFieldsFragments: true);
    var result = g.parse('''
  type Driver {
    cars: [Car]
  }

  type Car  {
    model: String
  }

  type Query {
    getDriver: Driver
  }

''');

    expect(result is Success, true);
    var driverWidget = g.views['DriverWidget']!;
    expect(driverWidget.getImportDependecies(g).map((e) => e.token), containsAll(['CarWidget']));
    
  });
}
