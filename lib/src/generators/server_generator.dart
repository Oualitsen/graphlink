import 'dart:io';

import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/io_utils.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/express_apollo_server_serializer.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/spring_server_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:graphlink/src/utils.dart';

Future<Set<String>> generateServerClasses(
    GLParser grammar, GeneratorConfig config, DateTime started) async {
  final serverLang = config.serverConfig!.language;
  if (serverLang is ExpressApolloServerConfig) {
    return _generateExpressApolloClasses(grammar, config, started);
  }
  final springConfig = serverLang as SpringServerConfig;
  final packageName = springConfig.basePackage;
  final destinationDir = config.outputDir;
  final serializer = JavaSerializer(
    grammar,
    inputsAsRecords: springConfig.inputAsRecord,
    typesAsRecords: springConfig.typeAsRecord,
    inputsCheckForNulls: true,
    typesCheckForNulls: grammar.mode == CodeGenerationMode.client,
    immutableInputFields: springConfig.immutableInputFields,
    immutableTypeFields: springConfig.immutableTypeFields,
    typeMapOverrides: config.typeMappings ?? {},
  );
  final springSerializer = SpringServerSerializer(grammar,
      javaSerializer: serializer,
      generateSchema: springConfig.generateSchema,
      injectDataFetching: springConfig.injectDataFetching,
      reactive: springConfig.reactive,
      useSpringSecurity: springConfig.useSpringSecurity);
  final futures = <Future<File>>[];

  grammar.getSerializableTypes().forEach((def) {
    futures.add(writeToFile(
      data: serializer.serializeTypeDefinition(def, packageName),
      fileName: serializer.getFileNameFor(def),
      subdir: 'types',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
      appendStar: true,
    ));
  });
  grammar.getSerializableInterfaces().forEach((def) {
    futures.add(writeToFile(
      data: serializer.serializeTypeDefinition(def, packageName),
      fileName: serializer.getFileNameFor(def),
      subdir: 'interfaces',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
      appendStar: true,
    ));
  });
  grammar.getSerializableEnums().forEach((def) {
    futures.add(writeToFile(
      data: serializer.serializeEnumDefinition(def, packageName),
      fileName: serializer.getFileNameFor(def),
      subdir: 'enums',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
      appendStar: true,
    ));
  });
  grammar.getSerializableInputs().forEach((def) {
    futures.add(writeToFile(
      data: serializer.serializeInputDefinition(def, packageName),
      fileName: serializer.getFileNameFor(def),
      subdir: 'inputs',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
      appendStar: true,
    ));
  });
  grammar.services.forEach((k, def) {
    futures.add(writeToFile(
      data: springSerializer.serializeService(def, packageName),
      fileName: serializer.getFileNameFor(def),
      subdir: 'services',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
      appendStar: true,
    ));
  });
  grammar.controllers.forEach((k, def) {
    futures.add(writeToFile(
      data: springSerializer.serializeController(def, packageName),
      fileName: serializer.getFileNameFor(def),
      subdir: 'controllers',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
      appendStar: true,
    ));
  });
  grammar.repositories.forEach((k, def) {
    futures.add(writeToFile(
      data: springSerializer.serializeRepository(def, packageName),
      fileName: '$k.java',
      subdir: 'repositories',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
      appendStar: true,
    ));
  });

  if (springConfig.generateSchema) {
    futures.add(saveSource(
      data: GLGraphqlSerializer(grammar).generateSchema(),
      path: springConfig.schemaTargetPath!,
      graphqlSource: true,
    ));
  }

  final result = await Future.wait(futures);
  stdout.writeln('Generated ${futures.length} files in ${formatElapsedTime(started)}');
  final paths = result.map((f) => f.path).toSet();
  await cleanUpObsoleteFiles(paths);
  return paths;
}

Future<Set<String>> _generateExpressApolloClasses(
    GLParser grammar, GeneratorConfig config, DateTime started) async {
  final apolloConfig = config.serverConfig!.language as ExpressApolloServerConfig;
  final destinationDir = config.outputDir;
  final tsSerializer = TypeScriptSerializer(grammar,
      typeMapOverrides: config.typeMappings ?? {});
  final serverSerializer = ExpressApolloServerSerializer(grammar, tsSerializer, apolloConfig);
  final futures = <Future<File>>[];

  futures.add(saveSource(
    data: serverSerializer.serializeTypeDefs(),
    path: '$destinationDir/typeDefs.ts',
    typescriptSource: true,
  ));

  grammar.getSerializableEnums().forEach((def) {
    futures.add(saveSource(
      data: tsSerializer.serializeEnumDefinition(def, ''),
      path: '$destinationDir/enums/${tsSerializer.getFileNameFor(def)}',
      typescriptSource: true,
    ));
  });
  grammar.getSerializableInputs().forEach((def) {
    futures.add(saveSource(
      data: tsSerializer.serializeInputDefinition(def, ''),
      path: '$destinationDir/inputs/${tsSerializer.getFileNameFor(def)}',
      typescriptSource: true,
    ));
  });
  grammar.getSerializableTypes().forEach((def) {
    futures.add(saveSource(
      data: tsSerializer.serializeTypeDefinition(def, ''),
      path: '$destinationDir/types/${tsSerializer.getFileNameFor(def)}',
      typescriptSource: true,
    ));
  });

  grammar.services.forEach((_, service) {
    futures.add(saveSource(
      data: serverSerializer.serializeService(service),
      path: '$destinationDir/services/${service.token.toKebabCase()}.ts',
      typescriptSource: true,
    ));
    final guard = serverSerializer.serializeGuard(service);
    if (guard != null) {
      final guardName = '${service.token.replaceFirst('Service', '')}Guard';
      futures.add(saveSource(
        data: guard,
        path: '$destinationDir/guards/${guardName.toKebabCase()}.ts',
        typescriptSource: true,
      ));
    }
    final loader = serverSerializer.serializeLoader(service);
    if (loader != null) {
      final loaderFile = '${service.token.replaceFirst('Service', '').toKebabCase()}-loaders.ts';
      futures.add(saveSource(
        data: loader,
        path: '$destinationDir/loaders/$loaderFile',
        typescriptSource: true,
      ));
    }
  });

  futures.add(saveSource(
    data: serverSerializer.serializeContext(),
    path: '$destinationDir/context.ts',
    typescriptSource: true,
  ));

  final hasUploads = grammar.uploadScalarNames.isNotEmpty &&
      grammar.services.values.any((s) =>
          s.fields.any((f) => f.arguments.any((a) =>
              grammar.uploadScalarNames.contains(a.type.firstType.token))));
  if (hasUploads) {
    futures.add(saveSource(
      data: serverSerializer.serializeFileUploadType(),
      path: '$destinationDir/file-upload.ts',
      typescriptSource: true,
    ));
    futures.add(saveSource(
      data: serverSerializer.serializeGraphqlUploadDeclarations(),
      path: '$destinationDir/graphql-upload.d.ts',
      typescriptSource: true,
    ));
  }

  futures.add(saveSource(
    data: serverSerializer.serializeResolvers(),
    path: '$destinationDir/resolvers/build-resolvers.ts',
    typescriptSource: true,
  ));

  if (apolloConfig.generateEntryPoint) {
    futures.add(saveSource(
      data: serverSerializer.serializeEntryPoint(),
      path: '$destinationDir/index.ts',
      typescriptSource: true,
    ));
    final implDir = destinationDir.replaceFirst('/generated', '');
    final contextStubPath = '$implDir/impl/my-context.ts';
    if (!File(contextStubPath).existsSync()) {
      futures.add(saveSource(
        data: serverSerializer.serializeContextStub(destinationDir),
        path: contextStubPath,
        typescriptSource: true,
      ));
    }
  }

  final result = await Future.wait(futures);
  stdout.writeln('Generated ${futures.length} files in ${formatElapsedTime(started)}');
  final paths = result.map((f) => f.path).toSet();
  await cleanUpObsoleteFiles(paths);
  return paths;
}
