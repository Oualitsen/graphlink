import 'dart:io';

import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/io_utils.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/express_apollo_server_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/java_spring_server_serializer.dart';
import 'package:graphlink/src/serializers/kotlin_spring_server_serializer.dart';
import 'package:graphlink/src/serializers/spring_map_type_resolver_config.dart';
import 'package:graphlink/src/serializers/kotlin_map_type_resolver_config.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:graphlink/src/utils.dart';

/// Writes one file per [defs] entry via [writeToFile], reducing the
/// repeated for-each-and-write shape to a single call at each site. [data]
/// and [fileName] are typically serializer method tear-offs (e.g.
/// `serializer.serializeTypeDefinition`, `serializer.getFileNameFor`).
void _writeDefinitions<T>({
  required List<Future<File>> futures,
  required Iterable<T> defs,
  required String Function(T def) data,
  required String Function(T def) fileName,
  required String subdir,
  required String destinationDir,
  required String packageName,
  bool appendStar = false,
}) {
  for (final def in defs) {
    futures.add(writeToFile(
      data: data(def),
      fileName: fileName(def),
      subdir: subdir,
      imports: const [],
      destinationDir: destinationDir,
      packageName: packageName,
      appendStar: appendStar,
    ));
  }
}

Future<Set<String>> generateServerClasses(
    GLParser grammar, GeneratorConfig config, DateTime started) async {
  final serverLang = config.serverConfig!.language;
  if (serverLang is ExpressApolloServerConfig) {
    return _generateExpressApolloClasses(grammar, config, started);
  }
  if (serverLang is KotlinSpringServerConfig) {
    return _generateKotlinSpringClasses(grammar, config, serverLang, started);
  }
  final springConfig = serverLang as SpringServerConfig;
  final packageName = springConfig.basePackage;
  final destinationDir = config.outputDir;
  final serializer = JavaSerializer(
    grammar,
    inputsAsRecords: springConfig.inputAsRecord,
    typesAsRecords: springConfig.typeAsRecord,
    inputsCheckForNulls: true,
    typesCheckForNulls: true,
    immutableInputFields: springConfig.immutableInputFields,
    immutableTypeFields: springConfig.immutableTypeFields,
    jspecify: springConfig.jspecify,
    typeMapOverrides: config.typeMappings ?? {},
    importPrefix: springConfig.basePackage,
  );
  final springSerializer = JavaSpringServerSerializer(grammar,
      packageName: packageName,
      javaSerializer: serializer,
      generateSchema: springConfig.generateSchema,
      injectContext: springConfig.injectContext,
      reactive: springConfig.reactive,
      useSpringSecurity: springConfig.useSpringSecurity);
  final futures = <Future<File>>[];

  _writeDefinitions(
    futures: futures,
    defs: grammar.getSerializableTypes(),
    data: serializer.serializeTypeDefinition,
    fileName: serializer.getFileNameFor,
    subdir: 'types',
    destinationDir: destinationDir,
    packageName: packageName,
    appendStar: true,
  );
  _writeDefinitions(
    futures: futures,
    defs: grammar.getSerializableInterfaces(),
    data: serializer.serializeTypeDefinition,
    fileName: serializer.getFileNameFor,
    subdir: 'interfaces',
    destinationDir: destinationDir,
    packageName: packageName,
    appendStar: true,
  );
  _writeDefinitions(
    futures: futures,
    defs: grammar.getSerializableEnums(),
    data: serializer.serializeEnumDefinition,
    fileName: serializer.getFileNameFor,
    subdir: 'enums',
    destinationDir: destinationDir,
    packageName: packageName,
    appendStar: true,
  );
  _writeDefinitions(
    futures: futures,
    defs: grammar.getSerializableInputs(),
    data: serializer.serializeInputDefinition,
    fileName: serializer.getFileNameFor,
    subdir: 'inputs',
    destinationDir: destinationDir,
    packageName: packageName,
    appendStar: true,
  );
  _writeDefinitions(
    futures: futures,
    defs: grammar.services.values,
    data: springSerializer.serializeService,
    fileName: serializer.getFileNameFor,
    subdir: 'services',
    destinationDir: destinationDir,
    packageName: packageName,
    appendStar: true,
  );
  if (springConfig.generateControllers) {
    _writeDefinitions(
      futures: futures,
      defs: grammar.controllers.values,
      data: springSerializer.serializeController,
      fileName: serializer.getFileNameFor,
      subdir: 'controllers',
      destinationDir: destinationDir,
      packageName: packageName,
      appendStar: true,
    );
  }
  if (springConfig.generateRepositories) {
    _writeDefinitions(
      futures: futures,
      defs: grammar.repositories.entries,
      data: (e) => springSerializer.serializeRepository(e.value),
      fileName: (e) => '${e.key}.java',
      subdir: 'repositories',
      destinationDir: destinationDir,
      packageName: packageName,
      appendStar: true,
    );
  }

  final hasAbstractTypes =
      grammar.getSerializableInterfaces().isNotEmpty || grammar.unions.isNotEmpty;
  if (springConfig.generateControllers && hasAbstractTypes) {
    futures.add(writeToFile(
      data: springMapTypeResolverConfigSource,
      fileName: springMapTypeResolverConfigFileName,
      subdir: 'config',
      imports: const [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
  }

  final schema = springSerializer.serializeTypeDefs();
  if (schema.isNotEmpty) {
    futures.add(saveSource(
      data: schema,
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

Future<Set<String>> _generateKotlinSpringClasses(GLParser grammar, GeneratorConfig config,
    KotlinSpringServerConfig springConfig, DateTime started) async {
  final packageName = springConfig.basePackage;
  final destinationDir = config.outputDir;
  final springSerializer = KotlinSpringServerSerializer(grammar,
      packageName: packageName,
      inputsAsDataClass: springConfig.inputAsDataClass,
      typesAsDataClass: springConfig.typeAsDataClass,
      generateSchema: springConfig.generateSchema,
      injectContext: springConfig.injectContext,
      blockingServices: springConfig.blockingServices);
  final serializer = springSerializer.serializer;
  final futures = <Future<File>>[];

  if (springConfig.blockingServices && springConfig.generateControllers) {
    futures.add(writeToFile(
      data: springSerializer.serializeSecurityCoroutineContext(),
      fileName: 'SecurityCoroutineContext.kt',
      subdir: 'security',
      imports: [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
  }

  _writeDefinitions(
    futures: futures,
    defs: grammar.getSerializableTypes(),
    data: serializer.serializeTypeDefinition,
    fileName: serializer.getFileNameFor,
    subdir: 'types',
    destinationDir: destinationDir,
    packageName: packageName,
  );
  _writeDefinitions(
    futures: futures,
    defs: grammar.getSerializableInterfaces(),
    data: serializer.serializeTypeDefinition,
    fileName: serializer.getFileNameFor,
    subdir: 'interfaces',
    destinationDir: destinationDir,
    packageName: packageName,
  );
  _writeDefinitions(
    futures: futures,
    defs: grammar.getSerializableEnums(),
    data: serializer.serializeEnumDefinition,
    fileName: serializer.getFileNameFor,
    subdir: 'enums',
    destinationDir: destinationDir,
    packageName: packageName,
  );
  _writeDefinitions(
    futures: futures,
    defs: grammar.getSerializableInputs(),
    data: serializer.serializeInputDefinition,
    fileName: serializer.getFileNameFor,
    subdir: 'inputs',
    destinationDir: destinationDir,
    packageName: packageName,
  );
  _writeDefinitions(
    futures: futures,
    defs: grammar.services.values,
    data: springSerializer.serializeService,
    fileName: serializer.getFileNameFor,
    subdir: 'services',
    destinationDir: destinationDir,
    packageName: packageName,
  );
  if (springConfig.generateControllers) {
    _writeDefinitions(
      futures: futures,
      defs: grammar.controllers.values,
      data: springSerializer.serializeController,
      fileName: serializer.getFileNameFor,
      subdir: 'controllers',
      destinationDir: destinationDir,
      packageName: packageName,
    );
  }
  if (springConfig.generateRepositories) {
    _writeDefinitions(
      futures: futures,
      defs: grammar.repositories.entries,
      data: (e) => springSerializer.serializeRepository(e.value),
      fileName: (e) => '${e.key}.kt',
      subdir: 'repositories',
      destinationDir: destinationDir,
      packageName: packageName,
    );
  }

  final hasAbstractTypes =
      grammar.getSerializableInterfaces().isNotEmpty || grammar.unions.isNotEmpty;
  if (springConfig.generateControllers && hasAbstractTypes) {
    futures.add(writeToFile(
      data: kotlinMapTypeResolverConfigSource,
      fileName: kotlinMapTypeResolverConfigFileName,
      subdir: 'config',
      imports: const [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
  }

  final schema = springSerializer.serializeTypeDefs();
  if (schema.isNotEmpty) {
    futures.add(saveSource(
      data: schema,
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
  final tsSerializer = TypeScriptSerializer(grammar, importPrefix: '',
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
      data: tsSerializer.serializeEnumDefinition(def),
      path: '$destinationDir/enums/${tsSerializer.getFileNameFor(def)}',
      typescriptSource: true,
    ));
  });
  grammar.getSerializableInputs().forEach((def) {
    futures.add(saveSource(
      data: tsSerializer.serializeInputDefinition(def),
      path: '$destinationDir/inputs/${tsSerializer.getFileNameFor(def)}',
      typescriptSource: true,
    ));
  });
  grammar.getSerializableTypes().forEach((def) {
    futures.add(saveSource(
      data: tsSerializer.serializeTypeDefinition(def),
      path: '$destinationDir/types/${tsSerializer.getFileNameFor(def)}',
      typescriptSource: true,
    ));
  });
  grammar.getSerializableInterfaces().forEach((def) {
    futures.add(saveSource(
      data: tsSerializer.serializeTypeDefinition(def),
      path: '$destinationDir/interfaces/${tsSerializer.getFileNameFor(def)}',
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

  if (serverSerializer.hasUploads) {
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
    data: serverSerializer.serializeResolvers().first,
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
