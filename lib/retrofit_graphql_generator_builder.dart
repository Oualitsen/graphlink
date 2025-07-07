import 'dart:io';

import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:logger/logger.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/serializers/dart_client_serializer.dart';
import 'package:retrofit_graphql/src/serializers/dart_serializer.dart';
import 'package:retrofit_graphql/src/serializers/gq_serializer.dart';
import 'package:yaml/yaml.dart';

class RetrofitGraphqlGeneratorBuilder implements Builder {
  final BuilderOptions options;
  final logger = Logger();

  /// Glob of all input files with ".graphqls" extension
  static final inputFiles = Glob('lib/**/*.graphql');
  static final inputFiles2 = Glob('lib/**/*.graphqls');
  RetrofitGraphqlGeneratorBuilder(this.options);
  static const outputDir = 'lib/generated';
  final map = {
    "ID": "String",
    "String": "String",
    "Float": "double",
    "Int": "int",
    "Boolean": "bool",
    "Null": "null"
  };
  final List<AssetId> assets = [];

  @override
  Map<String, List<String>> get buildExtensions => {
        '.graphql': ['.gq.dart']
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    await initAssets(buildStep);
    options.config.entries.where((element) => element.value is String).forEach((e) {
      map[e.key] = e.value as String;
    });
    var g = GQGrammar(
      typeMap: map,
      generateAllFieldsFragments: options.config["generateAllFieldsFragments"] as bool? ?? false,
      nullableFieldsRequired: options.config["nullableFieldsRequired"] as bool? ?? false,
      autoGenerateQueries: options.config["autoGenerateQueries"] as bool? ?? false,
      defaultAlias: options.config["defaultAlias"],
      operationNameAsParameter: options.config["operationNameAsParameter"] as bool? ?? false,
      identityFields: (options.config["identityFields"] as YamlList?)?.cast<String>() ?? [],
    );

    final GqSerializer serializer = DartSerializer(g);

    var parser = g.buildFrom(g.start());

    var schema = await readSchema(buildStep);
    parser.parse(schema);
    final dcs = DartClientSerializer(g);

    final inputs = dcs.serializeInputs(serializer);
    final enums = dcs.generateEnums(serializer);
    final types = dcs.generateTypes(serializer);
    final client = dcs.serializeClient();

    var dir = Directory(outputDir);
    var exists = await dir.exists();
    if (!exists) {
      await dir.create(recursive: true);
    }

    await File('$outputDir/$inputsFileName.dart').writeAsString(inputs);
    await File('$outputDir/$enumsFileName.dart').writeAsString(enums);
    await File('$outputDir/$typesFileName.dart').writeAsString(types);
    await File('$outputDir/$clientFileName.dart').writeAsString(client);
  }

  Future<void> initAssets(BuildStep buildStep) async {
    assets.clear();

    var inputAssets = await buildStep.findAssets(inputFiles).toList();
    final inputAssets2 = await buildStep.findAssets(inputFiles2).toList();
    assets.addAll(inputAssets);
    assets.addAll(inputAssets2);
  }

  Future<String> readSchema(BuildStep buildStep) async {
    final contents = await Future.wait(assets.map((asset) => buildStep.readAsString(asset)));
    final schema = contents.join("\n");
    return schema;
  }
}
