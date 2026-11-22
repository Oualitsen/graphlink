import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/generators/openapi_generator.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_schema_mapping.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_intercept_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_server_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_source_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_validation_extension.dart';
import 'package:graphlink/src/serializers/typescript/nest_apollo_rest_serializer.dart';
import 'package:graphlink/src/serializers/typescript/nest_apollo_server_constants.dart';
import 'package:graphlink/src/serializers/typescript/typescript_apollo_server_base.dart';
import 'package:graphlink/src/typescript_code_gen_utils.dart';

const nestOptionsFileName = 'graphlink.options.ts';
const nestModuleFileName = 'graphlink.module.ts';

/// A NestJS server, schema first: the service contracts are abstract classes (the DI tokens), root fields are
/// `@Resolver` classes, `@glMapsTo` fields are `@ResolveField` classes, `@glRest*` operations are `@Controller`s and the
/// whole is a dynamic `GraphLinkModule` the application imports.
class NestApolloServerSerializer extends TypeScriptApolloServerSerializerBase {
  final _cg = TypeScriptCodeGenUtils();

  final OpenApiOutput? openApi;

  NestApolloServerSerializer(super.grammar, super.tsSerializer, NestApolloServerConfig super.apolloConfig, {this.openApi});

  late final NestApolloRestSerializer rest = NestApolloRestSerializer(grammar, tsSerializer, apolloConfig, openApi: openApi);

  bool get hasRest => rest.hasRest;

  bool get restOnly => grammar.restOnly;

  @override
  String declareContract(String name, List<String> signatures) =>
      _cg.createClass(className: name, isAbstract: true, statements: [for (final s in signatures) 'abstract $s']);

  @override
  String declareInterceptor(String serializedInterface) => serializedInterface
      .replaceFirstMapped(RegExp(r'export interface (\w+) \{'), (m) => 'export abstract class ${m[1]} {')
      .replaceAllMapped(RegExp(r'^(\s+)(runBefore\()', multiLine: true), (m) => '${m[1]}abstract ${m[2]}');

  // ── resolvers ─────────────────────────────────────────────────────────────

  String rootResolverClassName(GLService service) => '${service.token}Resolver';

  String rootResolverFileName(GLService service) => '${service.token.toKebabCase()}.resolver';

  String fieldsResolverClassName(String typeName) => '${typeName}FieldsResolver';

  String fieldsResolverFileName(String typeName) => '${typeName.toKebabCase()}-fields.resolver';

  List<GLService> get _rootResolverServices => [
        for (final service in grammar.services.values)
          if (_rootEntries(service).isNotEmpty) service,
      ];

  Map<String, List<MappingEntry>> get _mappingsByType {
    final byType = <String, List<MappingEntry>>{};
    for (final service in grammar.services.values) {
      for (final mapping in service.mappings) {
        byType.putIfAbsent(mapping.type.token, () => []).add(MappingEntry(mapping: mapping, service: service));
      }
    }
    for (final typeName in mapToPassThroughFields().keys) {
      byType.putIfAbsent(typeName, () => []);
    }
    return byType;
  }

  List<String> get resolverClassNames => restOnly
      ? const []
      : [
          for (final service in _rootResolverServices) rootResolverClassName(service),
          for (final typeName in _mappingsByType.keys) fieldsResolverClassName(typeName),
        ];

  /// `{file name: content}` of every resolver class, relative to `resolvers/`.
  Map<String, String> serializeResolverFiles() {
    if (restOnly) return const {};
    return {
      for (final service in _rootResolverServices) '${rootResolverFileName(service)}.ts': _rootResolver(service),
      for (final entry in _mappingsByType.entries)
        '${fieldsResolverFileName(entry.key)}.ts': _fieldsResolver(entry.key, entry.value),
    };
  }

  @override
  List<String> serializeResolvers() => serializeResolverFiles().values.toList();

  List<RootEntry> _rootEntries(GLService service) {
    final entries = <RootEntry>[];
    for (final field in service.fields) {
      if (field.getDirectiveByName(glValidate)?.generated == true) continue;
      if (grammar.isRestField(field)) continue;
      final type = service.getTypeByFieldName(field.name.token);
      if (type == null) continue;
      final intercepted = grammar.isIntercepted(field, type);
      entries.add(RootEntry(
        service: service,
        field: field,
        queryType: type,
        fieldName: field.name.token,
        argNames: field.arguments.map((a) => a.token).toList(),
        argCodeNames: field.arguments.map((a) => a.codeName).toList(),
        argTypes: field.arguments.map((a) => a.type).toList(),
        returnType: field.type,
        needsInfo: apolloConfig.useResolveInfo && type != GLQueryType.subscription,
        contextInjected: injectsContext(field) || intercepted,
        intercepted: intercepted,
      ));
    }
    return entries;
  }

  String _rootResolver(GLService service) {
    final entries = _rootEntries(service);
    final types = <String>{};
    for (final e in entries) {
      for (final arg in e.field.arguments) {
        if (!isUploadScalar(arg.type)) collectType(arg.type, types);
      }
      collectType(e.returnType, types);
    }
    final decorators = <String>{
      for (final e in entries) _decoratorOf(e.queryType),
      for (final e in entries) ...[if (e.field.arguments.isNotEmpty) 'Args', if (e.contextInjected) 'Context', if (e.needsInfo) 'Info'],
    };
    final guarded = entries.any((e) => fieldHasValidation(e.field));
    final intercepted = entries.any((e) => e.intercepted);

    final dependencies = [
      _dependency(service.token),
      if (guarded) _dependency(guardName(service)),
      if (intercepted) _interceptorDependency(),
    ];
    final methods = [
      for (final e in entries)
        e.queryType == GLQueryType.subscription ? _subscriptionMethod(e) : _queryOrMutationMethod(e),
    ];

    final imports = [
      "import { Inject } from '@nestjs/common';",
      "import { ${([...decorators, 'Resolver'].toList()..sort()).join(', ')} } from '@nestjs/graphql';",
      if (entries.any((e) => e.needsInfo)) "import { GraphQLResolveInfo } from 'graphql';",
      if (entries.any((e) => e.contextInjected)) "import { GraphLinkContext } from '../context.js';",
      if (grammar.carriesSources) "import { attachSource, sourceOf } from '../source.js';",
      if (entries.any((e) => e.argTypes.any(isUploadScalar))) "import type { FileUpload } from '../file-upload.js';",
      ..._interceptorImports(intercepted),
      "import { ${service.token} } from '../services/${kebabJs(service.token)}';",
      if (guarded) "import { ${guardName(service)} } from '../guards/${kebabJs(guardName(service))}';",
      if (types.isNotEmpty) importLines(types),
    ];
    final body = '@Resolver()\n${_cg.createClass(
      className: rootResolverClassName(service),
      statements: [_constructor(dependencies), ...methods],
    )}';
    return '${GLClassModel(imports: imports, body: body).toFileContent()}\n';
  }

  String _decoratorOf(GLQueryType type) {
    if (type == GLQueryType.mutation) return 'Mutation';
    if (type == GLQueryType.subscription) return 'Subscription';
    return 'Query';
  }

  String _queryOrMutationMethod(RootEntry e) {
    final member = e.service.token.firstLow;
    final resolvedArgs = List<String>.from(e.argCodeNames);
    final uploadLines = <String>[];
    for (var i = 0; i < e.argTypes.length; i++) {
      if (!isUploadScalar(e.argTypes[i])) continue;
      final resolved = '_${e.argCodeNames[i]}';
      resolvedArgs[i] = resolved;
      uploadLines.add(_cg.constDecl(
          resolved, e.argTypes[i] is GLListType ? 'await Promise.all(${e.argCodeNames[i]})' : 'await ${e.argCodeNames[i]}'));
    }
    final callArgs = [
      ...resolvedArgs,
      if (injectsContext(e.field)) 'context',
      if (e.needsInfo) 'info',
    ].join(', ');
    final call = 'this.$member.${e.fieldName}($callArgs)';
    final toJson = tsSerializer.carryingSource(() => tsSerializer.toJsonExpr(e.returnType, '_r'));
    final needsWrap = e.returnType is GLListType ||
        grammar.isEnum(e.returnType.firstType.token) ||
        grammar.isProjectableType(e.returnType.firstType.token);
    final returned = needsWrap ? '$call.then((_r) => $toJson)' : call;
    final validate = fieldHasValidation(e.field)
        ? 'await this.${guardName(e.service).firstLow}.${validationMethodName(e.fieldName)}($callArgs);'
        : null;
    return '@${_decoratorOf(e.queryType)}(${e.fieldName.quote()})\n${_cg.createMethod(
      methodName: e.fieldName,
      arguments: _rootParams(e),
      async: true,
      statements: [
        if (e.intercepted) _runBefore(e),
        ...uploadLines,
        if (validate != null) validate,
        'return $returned;',
      ],
    )}';
  }

  String _subscriptionMethod(RootEntry e) {
    final member = e.service.token.firstLow;
    final callArgs = [...e.argCodeNames, if (injectsContext(e.field)) 'context'].join(', ');
    final call = 'this.$member.${e.fieldName}($callArgs)';
    final toJson = tsSerializer.carryingSource(() => tsSerializer.toJsonExpr(e.returnType, 'payload'));
    final decorator = '@Subscription(${e.fieldName.quote()}, { resolve: (payload: any) => $toJson })';
    final method = e.intercepted
        ? _cg.createMethod(
            methodName: e.fieldName,
            arguments: _rootParams(e),
            async: true,
            statements: [_runBefore(e), 'return $call;'],
          )
        : _cg.createMethod(methodName: e.fieldName, arguments: _rootParams(e), statements: ['return $call;']);
    return '$decorator\n$method';
  }

  List<String> _rootParams(RootEntry e) => [
        for (final arg in e.field.arguments) _argParam(arg),
        if (e.contextInjected) '@Context() context: GraphLinkContext',
        if (e.needsInfo) '@Info() info: GraphQLResolveInfo',
      ];

  String _argParam(GLArgumentDefinition arg) {
    final type = isUploadScalar(arg.type) ? _uploadParamType(arg.type) : tsSerializer.serializeType(arg.type);
    return '@Args(${arg.token.quote()}) ${arg.codeName}: $type';
  }

  String _uploadParamType(GLType type) {
    final upload = type is GLListType ? 'Promise<FileUpload>[]' : 'Promise<FileUpload>';
    return type.nullable ? '$upload | null' : upload;
  }

  String _runBefore(RootEntry e) {
    final callArgs = [
      ...interceptorTagCallArg(e.field, e.queryType),
      e.fieldName.quote(),
      '[${e.argCodeNames.join(', ')}]',
      'context',
      if (apolloConfig.useResolveInfo) (e.needsInfo ? 'info' : 'null'),
    ].join(', ');
    return 'await this.interceptor.runBefore($callArgs);';
  }

  // ── field resolvers (@glMapsTo) ───────────────────────────────────────────

  String _fieldsResolver(String typeName, List<MappingEntry> entries) {
    final passThrough = mapToPassThroughFields()[typeName] ?? const <String>[];
    final types = <String>{};
    for (final e in entries) {
      for (final arg in realMappingArgs(e.mapping)) {
        collectType(arg.type, types);
      }
      collectType(e.mapping.field.type, types);
    }
    final services = {for (final e in entries) e.service.token: e.service}.values.toList();
    final intercepted = entries.any((e) => grammar.isIntercepted(e.mapping.field));
    final batch = entries.any((e) => e.mapping.isBatch);
    final needsContext = entries.any((e) => _mappingNeedsContext(e.mapping));
    final needsInfo = apolloConfig.useResolveInfo && entries.any((e) => _isPlainMapping(e.mapping));
    final hasArgs = entries.any((e) => realMappingArgs(e.mapping).isNotEmpty);
    final forbids = entries.any((e) => e.mapping.forbid);

    final methods = [
      for (final e in entries) _mappingMethod(e),
      for (final name in passThrough) _cg.createMethod(
        methodName: name,
        arguments: ['@Parent() parent: any'],
        statements: ['return parent;'],
      ).prefixed('@ResolveField(${name.quote()})\n'),
    ];
    final dependencies = [
      for (final service in services) _dependency(service.token),
      if (intercepted) _interceptorDependency(),
    ];
    final names = <String>{'Parent', 'ResolveField', 'Resolver', if (hasArgs) 'Args', if (needsContext) 'Context', if (needsInfo) 'Info'};
    final imports = [
      "import { Inject } from '@nestjs/common';",
      "import { ${(names.toList()..sort()).join(', ')} } from '@nestjs/graphql';",
      if (forbids || needsInfo) "import { ${[if (forbids) 'GraphQLError', if (needsInfo) 'GraphQLResolveInfo'].join(', ')} } from 'graphql';",
      if (needsContext)
        "import { GraphLinkContext${batch ? ', GraphLinkLoaders' : ''} } from '../context.js';",
      if (grammar.carriesSources) "import { attachSource, sourceOf } from '../source.js';",
      ..._interceptorImports(intercepted),
      for (final service in services) "import { ${service.token} } from '../services/${kebabJs(service.token)}';",
      if (types.isNotEmpty) importLines(types),
    ];
    final body = '@Resolver(${typeName.quote()})\n${_cg.createClass(
      className: fieldsResolverClassName(typeName),
      statements: [_constructor(dependencies), ...methods],
    )}';
    return '${GLClassModel(imports: imports, body: body).toFileContent()}\n';
  }

  bool _isPlainMapping(GLSchemaMapping m) => !m.forbid && !m.identity && !m.forwarded && !m.isBatch;

  bool _mappingNeedsContext(GLSchemaMapping m) {
    if (m.forbid) return false;
    return m.isBatch || injectsContext(m.field) || grammar.isIntercepted(m.field);
  }

  String _mappingMethod(MappingEntry entry) {
    final m = entry.mapping;
    final name = m.field.name.token;
    final decorator = '@ResolveField(${name.quote()})\n';
    if (m.forbid) {
      return _cg.createMethod(
        methodName: name,
        returnType: 'never',
        statements: ["throw new GraphQLError('Access denied', { extensions: { code: 'FORBIDDEN' } });"],
      ).prefixed(decorator);
    }

    final intercepted = grammar.isIntercepted(m.field);
    final realArgs = realMappingArgs(m);
    final argParams = [for (final arg in realArgs) _argParam(arg)];
    final runBefore = intercepted ? _mappingRunBefore(m, realArgs) : null;
    final toJson = tsSerializer.carryingSource(() => tsSerializer.toJsonExpr(m.field.type, '_r'));

    if (m.identity || m.forwarded) {
      return _cg.createMethod(
        methodName: name,
        arguments: ['@Parent() parent: any', ...argParams, if (intercepted) '@Context() context: GraphLinkContext'],
        async: intercepted,
        statements: [if (runBefore != null) runBefore, 'return parent.$name;'],
      ).prefixed(decorator);
    }

    if (m.isBatch) {
      final loader = realArgs.isEmpty
          ? 'context.loaders.${m.key}'
          : 'context.loaders.${m.key}(${realArgs.map((a) => a.codeName).join(', ')})';
      return _cg.createMethod(
        methodName: name,
        arguments: [
          '@Parent() parent: any',
          ...argParams,
          '@Context() context: GraphLinkContext & { loaders: GraphLinkLoaders }',
        ],
        async: true,
        statements: [
          if (runBefore != null) runBefore,
          _cg.constDecl('_r', 'await $loader.load(parent)'),
          'return $toJson;',
        ],
      ).prefixed(decorator);
    }

    final needsInfo = apolloConfig.useResolveInfo;
    final passesContext = injectsContext(m.field);
    final callArgs = [
      for (final a in m.field.arguments)
        a.skipOnGraphqlSerialization ? (carriesSource(m.type.token) ? 'sourceOf(parent)' : 'parent') : a.codeName,
      if (passesContext) 'context',
      if (needsInfo) 'info',
    ].join(', ');
    return _cg.createMethod(
      methodName: name,
      arguments: [
        '@Parent() parent: any',
        ...argParams,
        if (passesContext || intercepted) '@Context() context: GraphLinkContext',
        if (needsInfo) '@Info() info: GraphQLResolveInfo',
      ],
      async: true,
      statements: [
        if (runBefore != null) runBefore,
        _cg.constDecl('_r', 'await this.${entry.service.token.firstLow}.${m.key}($callArgs)'),
        'return $toJson;',
      ],
    ).prefixed(decorator);
  }

  String _mappingRunBefore(GLSchemaMapping m, List<GLArgumentDefinition> realArgs) {
    final callArgs = [
      ...interceptorTagCallArg(m.field),
      '"${m.type.token}.${m.field.name}"',
      '[${realArgs.map((a) => a.codeName).join(', ')}]',
      'context',
      if (apolloConfig.useResolveInfo) 'null',
    ].join(', ');
    return 'await this.interceptor.runBefore($callArgs);';
  }

  // ── shared pieces ─────────────────────────────────────────────────────────

  String _dependency(String token) => '@Inject($token) private readonly ${token.firstLow}: $token';

  String _interceptorDependency() {
    final name = grammar.interfaces[glInterceptorInterfaceName]!.codeName;
    return '@Inject($name) private readonly interceptor: $name';
  }

  String _constructor(List<String> dependencies) => 'constructor(\n${dependencies.join(',\n').ident()}\n) {}';

  List<String> _interceptorImports(bool intercepted) {
    if (!intercepted) return const [];
    final interceptor = grammar.interfaces[glInterceptorInterfaceName]!;
    final tagEnum = grammar.enums[glInterceptorTagEnumName];
    return [
      "import { ${interceptor.codeName} } from '../interfaces/${tsSerializer.getFileNameFor(interceptor).replaceAll('.ts', '.js')}';",
      if (tagEnum != null)
        "import { ${tagEnum.codeName} } from '../enums/${tsSerializer.getFileNameFor(tagEnum).replaceAll('.ts', '.js')}';",
    ];
  }

  // ── graphlink.options.ts ──────────────────────────────────────────────────

  String serializeOptions() {
    const imports = [
      "import type { DynamicModule, ForwardReference, Type } from '@nestjs/common';",
      "import type { Request, Response } from 'express';",
      "import type { GraphLinkContext } from './context.js';",
    ];
    const body = r'''export const GRAPHLINK_OPTIONS = Symbol('GRAPHLINK_OPTIONS');

export interface GraphLinkModuleOptions {
   /** Modules providing (and exporting) every service, guard and the interceptor declared in `services/`, `guards/` and `interfaces/`. */
   imports?: Array<Type<unknown> | DynamicModule | Promise<DynamicModule> | ForwardReference>;
   maxQueryDepth?: number;
   contextFactory?: (req: Request, res: Response) => GraphLinkContext | Promise<GraphLinkContext>;
}

export async function restContext(options: GraphLinkModuleOptions, req: Request, res: Response): Promise<GraphLinkContext> {
   return options.contextFactory ? await options.contextFactory(req, res) : ({} as GraphLinkContext);
}
''';
    return '${const GLClassModel(imports: imports, body: body).toFileContent()}\n';
  }

  // ── exception filter ──────────────────────────────────────────────────────

  String serializeExceptionFilter() {
    final graphql = !restOnly;
    final restFormat = hasRest;
    final imports = [
      "import { ArgumentsHost, Catch, ExceptionFilter } from '@nestjs/common';",
      "import type { Request, Response } from 'express';",
      if (restFormat) "import { RestError, sendError } from './rest/support.js';",
      if (restFormat && hasDomainErrors) "import { GraphLinkDomainError, domainErrorResponse } from './errors/graph-link-domain-error.js';",
    ];
    final domainErrorResponse = restFormat && hasDomainErrors
        ? _cg.ifStatement(condition: 'error instanceof GraphLinkDomainError', ifBlockStatements: [
            'const failure = domainErrorResponse(error);',
            'res.status(failure.status).json(failure.body);',
            'return undefined;',
          ])
        : null;
    final handling = [
      if (graphql && restFormat)
        'if (req.path === graphqlPath) ${_cg.block([
          'const { status, body } = graphqlErrorBody(error);',
          'res.status(status).json(body);',
          'return;',
        ])}',
      if (graphql && !restFormat) ...[
        'const { status, body } = graphqlErrorBody(error);',
        'res.status(status).json(body);',
      ] else
        'sendError(res, restErrorStatus(error));',
    ];
    final catchMethod = _cg.createMethod(
      methodName: 'catch',
      arguments: ['error: unknown', 'host: ArgumentsHost'],
      returnType: 'unknown',
      statements: [
        if (graphql) "if (host.getType<string>() === 'graphql') return error;",
        _cg.constDecl('http', 'host.switchToHttp()'),
        _cg.constDecl('req', 'http.getRequest<Request>()'),
        _cg.constDecl('res', 'http.getResponse<Response>()'),
        _cg.ifStatement(condition: 'res.headersSent', ifBlockStatements: ['res.end();', 'return undefined;']),
        if (domainErrorResponse != null) domainErrorResponse,
        ...handling,
        'return undefined;',
      ],
    );
    final body = [
      if (graphql && restFormat) 'const graphqlPath = ${apolloConfig.graphqlPath.quote()};\n',
      if (graphql) nestGraphqlErrorBody,
      if (restFormat) nestRestErrorStatus,
      '@Catch()\n${_cg.createClass(className: 'GraphLinkExceptionFilter', implementsNames: ['ExceptionFilter'], statements: [catchMethod])}',
    ].join('\n');
    return '${GLClassModel(imports: imports, body: body).toFileContent()}\n';
  }

  // ── graphlink.module.ts ───────────────────────────────────────────────────

  String serializeModule() {
    final services = grammar.services.values.toList();
    final loaderServices = [
      for (final service in services)
        if (service.mappings.any((m) => m.isBatch)) service,
    ];
    final batch = batchMappings();
    final graphql = !restOnly;
    final resolverNames = resolverClassNames;
    final controllerNames = rest.controllerClassNames;

    final imports = [
      "import { DynamicModule, Inject, ${graphql ? 'MiddlewareConsumer, ' : ''}Module, NestModule } from '@nestjs/common';",
      "import { APP_FILTER } from '@nestjs/core';",
      if (graphql) ...[
        "import { ApolloDriver, ApolloDriverConfig } from '@nestjs/apollo';",
        "import { GraphQLModule } from '@nestjs/graphql';",
        "import type { Request, Response } from 'express';",
        if (hasUploads) ...[
          "import GraphQLUpload from 'graphql-upload/GraphQLUpload.mjs';",
          "import graphqlUploadExpress from 'graphql-upload/graphqlUploadExpress.mjs';",
        ],
        "import { GraphLinkContext } from './context.js';",
        "import { typeDefs } from './typeDefs.js';",
        if (hasDomainErrors) "import { formatDomainError } from './errors/graph-link-domain-error.js';",
        "import { defaultMaxQueryDepth, queryDepthGuard${hasSubscriptions ? ', subscribeErrors' : ''} } from './graphlink-request-guards.js';",
      ],
      "import { GRAPHLINK_OPTIONS, GraphLinkModuleOptions } from './graphlink.options.js';",
      "import { GraphLinkExceptionFilter } from './graphlink-exception.filter.js';",
      for (final service in _rootResolverServices)
        "import { ${rootResolverClassName(service)} } from './resolvers/${rootResolverFileName(service)}.js';",
      if (graphql)
        for (final typeName in _mappingsByType.keys)
          "import { ${fieldsResolverClassName(typeName)} } from './resolvers/${fieldsResolverFileName(typeName)}.js';",
      for (final service in rest.restServices)
        "import { ${rest.controllerClassName(service)} } from './rest/${rest.controllerFileName(service)}.js';",
      if (rest.servesOpenApi) "import { $nestOpenApiControllerClass } from './rest/$nestOpenApiControllerFile.js';",
      if (hasRest) "import { $nestRestFallbackControllerClass } from './rest/rest-fallback.controller.js';",
      for (final service in loaderServices) ...[
        "import { ${service.token} } from './services/${kebabJs(service.token)}';",
        for (final m in service.mappings.where((m) => m.isBatch))
          "import { create${m.key.firstUp}Loader } from './loaders/${loaderFileJs(service)}';",
      ],
    ];

    final factory = graphql ? _graphqlFactory(loaderServices, batch) : null;
    final moduleImports = [
      '...(options.imports ?? [])',
      if (graphql) factory!,
    ];
    final providers = [
      '{ provide: GRAPHLINK_OPTIONS, useValue: options }',
      '{ provide: APP_FILTER, useClass: GraphLinkExceptionFilter }',
      ...resolverNames,
    ];

    final forRoot = _cg.createMethod(
      methodName: 'static forRoot',
      arguments: ['options: GraphLinkModuleOptions = {}'],
      returnType: 'DynamicModule',
      statements: [
        if (graphql) _cg.constDecl('maxQueryDepth', 'options.maxQueryDepth ?? defaultMaxQueryDepth'),
        'return ${_cg.block([
          'module: GraphLinkModule,',
          'imports: ${_cg.arrayLiteral(moduleImports)},',
          'controllers: ${_cg.arrayLiteral(controllerNames)},',
          'providers: ${_cg.arrayLiteral(providers)},',
        ])};',
      ],
    );
    final configure = _cg.createMethod(
            methodName: 'configure',
            arguments: ['consumer: MiddlewareConsumer'],
            returnType: 'void',
            statements: [
              'consumer.apply(${[
                if (hasUploads) 'graphqlUploadExpress()',
                'queryDepthGuard(this.options.maxQueryDepth ?? defaultMaxQueryDepth)',
              ].join(', ')}).forRoutes(${apolloConfig.graphqlPath.quote()});',
            ],
          );
    const ctor = 'constructor(@Inject(GRAPHLINK_OPTIONS) private readonly options: GraphLinkModuleOptions) {}';
    final classBody = _cg.createClass(
      className: 'GraphLinkModule',
      implementsNames: graphql ? ['NestModule'] : null,
      statements: [if (graphql) ctor, forRoot, if (graphql) configure],
    );
    return '${GLClassModel(imports: imports, body: '@Module({})\n$classBody').toFileContent()}\n';
  }

  String _graphqlFactory(List<GLService> loaderServices, List<MappingEntry> batch) {
    final hasLoaders = batch.isNotEmpty;
    final factoryParams = [for (final s in loaderServices) '${s.token.firstLow}: ${s.token}'];
    final loaderFields = [
      for (final service in loaderServices)
        for (final m in service.mappings.where((m) => m.isBatch))
          '${m.key}: create${m.key.firstUp}Loader(${service.token.firstLow}${injectsContext(m.field) ? ', context' : ''}),',
    ];
    final createLoaders = hasLoaders
        ? _cg.createFunction(
            functionName: 'createLoaders',
            arguments: ['context: GraphLinkContext'],
            statements: ['return ${_cg.block(loaderFields)};'],
          )
        : null;

    final contextFunction = _cg.createMethod(
      methodName: 'context',
      arguments: ['connection: { req?: Request; res?: Response }'],
      async: true,
      statements: [
        _cg.constDecl('{ req, res }', 'connection'),
        _cg.constDecl('base', 'req && res && options.contextFactory ? await options.contextFactory(req, res) : {}'),
        _cg.constDecl('context', '{ ...base } as GraphLinkContext'),
        if (hasLoaders) 'context.loaders = createLoaders(context);',
        'return context;',
      ],
    );
    final onSubscribe = '${_cg.createMethod(
      methodName: 'onSubscribe',
      arguments: ['_ctx', '_id: string', 'payload: { query?: unknown }'],
      statements: ['return subscribeErrors(payload?.query, maxQueryDepth);'],
    )},';
    final config = _cg.block([
      'typeDefs,',
      'path: ${apolloConfig.graphqlPath.quote()},',
      if (hasUploads) ...[
        'resolvers: { ${grammar.uploadScalarNames.map((n) => '$n: GraphQLUpload').join(', ')} },',
        'csrfPrevention: false,',
      ],
      'includeStacktraceInErrorResponses: false,',
      if (hasDomainErrors) 'formatError: formatDomainError,',
      if (hasSubscriptions)
        "subscriptions: ${_cg.block([
              "'graphql-ws': ${_cg.block([
                    'path: ${apolloConfig.graphqlPath.quote()},',
                    '$onSubscribe',
                  ])},",
            ])},",
      '$contextFunction,',
    ]);
    final useFactory = '(${factoryParams.join(', ')}): ApolloDriverConfig => ${_cg.block([
      if (createLoaders != null) createLoaders,
      'return $config;',
    ])}';
    return 'GraphQLModule.forRootAsync<ApolloDriverConfig>(${_cg.block([
      'driver: ApolloDriver,',
      'imports: options.imports ?? [],',
      if (loaderServices.isNotEmpty) 'inject: ${_cg.arrayLiteral([for (final s in loaderServices) s.token])},',
      'useFactory: $useFactory,',
    ])})';
  }

  // ── index.ts ──────────────────────────────────────────────────────────────

  @override
  String serializeEntryPoint() {
    final lines = [
      "export { GraphLinkModule } from './graphlink.module.js';",
      "export { GRAPHLINK_OPTIONS } from './graphlink.options.js';",
      "export type { GraphLinkModuleOptions } from './graphlink.options.js';",
      "export type { GraphLinkContext${batchMappings().isNotEmpty ? ', GraphLinkLoaders' : ''} } from './context.js';",
      for (final service in grammar.services.values) ...[
        "export { ${service.token} } from './services/${kebabJs(service.token)}';",
        if (hasGuard(service)) "export { ${guardName(service)} } from './guards/${kebabJs(guardName(service))}';",
      ],
      if (hasInterceptor)
        "export { ${grammar.interfaces[glInterceptorInterfaceName]!.codeName} } from './interfaces/${tsSerializer.getFileNameFor(grammar.interfaces[glInterceptorInterfaceName]!).replaceAll('.ts', '.js')}';",
    ];
    return '${lines.join('\n')}\n';
  }
}

extension on String {
  String prefixed(String prefix) => '$prefix$this';
}

