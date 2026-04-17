import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/main.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/utils.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

const outputDir = "../my_web_app/lib/generated";

getConfig(GLParser g) {
  return GeneratorConfig(
      schemaPaths: [],
      mode: g.mode.name,
      identityFields: [],
      typeMappings: g.typeMap,
      outputDir: outputDir,
      clientConfig: ClientConfig(
          dart: DartClientConfig(
              appLocalizationsImport:
                  'package:my_web_app/generated/i18n/app_localizations.dart',
              generateAllFieldsFragments: g.generateAllFieldsFragments,
              nullableFieldsRequired: false,
              autoGenerateQueries: g.autoGenerateQueries,
              operationNameAsParameter: false,
              packageName: "my_web_app")));
}

void main() {
  test("UI View gen", () async {
    var g = GLParser(
        autoGenerateQueries: true,
        mode: CodeGenerationMode.client,
        generateAllFieldsFragments: true);
    g.parse('''
  type SingleLabelData {
    name: String!
  }

  type Query {
    getSingleLabelData: SingleLabelData
  }

''');

    await generateDartClientClasses(g, getConfig(g), DateTime.now(),
        pack: 'lib/generated');
  });

  test("UI View gen enum", () async {
    var g = GLParser(
        autoGenerateQueries: true,
        mode: CodeGenerationMode.client,
        generateAllFieldsFragments: true);
    g.parse('''
enum Gender {male, female}
  type WidgetEnumValue {
    gender: Gender
  }

  type Query {
    getSingleLabelData: WidgetEnumValue
  }

''');

    await generateDartClientClasses(g, getConfig(g), DateTime.now(),
        pack: 'lib/generated');
  });

  test("UI View gen nullable", () async {
    var g = GLParser(
        autoGenerateQueries: true,
        mode: CodeGenerationMode.client,
        generateAllFieldsFragments: true);
    g.parse('''
  type SingleLabelDataNullable {
    name: String
  }

  type Query {
    getSingleLabelData: SingleLabelDataNullable
  }

''');

    await generateDartClientClasses(g, getConfig(g), DateTime.now(),
        pack: 'lib/generated');
  });

  test("UI View gen when field is not a string", () async {
    var g = GLParser(
        autoGenerateQueries: true,
        mode: CodeGenerationMode.client,
        generateAllFieldsFragments: true);
    g.parse('''
  type SingleLabelDataNumber {
    age: Int!
  }

  type Query {
    getSingleLabelData: SingleLabelDataNumber
  }

''');

    await generateDartClientClasses(g, getConfig(g), DateTime.now(),
        pack: 'lib/generated');
  });

  test("UI View gen when field is a list", () async {
    var g = GLParser(
        autoGenerateQueries: true,
        mode: CodeGenerationMode.client,
        generateAllFieldsFragments: true);
    g.parse('''
  type ListLabelData {
    names: [String!]!
  }

  type Query {
    getSingleLabelData: ListLabelData
  }

''');

    await generateDartClientClasses(g, getConfig(g), DateTime.now(),
        pack: 'lib/generated');
  });

  test("UI View gen when field is a nullable list", () async {
    var g = GLParser(
        autoGenerateQueries: true,
        mode: CodeGenerationMode.client,
        generateAllFieldsFragments: true);
    g.parse('''
  type NullableListLabelData {
    names: [String]
  }

  type Query {
    getNullableListLabelData: NullableListLabelData
  }

''');

    await generateDartClientClasses(g, getConfig(g), DateTime.now(),
        pack: 'lib/generated');
  });

  test("UI View gen when field is another type", () async {
    var g = GLParser(
        autoGenerateQueries: true,
        mode: CodeGenerationMode.client,
        generateAllFieldsFragments: true);
    g.parse('''
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

    await generateDartClientClasses(g, getConfig(g), DateTime.now(),
        pack: 'lib/generated');
  });

  test("UI View gen when field is another type as List", () async {
    var g = GLParser(
        autoGenerateQueries: true,
        mode: CodeGenerationMode.client,
        generateAllFieldsFragments: true);
    g.parse('''
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

    await generateDartClientClasses(g, getConfig(g), DateTime.now(),
        pack: 'lib/generated');
  });

  

  test("UI View should not generate for @internal", () async {
    var g = GLParser(
        autoGenerateQueries: true,
        mode: CodeGenerationMode.client,
        generateAllFieldsFragments: true);
    g.parse('''
  type Person ${glInternal} {
    name: String!
  }

''');

    expect(g.views[widgetName("Person")], isNull);
  });

 
}
