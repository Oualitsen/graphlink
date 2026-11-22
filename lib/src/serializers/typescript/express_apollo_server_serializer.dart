import 'package:graphlink/src/generators/openapi_generator.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_source_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_intercept_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_validation_extension.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_schema_mapping.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/typescript/express_apollo_rest_constants.dart';
import 'package:graphlink/src/serializers/typescript/express_apollo_rest_serializer.dart';
import 'package:graphlink/src/serializers/typescript/express_apollo_server_constants.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_server_extension.dart';
import 'package:graphlink/src/typescript_code_gen_utils.dart';
import 'package:graphlink/src/serializers/typescript/typescript_apollo_server_base.dart';

class ExpressApolloServerSerializer extends TypeScriptApolloServerSerializerBase {
  final _cg = TypeScriptCodeGenUtils();

  ExpressApolloServerSerializer(super.grammar, super.tsSerializer, super.apolloConfig);

  late final ExpressApolloRestSerializer _rest = ExpressApolloRestSerializer(grammar, tsSerializer, apolloConfig);

  bool get hasRest => _rest.hasRest;

  bool get hasRestUploads => _rest.hasUploads;

  String serializeRestUploads() => _rest.serializeUploads();

  bool get hasRestDownloads => _rest.hasDownloads;

  String serializeRestDownloads() => _rest.serializeDownloads();

  String serializeRestRouter({OpenApiOutput? openApi}) => _rest.serializeRestRouter(openApi: openApi);

  String serializeRestSupport() {
    if (!hasDomainErrors) return expressRestSupport;
    return "import { GraphLinkDomainError, domainErrorResponse } from '../errors/graph-link-domain-error.js';\n${expressRestSupport.replaceFirst(
      '         if (error instanceof RestError) {',
      '''         if (error instanceof GraphLinkDomainError) {
            const failure = domainErrorResponse(error);
            res.status(failure.status).json(failure.body);
            return;
         }
         if (error instanceof RestError) {''',
    )}";
  }



  // ── services/XxxService.ts ────────────────────────────────────────────────

  /// Apollo resolver positional signature. `context` is the 3rd positional
  /// arg, so when it isn't injected but `info` (4th) is, a `_ctx` placeholder
  /// keeps `info` in position.
  String _resolverSignature(String parentParam, String argsDestructure, bool ctx, bool info) {
    final parts = [parentParam, argsDestructure];
    if (ctx) {
      parts.add('context');
      if (info) parts.add('info');
    } else if (info) {
      parts.add('_ctx');
      parts.add('info');
    }
    return '(${parts.join(', ')})';
  }

  // ── resolvers/buildResolvers.ts ───────────────────────────────────────────

  @override
  List<String> serializeResolvers() => [_serializeResolvers()];

  String _serializeResolvers() {
    final services = grammar.services.values.toList();

    // collect types referenced via callToJson (projectable types + enums)
    final resolverTypes = <String>{};
    for (final service in services) {
      for (final field in service.fields) {
        collectType(field.type, resolverTypes);
      }
      for (final mapping in service.mappings) {
        collectType(mapping.field.type, resolverTypes);
      }
    }
    final resolverTypeImports = importLines(resolverTypes);

    final imports = <String>[
      "import { IResolvers } from '@graphql-tools/utils';",
      "import { ${apolloConfig.useResolveInfo ? 'GraphQLError, GraphQLResolveInfo' : 'GraphQLError'} } from 'graphql';",
      hasBatchLoaders
          ? "import { GraphLinkContext, GraphLinkLoaders } from '../context.js';"
          : "import { GraphLinkContext } from '../context.js';",
      if (grammar.carriesSources) "import { attachSource, sourceOf } from '../source.js';",
      if (hasUploads) "import GraphQLUpload from 'graphql-upload/GraphQLUpload.mjs';",
      if (resolverTypeImports.isNotEmpty) resolverTypeImports,
      // service + guard imports (guard only if service has @glValidate fields)
      for (final service in services) ...[
        "import { ${service.token} } from '../services/${kebabJs(service.token)}';",
        if (hasGuard(service)) "import { ${guardName(service)} } from '../guards/${kebabJs(guardName(service))}';",
      ],
      if (hasInterceptor) ...[
        "import { ${grammar.interfaces[glInterceptorInterfaceName]!.codeName} } from '../interfaces/${tsSerializer.getFileNameFor(grammar.interfaces[glInterceptorInterfaceName]!).replaceAll('.ts', '.js')}';",
        if (grammar.enums.containsKey(glInterceptorTagEnumName))
          "import { ${grammar.enums[glInterceptorTagEnumName]!.codeName} } from '../enums/${tsSerializer.getFileNameFor(grammar.enums[glInterceptorTagEnumName]!).replaceAll('.ts', '.js')}';",
      ],
    ];

    // buildResolvers params: required services first, guards, then the
    // interceptor (single instance, not per-service).
    final params = <String>[
      for (final service in services) '${service.token.firstLow}: ${service.token}',
      for (final service in services)
        if (hasGuard(service)) '${guardName(service).firstLow}: ${guardName(service)}',
      if (hasInterceptor)
        'interceptor: ${grammar.interfaces[glInterceptorInterfaceName]!.codeName}',
    ];

    final query = _serializeRootBlock(services, GLQueryType.query, 'Query');
    final mutation = _serializeRootBlock(services, GLQueryType.mutation, 'Mutation');
    final subscription = _serializeSubscriptionBlock(services);
    final resolverMap = [
      if (hasUploads)
        for (final name in grammar.uploadScalarNames) '$name: GraphQLUpload',
      if (query != null) query,
      if (mutation != null) mutation,
      if (subscription != null) subscription,
      ..._serializeTypeMappings(services),
    ].map((e) => '$e,').toList();

    final buildResolvers = _cg.createFunction(
      functionName: 'buildResolvers',
      arguments: params,
      returnType: 'IResolvers',
      exported: true,
      statements: [
        'return ${_cg.block(resolverMap)};',
      ],
    );

    return '${imports.join('\n')}\n\n$buildResolvers\n';
  }

  /// `runBefore(...)` call inserted as the first statement of an intercepted
  /// resolver, before any upload/validation/service call.
  String? _runBeforeStatement(RootEntry e) {
    if (!e.intercepted) return null;
    final callArgs = [
      ...interceptorTagCallArg(e.field, e.queryType),
      '"${e.fieldName}"',
      '[${e.argCodeNames.join(', ')}]',
      'context',
      // `info` is a required param, so a resolver that doesn't destructure it
      // (e.g. a subscription) must still pass literal `null` positionally.
      if (apolloConfig.useResolveInfo) (e.needsInfo ? 'info' : 'null'),
    ].join(', ');
    return 'await interceptor.runBefore($callArgs);';
  }

  /// Builds a resolver-map entry `fieldName: <value>,`. With [signature],
  /// [bodyStatements] become an `async (…) => { … }` function body; without it,
  /// they become an object literal (e.g. a subscription's `{ subscribe, resolve }`).
  String _entry(String fieldName, List<String> bodyStatements, {String? signature}) {
    final block = _cg.block(bodyStatements);
    final value = signature != null ? 'async $signature => $block' : block;
    return '$fieldName: $value,';
  }

  String? _serializeRootBlock(List<GLService> services, GLQueryType type, String blockName) {
    final entries = <RootEntry>[];
    for (final service in services) {
      for (final field in service.fields) {
        if (field.getDirectiveByName(glValidate)?.generated == true) continue;
        if (grammar.isRestField(field)) continue;
        if (service.getTypeByFieldName(field.name.token) != type) continue;
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
          needsInfo: apolloConfig.useResolveInfo,
          // an intercepted resolver always needs `context` locally to pass to
          // `runBefore`, regardless of whether the SERVICE method itself opted
          // into @glInjectContext/global injectContext.
          contextInjected: injectsContext(field) || intercepted,
          intercepted: intercepted,
        ));
      }
    }
    if (entries.isEmpty) return null;

    final fieldEntries = <String>[];
    for (final e in entries) {
      final sVar = e.service.token.firstLow;
      final gVar = guardName(e.service).firstLow;
      final argsDestructure =
          argsDestructurePattern(e.argNames, e.argCodeNames, '__');

      // resolve upload args before passing to service. The destructured local
      // binding is the (parameter-safe) code name, so awaits/calls use it.
      final resolvedArgNames = List<String>.from(e.argCodeNames);
      final uploadAwaitLines = <String>[];
      for (int i = 0; i < e.argTypes.length; i++) {
        if (isUploadScalar(e.argTypes[i])) {
          final local = e.argCodeNames[i];
          final resolved = '_$local';
          resolvedArgNames[i] = resolved;
          uploadAwaitLines.add(e.argTypes[i] is GLListType
              ? _cg.constDecl(resolved, 'await Promise.all($local)')
              : _cg.constDecl(resolved, 'await $local'));
        }
      }

      final callArgs = [...resolvedArgNames, if (e.contextInjected) 'context', if (e.needsInfo) 'info'].join(', ');
      final serviceCall = '$sVar.${e.fieldName}($callArgs)';
      final toJsonExpr = tsSerializer.carryingSource(() => tsSerializer.toJsonExpr(e.returnType, '_r'));
      final needsWrap = e.returnType is GLListType ||
          grammar.isEnum(e.returnType.firstType.token) ||
          grammar.isProjectableType(e.returnType.firstType.token);
      final returnExpr = needsWrap
          ? '$serviceCall.then((_r) => $toJsonExpr)'
          : serviceCall;
      final hasValidate = fieldHasValidation(e.service.fields
          .firstWhere((f) => f.name.token == e.fieldName));
      final validateCall = hasValidate
          ? 'await $gVar.${validationMethodName(e.fieldName)}($callArgs);'
          : null;
      final resolverSignature = _resolverSignature('_', argsDestructure, e.contextInjected, e.needsInfo);

      final runBefore = _runBeforeStatement(e);
      fieldEntries.add(_entry(e.fieldName, [
        if (runBefore != null) runBefore,
        ...uploadAwaitLines,
        if (validateCall != null) validateCall,
        'return $returnExpr;',
      ], signature: resolverSignature));
    }
    return '$blockName: ${_cg.block(fieldEntries)}';
  }

  String? _serializeSubscriptionBlock(List<GLService> services) {
    final entries = <RootEntry>[];
    for (final service in services) {
      for (final field in service.fields) {
        if (service.getTypeByFieldName(field.name.token) != GLQueryType.subscription) continue;
        final intercepted = grammar.isIntercepted(field, GLQueryType.subscription);
        entries.add(RootEntry(
          service: service,
          field: field,
          queryType: GLQueryType.subscription,
          fieldName: field.name.token,
          argNames: field.arguments.map((a) => a.token).toList(),
          argCodeNames: field.arguments.map((a) => a.codeName).toList(),
          argTypes: field.arguments.map((a) => a.type).toList(),
          returnType: field.type,
          needsInfo: false,
          contextInjected: injectsContext(field) || intercepted,
          intercepted: intercepted,
        ));
      }
    }
    if (entries.isEmpty) return null;

    final fieldEntries = <String>[];
    for (final e in entries) {
      final sVar = e.service.token.firstLow;
      final argsDestructure =
          argsDestructurePattern(e.argNames, e.argCodeNames, '__');
      final callArgs = [...e.argCodeNames, if (e.contextInjected) 'context'].join(', ');
      final subscribeSignature = _resolverSignature('_', argsDestructure, e.contextInjected, false);
      final toJsonExpr = tsSerializer.carryingSource(() => tsSerializer.toJsonExpr(e.returnType, 'payload'));
      final runBefore = _runBeforeStatement(e);
      final subscribeBody = runBefore == null
          ? '$sVar.${e.fieldName}($callArgs)'
          : '(async () => { $runBefore return $sVar.${e.fieldName}($callArgs); })()';
      fieldEntries.add(_entry(e.fieldName, [
        'subscribe: $subscribeSignature => $subscribeBody,',
        'resolve: (payload: any) => $toJsonExpr,',
      ]));
    }
    return 'Subscription: ${_cg.block(fieldEntries)}';
  }

  List<String> _serializeTypeMappings(List<GLService> services) {
    final byType = <String, List<MappingEntry>>{};
    for (final service in services) {
      for (final mapping in service.mappings) {
        byType.putIfAbsent(mapping.type.token, () => []);
        byType[mapping.type.token]!.add(MappingEntry(mapping: mapping, service: service));
      }
    }

    final passThrough = mapToPassThroughFields();
    return [
      for (final typeName in {...byType.keys, ...passThrough.keys})
        '$typeName: ${_cg.block([
          for (final entry in byType[typeName] ?? <MappingEntry>[])
            '${entry.mapping.field.name}: ${_mappingResolver(entry.mapping, entry.service.token.firstLow)},',
          for (final name in passThrough[typeName] ?? <String>[])
            '$name: (parent) => parent,',
        ])}',
    ];
  }

  /// `runBefore(...)` call for an intercepted mapping field, inserted once
  /// per resolved parent (not inside the DataLoader's batch function, which
  /// only sees an already-collapsed array with no single caller to attribute
  /// the check to).
  String _mappingRunBeforeStatement(GLSchemaMapping m) {
    final argCodeNames = realMappingArgs(m).map((a) => a.codeName).toList();
    final callArgs = [
      ...interceptorTagCallArg(m.field),
      '"${m.type.token}.${m.field.name}"',
      '[${argCodeNames.join(', ')}]',
      'context',
      if (apolloConfig.useResolveInfo) 'null',
    ].join(', ');
    return 'await interceptor.runBefore($callArgs);';
  }

  /// The resolver expression (no `fieldName:` key, no trailing comma) for a
  /// single `@glMapsTo` / batch / identity / forbidden field mapping.
  String _mappingResolver(GLSchemaMapping m, String sVar) {
    if (m.forbid) {
      return "() => { throw new GraphQLError('Access denied', { extensions: { code: 'FORBIDDEN' } }); }";
    }

    final intercepted = grammar.isIntercepted(m.field);
    final runBefore = intercepted ? _mappingRunBeforeStatement(m) : null;

    if (m.identity || m.forwarded) {
      final expr = 'parent.${m.field.name}';
      if (runBefore == null) return '(parent) => $expr';
      final sig = _resolverSignature('parent', '_', true, false);
      return 'async $sig => ${_cg.block([runBefore, 'return $expr;'])}';
    }
    if (m.isBatch) {
      final realArgs = realMappingArgs(m);
      final argNames = realArgs.map((a) => a.token).toList();
      final argCodeNames = realArgs.map((a) => a.codeName).toList();
      final argsDestructure = argsDestructurePattern(argNames, argCodeNames, '_');
      final loaderAccess = realArgs.isEmpty
          ? 'context.loaders.${m.key}'
          : 'context.loaders.${m.key}(${argCodeNames.join(', ')})';
      final toJsonExpr = tsSerializer.carryingSource(() => tsSerializer.toJsonExpr(m.field.type, '_r'));
      const contextType = 'GraphLinkContext & { loaders: GraphLinkLoaders }';
      if (runBefore == null) {
        return '(parent, $argsDestructure, context: $contextType) => $loaderAccess.load(parent).then((_r) => $toJsonExpr)';
      }
      return 'async (parent, $argsDestructure, context: $contextType) => ${_cg.block([
        runBefore,
        'const _r = await $loaderAccess.load(parent);',
        'return $toJsonExpr;',
      ])}';
    }
    // The synthetic `value` arg is the parent source instance, not a
    // GraphQL field argument — it is never destructured off `args`, and
    // the resolver passes `parent` in its call slot.
    final realArgs = m.field.arguments
        .where((a) => !a.skipOnGraphqlSerialization)
        .toList();
    final argNames = realArgs.map((a) => a.token).toList();
    final argCodeNames = realArgs.map((a) => a.codeName).toList();
    final argsDestructure = argsDestructurePattern(argNames, argCodeNames, '_');
    final needsInfo = apolloConfig.useResolveInfo;
    final ctx = injectsContext(m.field) || intercepted;
    final mappingCallArgs = [
      ...m.field.arguments
          .map((a) => a.skipOnGraphqlSerialization ? (carriesSource(m.type.token) ? 'sourceOf(parent)' : 'parent') : a.codeName),
      if (ctx) 'context',
      if (needsInfo) 'info',
    ].join(', ');
    final mappingResolverArgs = _resolverSignature('parent', argsDestructure, ctx, needsInfo);
    final toJsonExpr = tsSerializer.carryingSource(() => tsSerializer.toJsonExpr(m.field.type, '_r'));
    final serviceCall = '$sVar.${m.key}($mappingCallArgs)';
    if (runBefore == null) {
      return '$mappingResolverArgs => $serviceCall.then((_r) => $toJsonExpr)';
    }
    return 'async $mappingResolverArgs => ${_cg.block([
      runBefore,
      'const _r = await $serviceCall;',
      'return $toJsonExpr;',
    ])}';
  }

  // ── index.ts ──────────────────────────────────────────────────────────────

  @override
  String serializeEntryPoint() {
    if (grammar.restOnly) return _restOnlyEntryPoint();
    final services = grammar.services.values.toList();

    final interceptorDef = hasInterceptor ? grammar.interfaces[glInterceptorInterfaceName]! : null;
    final imports = <String>[
      "import express, { Express, NextFunction, Request, RequestHandler, Response } from 'express';",
      "import { DocumentNode, GraphQLError, Kind, parse, SelectionSetNode } from 'graphql';",
      "import cors from 'cors';",
      "import { ApolloServer } from '@apollo/server';",
      if (hasDomainErrors && !grammar.restOnly) "import { formatDomainError } from './errors/graph-link-domain-error.js';",
      "import { expressMiddleware } from '@apollo/server/express4';",
      if (hasSubscriptions) ...[
        "import { createServer as createHttpServer, Server } from 'http';",
        "import { WebSocketServer } from 'ws';",
        "import { useServer } from 'graphql-ws/lib/use/ws';",
        "import { makeExecutableSchema } from '@graphql-tools/schema';",
        "import { ApolloServerPluginDrainHttpServer } from '@apollo/server/plugin/drainHttpServer';",
      ],
      if (hasUploads) "import graphqlUploadExpress from 'graphql-upload/graphqlUploadExpress.mjs';",
      "import { GraphLinkContext } from './context.js';",
      "import { typeDefs } from './typeDefs.js';",
      "import { buildResolvers } from './resolvers/build-resolvers.js';",
      if (_rest.hasRest) "import { buildRestRouter } from './rest/build-rest-router.js';",
      if (interceptorDef != null)
        "import { ${interceptorDef.codeName} } from './interfaces/${tsSerializer.getFileNameFor(interceptorDef).replaceAll('.ts', '.js')}';",
      for (final service in services) ...[
        "import { ${service.token} } from './services/${kebabJs(service.token)}';",
        if (hasGuard(service)) "import { ${guardName(service)} } from './guards/${kebabJs(guardName(service))}';",
      ],
      for (final service in services)
        for (final m in service.mappings.where((m) => m.isBatch))
          "import { create${m.key.firstUp}Loader } from './loaders/${loaderFileJs(service)}';",
    ];

    final buf = StringBuffer();
    buf.writeln(expressRequestGuards);
    if (hasSubscriptions) buf.writeln(expressSubscribeGuard);

    // GraphLinkServices interface
    final serviceFields = <String>[];
    for (final service in services) {
      serviceFields.add('${service.token.firstLow}: ${service.token};');
      if (hasGuard(service)) {
        final guard = guardName(service);
        serviceFields.add('${guard.firstLow}: $guard;');
      }
    }
    if (hasInterceptor) {
      serviceFields.add(
          'interceptor?: ${grammar.interfaces[glInterceptorInterfaceName]!.codeName};');
    }
    serviceFields.add('maxQueryDepth?: number;');
    serviceFields.add('contextFactory?: (req: Request, res: Response) => GraphLinkContext | Promise<GraphLinkContext>;');
    buf.writeln(_cg.createInterface(
      interfaceName: 'GraphLinkServices',
      fields: serviceFields,
    ));
    buf.writeln();

    // Per-request DataLoaders: created fresh for each request/subscription and
    // attached to the context, so their caches are scoped to one operation and
    // released when it ends (never shared across the whole process).
    final loaderFields = <String>[
      for (final service in services)
        for (final m in service.mappings.where((m) => m.isBatch))
          '${m.key}: create${m.key.firstUp}Loader(services.${service.token.firstLow}${injectsContext(m.field) ? ', context' : ''}),',
    ];
    if (loaderFields.isNotEmpty) {
      buf.writeln(_cg.createFunction(
        functionName: 'createLoaders',
        arguments: [
          'services: GraphLinkServices',
          if (anyBatchInjectsContext) 'context: GraphLinkContext',
        ],
        statements: ['return ${_cg.block(loaderFields)};'],
      ));
      buf.writeln();
    }

    // buildResolvers call: services first, guards last (mirrors param order)
    final serviceArgs = services.map((s) => 'services.${s.token.firstLow}').join(', ');
    final guardArgs = services
        .where((s) => hasGuard(s))
        .map((s) => 'services.${guardName(s).firstLow}')
        .join(', ');
    final resolverArgs = [
      serviceArgs,
      if (guardArgs.isNotEmpty) guardArgs,
      if (hasInterceptor) 'services.interceptor!',
    ].join(', ');

    // A schema using @glIntercept anywhere requires an interceptor — fail
    // fast at server start rather than on the first intercepted request.
    final interceptorGuard = hasInterceptor
        ? _cg.ifStatement(
            condition: '!services.interceptor',
            ifBlockStatements: [
              "throw new Error('GraphLinkServices.interceptor is required: the schema uses @glIntercept.');",
            ],
          )
        : null;

    final List<String> createServerBody;
    if (hasSubscriptions) {
      final pluginsArray = _cg.arrayLiteral([
        'ApolloServerPluginDrainHttpServer({ httpServer })',
        _cg.block([
          '${_cg.createMethod(
            methodName: 'serverWillStart',
            async: true,
            statements: [
              'return ${_cg.block([
                '${_cg.createMethod(
                  methodName: 'drainServer',
                  async: true,
                  statements: ['await cleanup.dispose();'],
                )},',
              ])};',
            ],
          )},',
        ]),
      ]);
      createServerBody = [
        if (interceptorGuard != null) interceptorGuard,
        _cg.constDecl('maxQueryDepth', 'services.maxQueryDepth ?? defaultMaxQueryDepth'),
        _cg.constDecl('app', 'express()'),
        'app.use(cors());',
        'app.use(express.json());',
        '',
        _cg.constDecl('schema', 'makeExecutableSchema(${_cg.block([
          'typeDefs,',
          'resolvers: buildResolvers($resolverArgs),',
        ])})'),
        _cg.constDecl('httpServer', 'createHttpServer(app)'),
        _cg.constDecl('wsServer', 'new WebSocketServer(${_cg.block([
          'server: httpServer,',
          "path: '${apolloConfig.graphqlPath}',",
        ])})'),
        _cg.constDecl('cleanup', 'useServer({ schema${_wsContextOption()}, onSubscribe: (_ctx, message) => subscribeErrors(message.payload?.query, maxQueryDepth) }, wsServer as any)'),
        '',
        _cg.constDecl('server', 'new ApolloServer<GraphLinkContext>(${_cg.block([
          'schema,',
          'includeStacktraceInErrorResponses: false,',
          if (hasDomainErrors) 'formatError: formatDomainError,',
          // graphql-upload sends multipart/form-data, which Apollo's CSRF prevention
          // blocks by default unless the client sends a preflight-style header.
          if (hasUploads) 'csrfPrevention: false,',
          'plugins: $pluginsArray,',
        ])})'),
        '',
        'await server.start();',
        _registerMiddleware(),
        if (_rest.hasRest) 'app.use(buildRestRouter(services));',
        'app.use(graphLinkErrorHandler);',
        'return httpServer;',
      ];
    } else {
      createServerBody = [
        if (interceptorGuard != null) interceptorGuard,
        _cg.constDecl('maxQueryDepth', 'services.maxQueryDepth ?? defaultMaxQueryDepth'),
        _cg.constDecl('app', 'express()'),
        'app.use(cors());',
        'app.use(express.json());',
        '',
        _cg.constDecl('server', 'new ApolloServer<GraphLinkContext>(${_cg.block([
          'typeDefs,',
          'resolvers: buildResolvers($resolverArgs),',
          'includeStacktraceInErrorResponses: false,',
          if (hasDomainErrors) 'formatError: formatDomainError,',
          // graphql-upload sends multipart/form-data, which Apollo's CSRF prevention
          // blocks by default unless the client sends a preflight-style header.
          if (hasUploads) 'csrfPrevention: false,',
        ])})'),
        '',
        'await server.start();',
        _registerMiddleware(),
        if (_rest.hasRest) 'app.use(buildRestRouter(services));',
        'app.use(graphLinkErrorHandler);',
        'return app;',
      ];
    }

    buf.writeln(_cg.createFunction(
      functionName: 'createServer',
      arguments: ['services: GraphLinkServices'],
      returnType: hasSubscriptions ? 'Server' : 'Express',
      async: true,
      exported: true,
      statements: createServerBody,
    ));

    return '${GLClassModel(imports: imports, body: buf.toString()).toFileContent()}\n';
  }

  /// A schema with REST operations only: an Express app with the REST router, no Apollo, no schema, no resolvers.
  String _restOnlyEntryPoint() {
    final services = grammar.services.values.toList();
    final guarded = services.where(hasGuard).toList();
    final imports = [
      "import express, { Express, Request, Response } from 'express';",
      "import cors from 'cors';",
      "import { GraphLinkContext } from './context.js';",
      "import { buildRestRouter } from './rest/build-rest-router.js';",
      "import { restErrorHandler } from './rest/support.js';",
      for (final service in services) "import { ${service.token} } from './services/${kebabJs(service.token)}';",
      for (final service in guarded) "import { ${guardName(service)} } from './guards/${kebabJs(guardName(service))}';",
    ];
    final body = StringBuffer()
      ..writeln(_cg.createInterface(interfaceName: 'GraphLinkServices', fields: [
        for (final service in services) '${service.token.firstLow}: ${service.token};',
        for (final service in guarded) '${guardName(service).firstLow}: ${guardName(service)};',
        'contextFactory?: (req: Request, res: Response) => GraphLinkContext | Promise<GraphLinkContext>;',
      ]))
      ..writeln()
      ..writeln(_cg.createFunction(
        functionName: 'createServer',
        arguments: ['services: GraphLinkServices'],
        returnType: 'Express',
        async: true,
        exported: true,
        statements: [
          _cg.constDecl('app', 'express()'),
          'app.use(cors());',
          'app.use(buildRestRouter(services));',
          'app.use(restErrorHandler);',
          'return app;',
        ],
      ));
    return '${GLClassModel(imports: imports, body: body.toString()).toFileContent()}\n';
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// The `context` option for the WS (`useServer`) transport. Subscriptions have
  /// no `contextFactory` (no req/res), so the WS context carries only per-request
  /// loaders — built after the context object exists when they need to forward it.
  String _wsContextOption() {
    if (!hasBatchLoaders) return '';
    if (anyBatchInjectsContext) {
      final body = _cg.block([
        _cg.constDecl('context', '{} as GraphLinkContext'),
        'context.loaders = createLoaders(services, context);',
        'return context;',
      ]);
      return ', context: () => $body';
    }
    return ', context: () => ({ loaders: createLoaders(services) })';
  }

  /// `app.use('/path', [graphqlUploadExpress(),] expressMiddleware(server, { context }))`.
  String _registerMiddleware() {
    final String contextCallback;
    if (anyBatchInjectsContext) {
      // Loaders forward the request context to their batch service methods, so
      // the context object must exist before the loaders are built.
      final body = _cg.block([
        _cg.constDecl('context', 'services.contextFactory ? await services.contextFactory(req, res) : {} as GraphLinkContext', type: 'GraphLinkContext'),
        'context.loaders = createLoaders(services, context);',
        'return context;',
      ]);
      contextCallback = 'context: async ({ req, res }) => $body,';
    } else if (hasBatchLoaders) {
      final body = _cg.block([
        _cg.constDecl('base', 'services.contextFactory ? await services.contextFactory(req, res) : {} as GraphLinkContext'),
        'return { ...base, loaders: createLoaders(services) };',
      ]);
      contextCallback = 'context: async ({ req, res }) => $body,';
    } else {
      final context = _cg.ternaryOp(
        condition: 'services.contextFactory',
        positiveStatement: 'services.contextFactory(req, res)',
        negativeStatement: '{} as GraphLinkContext',
      );
      contextCallback = 'context: async ({ req, res }) => $context,';
    }
    final options = _cg.block([contextCallback]);
    final uploadHandler = hasUploads ? 'graphqlUploadExpress(), ' : '';
    return "app.use('${apolloConfig.graphqlPath}', ${uploadHandler}queryDepthGuard(maxQueryDepth), expressMiddleware(server, $options));";
  }

}

class RootEntry {
  final GLService service;
  final GLField field;
  final GLQueryType queryType;
  final String fieldName;

  /// Original GraphQL argument names — the wire/property keys read off the
  /// resolver `args` object (always the schema token).
  final List<String> argNames;

  /// Parameter-safe identifiers parallel to [argNames]; equal to the wire name
  /// unless it collides with a reserved word (`return` → `return_`). Used for
  /// the destructuring target, local bindings, and service-call arguments.
  final List<String> argCodeNames;
  final List<GLType> argTypes;
  final GLType returnType;
  final bool needsInfo;
  final bool contextInjected;

  final bool intercepted;
  RootEntry({
    required this.service,
    required this.field,
    required this.queryType,
    required this.fieldName,
    required this.argNames,
    required this.argCodeNames,
    required this.argTypes,
    required this.returnType,
    required this.needsInfo,
    required this.contextInjected,
    required this.intercepted,
  });
}

class MappingEntry {
  final GLSchemaMapping mapping;
  final GLService service;
  MappingEntry({required this.mapping, required this.service});
}
