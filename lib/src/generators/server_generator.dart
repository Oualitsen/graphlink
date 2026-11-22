import 'package:graphlink/src/parser_extensions/gl_grammar_source_extension.dart';
import 'dart:io';

import 'package:graphlink/src/generators/openapi_generator.dart';
import 'package:graphlink/src/serializers/jvm_server_domain_error.dart';
import 'package:graphlink/src/serializers/spring_openapi_controller_serializer.dart';

import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/io_utils.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_server_extension.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_intercept_extension.dart';
import 'package:graphlink/src/generators/python_client_generator.dart' show pythonBarrel, pythonExportLine;
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_client_constants.dart' show pythonJsonChecks, pythonModelBase;
import 'package:graphlink/src/serializers/python/python_ariadne_server_constants.dart';
import 'package:graphlink/src/serializers/python/fastapi_ariadne_server_serializer.dart';
import 'package:graphlink/src/serializers/python/django_ariadne_server_serializer.dart';
import 'package:graphlink/src/serializers/python/python_ariadne_server_serializer.dart';
import 'package:graphlink/src/serializers/python/python_rest_constants.dart';
import 'package:graphlink/src/serializers/python/python_openapi_serializer.dart';
import 'package:graphlink/src/serializers/typescript/nest_apollo_rest_serializer.dart' show nestOpenApiControllerFile;
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:graphlink/src/serializers/typescript/express_apollo_rest_constants.dart';
import 'package:graphlink/src/serializers/typescript/express_apollo_server_serializer.dart';
import 'package:graphlink/src/serializers/typescript/nest_apollo_server_constants.dart';
import 'package:graphlink/src/serializers/typescript/nest_apollo_server_serializer.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_maps_to_extension.dart';
import 'package:graphlink/src/serializers/java/java_spring_server_serializer.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_spring_server_serializer.dart';
import 'package:graphlink/src/serializers/java/spring_map_type_resolver_config.dart';
import 'package:graphlink/src/serializers/java/spring_source_support.dart';
import 'package:graphlink/src/serializers/java/spring_subscription_transport_config.dart';
import 'package:graphlink/src/serializers/java/spring_rest_support.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_spring_rest_support.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_map_type_resolver_config.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_source_support.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_subscription_transport_config.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
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

void _writeMapperClasses({
  required List<Future<File>> futures,
  required GLParser grammar,
  required GLSerializer serializer,
  required String destinationDir,
  required String packageName,
}) {
  _writeDefinitions(
    futures: futures,
    defs: grammar.mapperClassSources.where((def) => serializer.serializeMapperClass(def) != null),
    data: (def) => serializer.serializeMapperClass(def)!,
    fileName: serializer.getMapperFileName,
    subdir: 'mappers',
    destinationDir: destinationDir,
    packageName: packageName,
  );
}

void _writeSpringOpenApiController(List<Future<File>> futures, OpenApiOutput? openApi, SpringServerConfigBase springConfig,
    String destinationDir, String packageName, {required bool kotlin}) {
  if (openApi == null || !openApi.serve || !springConfig.generateControllers) return;
  final serializer = SpringOpenApiControllerSerializer(openApi, packageName);
  futures.add(writeToFile(
    data: kotlin ? serializer.serializeKotlin() : serializer.serializeJava(),
    fileName: '$springOpenApiControllerName.${kotlin ? 'kt' : 'java'}',
    subdir: 'controllers',
    imports: kotlin ? serializer.kotlinImports : serializer.javaImports,
    destinationDir: destinationDir,
    packageName: packageName,
  ));
}

Future<Set<String>> generateServerClasses(
    GLParser grammar, GeneratorConfig config, DateTime started) async {
  final written = await _generateServerTarget(grammar, config, started);
  return {...written, ...await writeOpenApiFile(buildOpenApiOutput(grammar, config))};
}

Future<Set<String>> _generateServerTarget(
    GLParser grammar, GeneratorConfig config, DateTime started) async {
  final serverLang = config.serverConfig!.language;
  if (serverLang is ExpressApolloServerConfig) {
    return _generateExpressApolloClasses(grammar, config, started);
  }
  if (serverLang is NestApolloServerConfig) {
    return _generateNestApolloClasses(grammar, config, serverLang, started);
  }
  if (serverLang is AriadneServerConfig) {
    return _generateAriadneClasses(grammar, config, serverLang, started);
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
  _writeMapperClasses(
    futures: futures,
    grammar: grammar,
    serializer: serializer,
    destinationDir: destinationDir,
    packageName: packageName,
  );
  _writeDefinitions(
    futures: futures,
    // GraphLinkInterceptor is written separately below (JVM-specific content).
    defs: grammar.getSerializableInterfaces().where((def) => def.token != glInterceptorInterfaceName),
    data: serializer.serializeTypeDefinition,
    fileName: serializer.getFileNameFor,
    subdir: 'interfaces',
    destinationDir: destinationDir,
    packageName: packageName,
    appendStar: true,
  );
  if (grammar.errors.isNotEmpty) {
    _writeDefinitions(
      futures: futures,
      defs: grammar.errors.values,
      data: serializer.serializeErrorDefinition,
      fileName: (e) => serializer.getFileNameFor(e.type),
      subdir: springDomainErrorDir,
      destinationDir: destinationDir,
      packageName: packageName,
      appendStar: true,
    );
    _writeJvmDomainErrorSupport(futures, destinationDir, packageName, grammar,
        kotlin: false,
        base: javaServerDomainError,
        resolver: javaServerDomainErrorResolver,
        advice: javaServerDomainErrorAdvice,
        generateControllers: springConfig.generateControllers);
  }
  final interceptorInterface = springSerializer.serializeInterceptorInterface();
  if (interceptorInterface != null) {
    futures.add(writeToFile(
      data: interceptorInterface,
      fileName: serializer.getFileNameFor(grammar.interfaces[glInterceptorInterfaceName]!),
      subdir: 'interfaces',
      imports: const [],
      destinationDir: destinationDir,
      packageName: packageName,
      appendStar: true,
    ));
  }
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
  _writeSpringOpenApiController(futures, buildOpenApiOutput(grammar, config), springConfig, destinationDir, packageName, kotlin: false);
  if (springConfig.generateControllers && grammar.restControllers.isNotEmpty) {
    _writeDefinitions(
      futures: futures,
      defs: grammar.restControllers.values,
      data: springSerializer.serializeRestController,
      fileName: serializer.getFileNameFor,
      subdir: 'controllers',
      destinationDir: destinationDir,
      packageName: packageName,
      appendStar: true,
    );
    if (grammar.restOperations.values.any((op) => op.bodyKind == RestBodyKind.raw)) {
      futures.add(writeToFile(
        data: springConfig.reactive ? springRestReactiveUploadSource : springRestUploadSource,
        fileName: springRestUploadFileName,
        subdir: 'rest',
        imports: const [],
        destinationDir: destinationDir,
        packageName: packageName,
      ));
    }
    if (grammar.restOperations.values.any((op) => op.responseKind == RestResponseKind.binary)) {
      futures.add(writeToFile(
        data: springRestDownloadSource,
        fileName: springRestDownloadFileName,
        subdir: 'rest',
        imports: const [],
        destinationDir: destinationDir,
        packageName: packageName,
      ));
    }
    if (grammar.restUsesStructuredParams) {
      futures.add(writeToFile(
        data: springRestParamsSource,
        fileName: springRestParamsFileName,
        subdir: 'rest',
        imports: const [],
        destinationDir: destinationDir,
        packageName: packageName,
      ));
    }
    futures.add(writeToFile(
      data: springRestSupportSource,
      fileName: springRestSupportFileName,
      subdir: 'rest',
      imports: const [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
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

  final hasAbstractTypes = !grammar.restOnly &&
      (grammar.getSerializableInterfaces().isNotEmpty || grammar.unions.isNotEmpty);
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

  if (springConfig.generateControllers && !grammar.restOnly && springSerializer.hasSubscriptions) {
    futures.add(writeToFile(
      data: springSubscriptionTransportConfigSource,
      fileName: springSubscriptionTransportConfigFileName,
      subdir: 'config',
      imports: const [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
  }

  if (springConfig.generateControllers && !grammar.restOnly && grammar.carriesSources) {
    futures.add(writeToFile(
      data: springSourceSupportSource,
      fileName: springSourceSupportFileName,
      subdir: 'controllers',
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
  _writeMapperClasses(
    futures: futures,
    grammar: grammar,
    serializer: serializer,
    destinationDir: destinationDir,
    packageName: packageName,
  );
  _writeDefinitions(
    futures: futures,
    // GraphLinkInterceptor is written separately below (JVM-specific content).
    defs: grammar.getSerializableInterfaces().where((def) => def.token != glInterceptorInterfaceName),
    data: serializer.serializeTypeDefinition,
    fileName: serializer.getFileNameFor,
    subdir: 'interfaces',
    destinationDir: destinationDir,
    packageName: packageName,
  );
  if (grammar.errors.isNotEmpty) {
    _writeDefinitions(
      futures: futures,
      defs: grammar.errors.values,
      data: serializer.serializeErrorDefinition,
      fileName: (e) => serializer.getFileNameFor(e.type),
      subdir: springDomainErrorDir,
      destinationDir: destinationDir,
      packageName: packageName,
      appendStar: true,
    );
    _writeJvmDomainErrorSupport(futures, destinationDir, packageName, grammar,
        kotlin: true,
        base: kotlinServerDomainError,
        resolver: kotlinServerDomainErrorResolver,
        advice: kotlinServerDomainErrorAdvice,
        generateControllers: springConfig.generateControllers);
  }
  final interceptorInterface = springSerializer.serializeInterceptorInterface();
  if (interceptorInterface != null) {
    futures.add(writeToFile(
      data: interceptorInterface,
      fileName: serializer.getFileNameFor(grammar.interfaces[glInterceptorInterfaceName]!),
      subdir: 'interfaces',
      imports: const [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
  }
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
  _writeSpringOpenApiController(futures, buildOpenApiOutput(grammar, config), springConfig, destinationDir, packageName, kotlin: true);
  if (springConfig.generateControllers && grammar.restControllers.isNotEmpty) {
    _writeDefinitions(
      futures: futures,
      defs: grammar.restControllers.values,
      data: springSerializer.serializeRestController,
      fileName: serializer.getFileNameFor,
      subdir: 'controllers',
      destinationDir: destinationDir,
      packageName: packageName,
    );
    if (grammar.restOperations.values.any((op) => op.bodyKind == RestBodyKind.raw)) {
      futures.add(writeToFile(
        data: kotlinRestUploadSource,
        fileName: kotlinRestUploadFileName,
        subdir: 'rest',
        imports: const [],
        destinationDir: destinationDir,
        packageName: packageName,
      ));
    }
    if (grammar.restOperations.values.any((op) => op.responseKind == RestResponseKind.binary)) {
      futures.add(writeToFile(
        data: kotlinRestDownloadSource,
        fileName: kotlinRestDownloadFileName,
        subdir: 'rest',
        imports: const [],
        destinationDir: destinationDir,
        packageName: packageName,
      ));
    }
    if (grammar.restUsesStructuredParams) {
      futures.add(writeToFile(
        data: kotlinRestParamsSource,
        fileName: kotlinRestParamsFileName,
        subdir: 'rest',
        imports: const [],
        destinationDir: destinationDir,
        packageName: packageName,
      ));
    }
    futures.add(writeToFile(
      data: kotlinRestSupportSource,
      fileName: kotlinRestSupportFileName,
      subdir: 'rest',
      imports: const [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
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

  final hasAbstractTypes = !grammar.restOnly &&
      (grammar.getSerializableInterfaces().isNotEmpty || grammar.unions.isNotEmpty);
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

  if (springConfig.generateControllers && !grammar.restOnly && grammar.carriesSources) {
    futures.add(writeToFile(
      data: kotlinSourceSupportSource,
      fileName: kotlinSourceSupportFileName,
      subdir: 'controllers',
      imports: const [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
  }

  if (springConfig.generateControllers && !grammar.restOnly && springSerializer.hasSubscriptions) {
    futures.add(writeToFile(
      data: kotlinSubscriptionTransportConfigSource,
      fileName: kotlinSubscriptionTransportConfigFileName,
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

  if (!grammar.restOnly) {
    futures.add(saveSource(
      data: serverSerializer.serializeTypeDefs(),
      path: '$destinationDir/typeDefs.ts',
      typescriptSource: true,
    ));
  }

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
  for (final def in grammar.mapperClassSources) {
    final content = tsSerializer.serializeMapperClass(def);
    if (content == null) continue;
    futures.add(saveSource(
      data: content,
      path: '$destinationDir/mappers/${tsSerializer.getMapperFileName(def)}',
      typescriptSource: true,
    ));
  }
  grammar.getSerializableInterfaces().forEach((def) {
    // GraphLinkInterceptor is written separately below (target-specific content).
    if (def.token == glInterceptorInterfaceName) return;
    futures.add(saveSource(
      data: tsSerializer.serializeTypeDefinition(def),
      path: '$destinationDir/interfaces/${tsSerializer.getFileNameFor(def)}',
      typescriptSource: true,
    ));
  });
  grammar.errors.forEach((_, def) {
    futures.add(saveSource(
      data: tsSerializer.serializeErrorDefinition(def),
      path: '$destinationDir/errors/${tsSerializer.getFileNameFor(def.type)}',
      typescriptSource: true,
    ));
  });
  if (serverSerializer.hasDomainErrors) {
    futures.add(saveSource(
      data: serverSerializer.serializeDomainErrorSupport(),
      path: '$destinationDir/errors/graph-link-domain-error.ts',
      typescriptSource: true,
    ));
  }
  final interceptorInterface = serverSerializer.serializeInterceptorInterface();
  if (interceptorInterface != null) {
    futures.add(saveSource(
      data: interceptorInterface,
      path: '$destinationDir/interfaces/${tsSerializer.getFileNameFor(grammar.interfaces[glInterceptorInterfaceName]!)}',
      typescriptSource: true,
    ));
  }

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

  if (grammar.carriesSources) {
    futures.add(saveSource(
      data: serverSerializer.serializeSourceSupport(),
      path: '$destinationDir/source.ts',
      typescriptSource: true,
    ));
  }

  futures.add(saveSource(
    data: serverSerializer.serializeContext(),
    path: '$destinationDir/context.ts',
    typescriptSource: true,
  ));

  if (serverSerializer.hasUploads || serverSerializer.hasRestUploads) {
    futures.add(saveSource(
      data: serverSerializer.serializeFileUploadType(),
      path: '$destinationDir/file-upload.ts',
      typescriptSource: true,
    ));
  }
  if (serverSerializer.hasUploads) {
    futures.add(saveSource(
      data: serverSerializer.serializeGraphqlUploadDeclarations(),
      path: '$destinationDir/graphql-upload.d.ts',
      typescriptSource: true,
    ));
  }

  if (!grammar.restOnly) {
    futures.add(saveSource(
      data: serverSerializer.serializeResolvers().first,
      path: '$destinationDir/resolvers/build-resolvers.ts',
      typescriptSource: true,
    ));
  }

  if (serverSerializer.hasRest) {
    futures.add(saveSource(
      data: serverSerializer.serializeRestSupport(),
      path: '$destinationDir/rest/$expressRestSupportFileName',
      typescriptSource: true,
    ));
    if (serverSerializer.hasRestUploads) {
      futures.add(saveSource(
        data: serverSerializer.serializeRestUploads(),
        path: '$destinationDir/rest/$expressRestUploadsFileName',
        typescriptSource: true,
      ));
    }
    if (serverSerializer.hasRestDownloads) {
      futures.add(saveSource(
        data: serverSerializer.serializeRestDownloads(),
        path: '$destinationDir/rest/$expressRestDownloadFileName',
        typescriptSource: true,
      ));
    }
    futures.add(saveSource(
      data: serverSerializer.serializeRestRouter(openApi: buildOpenApiOutput(grammar, config)),
      path: '$destinationDir/rest/build-rest-router.ts',
      typescriptSource: true,
    ));
  }

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

Future<Set<String>> _generateNestApolloClasses(
    GLParser grammar, GeneratorConfig config, NestApolloServerConfig nestConfig, DateTime started) async {
  final destinationDir = config.outputDir;
  final tsSerializer = TypeScriptSerializer(grammar, importPrefix: '',
      typeMapOverrides: config.typeMappings ?? {});
  final openApi = buildOpenApiOutput(grammar, config);
  final serializer = NestApolloServerSerializer(grammar, tsSerializer, nestConfig, openApi: openApi);
  final futures = <Future<File>>[];

  void add(String path, String data) {
    futures.add(saveSource(data: data, path: '$destinationDir/$path', typescriptSource: true));
  }

  if (!grammar.restOnly) add('typeDefs.ts', serializer.serializeTypeDefs());

  grammar.getSerializableEnums().forEach((def) {
    add('enums/${tsSerializer.getFileNameFor(def)}', tsSerializer.serializeEnumDefinition(def));
  });
  grammar.getSerializableInputs().forEach((def) {
    add('inputs/${tsSerializer.getFileNameFor(def)}', tsSerializer.serializeInputDefinition(def));
  });
  grammar.getSerializableTypes().forEach((def) {
    add('types/${tsSerializer.getFileNameFor(def)}', tsSerializer.serializeTypeDefinition(def));
  });
  for (final def in grammar.mapperClassSources) {
    final content = tsSerializer.serializeMapperClass(def);
    if (content != null) add('mappers/${tsSerializer.getMapperFileName(def)}', content);
  }
  grammar.getSerializableInterfaces().forEach((def) {
    if (def.token == glInterceptorInterfaceName) return;
    add('interfaces/${tsSerializer.getFileNameFor(def)}', tsSerializer.serializeTypeDefinition(def));
  });
  grammar.errors.forEach((_, def) {
    add('errors/${tsSerializer.getFileNameFor(def.type)}', tsSerializer.serializeErrorDefinition(def));
  });
  if (serializer.hasDomainErrors) add('errors/graph-link-domain-error.ts', serializer.serializeDomainErrorSupport());
  final interceptorInterface = serializer.serializeInterceptorInterface();
  if (interceptorInterface != null) {
    add('interfaces/${tsSerializer.getFileNameFor(grammar.interfaces[glInterceptorInterfaceName]!)}', interceptorInterface);
  }

  grammar.services.forEach((_, service) {
    add('services/${service.token.toKebabCase()}.ts', serializer.serializeService(service));
    final guard = serializer.serializeGuard(service);
    if (guard != null) {
      add('guards/${'${service.token.replaceFirst('Service', '')}Guard'.toKebabCase()}.ts', guard);
    }
    final loader = serializer.serializeLoader(service);
    if (loader != null) {
      add('loaders/${service.token.replaceFirst('Service', '').toKebabCase()}-loaders.ts', loader);
    }
  });

  if (grammar.carriesSources) add('source.ts', serializer.serializeSourceSupport());
  add('context.ts', serializer.serializeContext());

  if (serializer.hasUploads || serializer.rest.hasUploads) add('file-upload.ts', serializer.serializeFileUploadType());
  if (serializer.hasUploads) add('graphql-upload.d.ts', serializer.serializeGraphqlUploadDeclarations());

  serializer.serializeResolverFiles().forEach((file, content) => add('resolvers/$file', content));

  if (serializer.hasRest) {
    add('rest/$nestRestSupportFileName', nestRestSupport);
    if (serializer.rest.hasUploads) add('rest/$expressRestUploadsFileName', serializer.rest.serializeUploads());
    if (serializer.rest.hasDownloads) add('rest/$expressRestDownloadFileName', serializer.rest.serializeDownloads());
    add('rest/shapes.ts', serializer.rest.serializeShapes());
    for (final service in serializer.rest.restServices) {
      add('rest/${serializer.rest.controllerFileName(service)}.ts', serializer.rest.serializeController(service));
    }
    add('rest/rest-fallback.controller.ts', serializer.rest.serializeFallbackController());
    if (serializer.rest.servesOpenApi) add('rest/$nestOpenApiControllerFile.ts', serializer.rest.serializeOpenApiController());
  }

  add(nestOptionsFileName, serializer.serializeOptions());
  add(nestExceptionFilterFileName, serializer.serializeExceptionFilter());
  if (!grammar.restOnly) add(nestRequestGuardsFileName, nestRequestGuards);

  if (nestConfig.generateEntryPoint) {
    add(nestModuleFileName, serializer.serializeModule());
    add('index.ts', serializer.serializeEntryPoint());
    final implDir = destinationDir.replaceFirst('/generated', '');
    final contextStubPath = '$implDir/impl/my-context.ts';
    if (!File(contextStubPath).existsSync()) {
      futures.add(saveSource(
        data: serializer.serializeContextStub(destinationDir),
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

Future<Set<String>> _generateAriadneClasses(
    GLParser grammar, GeneratorConfig config, AriadneServerConfig ariadneConfig, DateTime started) async {
  final destinationDir = config.outputDir;
  final py = PythonSerializer(
    grammar,
    runtimeDir: ariadneRuntimeDir,
    typeMapOverrides: config.typeMappings ?? {},
  );
  final isDjango = ariadneConfig is DjangoAriadneServerConfig;
  final openApi = buildOpenApiOutput(grammar, config);
  final PythonAriadneServerSerializer serverSerializer = isDjango
      ? DjangoAriadneServerSerializer(grammar, py, ariadneConfig, openApi: openApi)
      : FastapiAriadneServerSerializer(grammar, py, ariadneConfig, openApi: openApi);
  final files = <String, String>{};
  final exports = <String>[];
  final models = <String>[];

  void add(String path, String content) {
    if (content.trim().isEmpty) return;
    files[path] = content;
  }

  String wrap(String body) => py.serializeGlClass(GLClassModel(body: body.trim()));

  add('$ariadneRuntimeDir/graph_link_model.py', wrap(pythonModelBase));
  add('$ariadneRuntimeDir/graph_link_json.py', wrap(pythonJsonChecks));
  files['$ariadneRuntimeDir/__init__.py'] = '';

  grammar.getSerializableEnums().forEach((def) {
    final content = py.serializeEnumDefinition(def);
    add('enums/${py.getFileNameFor(def)}', content);
    if (content.trim().isNotEmpty) exports.add(pythonExportLine('enums', py, def.codeName, def));
  });
  grammar.getSerializableInputs().forEach((def) {
    final content = py.serializeInputDefinition(def);
    add('inputs/${py.getFileNameFor(def)}', content);
    if (content.trim().isNotEmpty) {
      exports.add(pythonExportLine('inputs', py, def.codeName, def));
      models.add(def.codeName);
    }
  });
  grammar.getSerializableTypes().forEach((def) {
    final content = py.serializeTypeDefinition(def);
    add('types/${py.getFileNameFor(def)}', content);
    if (content.trim().isNotEmpty) {
      exports.add(pythonExportLine('types', py, def.codeName, def));
      models.add(def.codeName);
    }
  });
  for (final def in grammar.mapperClassSources) {
    final content = py.serializeMapperClass(def);
    if (content == null) continue;
    add('mappers/${py.getMapperFileName(def)}', content);
    exports.add('from .mappers.${py.getMapperFileName(def).replaceAll('.py', '')} import ${py.mapping.mapperName(def)}');
  }
  grammar.getSerializableInterfaces().forEach((def) {
    if (def.token == glInterceptorInterfaceName) return;
    final content = py.serializeTypeDefinition(def);
    add('interfaces/${py.getFileNameFor(def)}', content);
    if (content.trim().isNotEmpty) {
      exports.add(pythonExportLine('interfaces', py, def.codeName, def));
      models.add(def.codeName);
    }
  });
  final interceptorInterface = serverSerializer.serializeInterceptorInterface();
  if (interceptorInterface != null) {
    add('interfaces/${serverSerializer.interceptorFileName}.py', wrap(interceptorInterface));
  }

  grammar.errors.forEach((_, def) {
    add('errors/${py.getFileNameFor(def.type)}', py.serializeErrorDefinition(def));
    exports.add(pythonExportLine('errors', py, def.type.codeName, def.type));
  });
  if (grammar.errors.isNotEmpty) {
    add('$ariadneRuntimeDir/graph_link_domain_error.py', wrap(serverSerializer.serializeDomainErrorRuntime()));
  }

  grammar.services.forEach((_, service) {
    add('services/${serverSerializer.serviceFileName(service)}.py', wrap(serverSerializer.serializeService(service)));
    final guard = serverSerializer.serializeGuard(service);
    if (guard != null) add('guards/${serverSerializer.guardFileName(service)}.py', wrap(guard));
    final loader = serverSerializer.serializeLoader(service);
    if (loader != null) add('loaders/${serverSerializer.loaderFileName(service)}.py', wrap(loader));
  });

  if (grammar.carriesSources) add('source.py', wrap(serverSerializer.serializeSourceSupport()));
  add('context.py', wrap(serverSerializer.serializeContext()));
  if (grammar.services.values.any((s) => s.mappings.any((m) => m.isBatch))) {
    add('$ariadneRuntimeDir/graph_link_loader.py', wrap(serverSerializer.serializeLoaderRuntime()));
  }
  if (serverSerializer.hasUploads || serverSerializer.hasRestUploads) {
    add('file_upload.py', wrap(serverSerializer.serializeFileUpload()));
  }

  if (!grammar.restOnly) {
    add('type_defs.py', serverSerializer.serializeTypeDefs());
    add('$ariadneRuntimeDir/graph_link_guards.py', wrap(serverSerializer.serializeGuards()));
    add('$ariadneRuntimeDir/graph_link_ws.py', wrap(serverSerializer.serializeWsHandler()));
    if (isDjango) {
      add('$ariadneRuntimeDir/graph_link_view.py', wrap(ariadneDjangoGraphQLView));
      add('$ariadneRuntimeDir/graph_link_websocket.py', wrap(ariadneDjangoWebSocket));
    }
    add('resolvers.py', serverSerializer.serializeResolvers().first);
  }

  if (serverSerializer.hasRest) {
    add('rest/core.py', wrap(serverSerializer.rest.serializeCore()));
    add('rest/support.py', wrap(serverSerializer.rest.serializeSupport()));
    if (serverSerializer.hasRestUploads) add('rest/uploads.py', wrap(serverSerializer.rest.serializeUploads()));
    if (serverSerializer.hasRestDownloads) add('rest/download.py', wrap(serverSerializer.rest.serializeDownloads()));
    add('rest/routes.py', serverSerializer.rest.serializeRestRoutes());
    if (isDjango) {
      add('rest/urls.py', wrap(pythonRestDjangoUrls));
    } else {
      add('rest/router.py', wrap(pythonRestFastapiRouter));
    }
    if (serverSerializer.servesOpenApi) {
      final openApiSerializer = PythonOpenApiSerializer(openApi!, py);
      add(pythonOpenApiFile, wrap(isDjango ? openApiSerializer.serializeDjango() : openApiSerializer.serializeFastapi()));
    }
    files['rest/__init__.py'] = '';
  }

  if (ariadneConfig.generateEntryPoint) add('app.py', serverSerializer.serializeEntryPoint());

  for (final subdir in const ['enums', 'inputs', 'types', 'interfaces', 'errors', 'mappers', 'services', 'guards', 'loaders']) {
    if (files.keys.any((k) => k.startsWith('$subdir/'))) files['$subdir/__init__.py'] = '';
  }
  files['__init__.py'] = pythonBarrel(exports, models);

  final written = <Future<File>>[];
  files.forEach((path, content) {
    written.add(saveSource(data: content, path: '$destinationDir/$path', hashCommentSource: true));
  });
  final result = await Future.wait(written);
  stdout.writeln('Generated ${written.length} files in ${formatElapsedTime(started)}');
  final paths = result.map((f) => f.path).toSet();
  await cleanUpObsoleteFiles(paths);
  return paths;
}

void _writeJvmDomainErrorSupport(
  List<Future<File>> futures,
  String destinationDir,
  String packageName,
  GLParser grammar, {
  required bool kotlin,
  required String base,
  required String resolver,
  required String advice,
  required bool generateControllers,
}) {
  final extension = kotlin ? 'kt' : 'java';
  void write(String name, String source, String subdir) {
    futures.add(writeToFile(
      data: source,
      fileName: '$name.$extension',
      subdir: subdir,
      imports: const [],
      destinationDir: destinationDir,
      packageName: packageName,
    ));
  }

  write('GraphLinkDomainError', base, springDomainErrorDir);
  if (!generateControllers) return;
  final errorsImport = 'import $packageName.$springDomainErrorDir.GraphLinkDomainError${kotlin ? '' : ';'}\n\n';
  if (!grammar.restOnly) write('GraphLinkDomainErrorResolver', '$errorsImport$resolver', 'controllers');
  if (grammar.restOperations.isNotEmpty) write('GraphLinkDomainErrorAdvice', '$errorsImport$advice', 'controllers');
}
