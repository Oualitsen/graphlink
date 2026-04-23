import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:logger/logger.dart';
import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/main.dart';
import 'package:yaml/yaml.dart';

class GraphlinkGeneratorBuilder implements Builder {
  final BuilderOptions options;
  final logger = Logger();

  /// Glob of all input files with ".graphqls" extension
  static final inputFiles = Glob('lib/**/*.graphql');
  static final inputFiles2 = Glob('lib/**/*.graphqls');
  GraphlinkGeneratorBuilder(this.options);
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
    final now = DateTime.now();
    await initAssets(buildStep);
    options.config.entries
        .where((element) => element.value is String)
        .forEach((e) {
      map[e.key] = e.value as String;
    });
    var g = GLParser(
      generateAllFieldsFragments:
          options.config["generateAllFieldsFragments"] as bool? ?? false,
      nullableFieldsRequired:
          options.config["nullableFieldsRequired"] as bool? ?? false,
      autoGenerateQueries:
          options.config["autoGenerateQueries"] as bool? ?? false,
      defaultAlias: options.config["defaultAlias"],
      operationNameAsParameter:
          options.config["operationNameAsParameter"] as bool? ?? false,
      identityFields:
          (options.config["identityFields"] as YamlList?)?.cast<String>() ?? [],
    );

    var schema = await readSchema(buildStep);
    g.parse(schema);
    await generateDartClientClasses(
        g,
        GeneratorConfig(
            schemaPaths: [],
            mode: "client",
            identityFields: g.identityFields,
            typeMappings: map,
            outputDir: outputDir),
        now);
  }

  Future<void> initAssets(BuildStep buildStep) async {
    assets.clear();

    var inputAssets = await buildStep.findAssets(inputFiles).toList();
    final inputAssets2 = await buildStep.findAssets(inputFiles2).toList();
    assets.addAll(inputAssets);
    assets.addAll(inputAssets2);
  }

  Future<String> readSchema(BuildStep buildStep) async {
    final contents =
        await Future.wait(assets.map((asset) => buildStep.readAsString(asset)));
    final schema = contents.join("\n");
    return schema;
  }
}
