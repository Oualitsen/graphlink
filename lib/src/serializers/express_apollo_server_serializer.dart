import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_validation_extension.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_schema_mapping.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:graphlink/src/typescript_code_gen_utils.dart';
import 'package:graphlink/src/serializers/server_serializer.dart';

class ExpressApolloServerSerializer extends ServerSerializer with ServerSerializerUtils {
  final TypeScriptSerializer tsSerializer;
  final ExpressApolloServerConfig apolloConfig;
  final _cg = TypeScriptCodeGenUtils();

  ExpressApolloServerSerializer(super.grammar, this.tsSerializer, this.apolloConfig);

  // ── uploads ───────────────────────────────────────────────────────────────

  String serializeFileUploadType() => [
    'export interface FileUpload {',
    '  filename: string;',
    '  mimetype: string;',
    '  encoding: string;',
    '  createReadStream(): NodeJS.ReadableStream;',
    '}',
    '',
  ].join('\n');

  String serializeGraphqlUploadDeclarations() => [
    "declare module 'graphql-upload/GraphQLUpload.mjs' {",
    "  import { GraphQLScalarType } from 'graphql';",
    '  const GraphQLUpload: GraphQLScalarType;',
    '  export default GraphQLUpload;',
    '}',
    '',
    "declare module 'graphql-upload/graphqlUploadExpress.mjs' {",
    "  import { RequestHandler } from 'express';",
    '  function graphqlUploadExpress(options?: {',
    '    maxFileSize?: number;',
    '    maxFiles?: number;',
    '  }): RequestHandler;',
    '  export default graphqlUploadExpress;',
    '}',
    '',
  ].join('\n');

  // ── context.ts ────────────────────────────────────────────────────────────

  @override
  String serializeContext() =>
      'export interface GraphLinkContext extends Record<string, unknown> {}\n';

  // ── impl/my-context.ts stub (written once) ────────────────────────────────

  String serializeContextStub(String generatedDir) {
    final dirName = generatedDir.split('/').last;
    return [
      "declare module '../$dirName/context.js' {",
      '  interface GraphLinkContext {',
      '    // add your typed context fields here, for example:',
      '    // userId?: string;',
      '    // roles?: string[];',
      '  }',
      '}',
      '',
    ].join('\n');
  }

  // ── typeDefs.ts ───────────────────────────────────────────────────────────

  @override
  String serializeTypeDefs() {
    final schema = GLGraphqlSerializer(grammar).generateSchema();
    final escaped = schema.replaceAll('`', r'\`');
    return 'export const typeDefs = `\n$escaped`;\n';
  }

  // ── services/XxxService.ts ────────────────────────────────────────────────

  /// Whether [field]'s resolver/service method receives the request `context`
  /// parameter — either globally (`injectContext`) or per-field via
  /// `@glInjectContext`.
  bool _injectsContext(GLField field) =>
      apolloConfig.injectContext || field.hasDirective(glInjectContext);

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

  @override
  String serializeService(GLService service) {
    final importedTypes = <String>{};
    final methods = <String>[];
    var hasUpload = false;

    for (final field in service.fields) {
      if (field.getDirectiveByName(glValidate)?.generated == true) continue;
      final argList = field.arguments.map((arg) {
        if (isUploadScalar(arg.type)) {
          hasUpload = true;
          return '${arg.codeName}: ${_tsUploadType(arg.type)}';
        }
        _collectType(arg.type, importedTypes);
        return '${arg.codeName}: ${tsSerializer.serializeType(arg.type)}';
      }).toList();
      final returnTs = tsSerializer.serializeType(field.type);
      _collectType(field.type, importedTypes);
      final isSubscription = service.getTypeByFieldName(field.name.token) == GLQueryType.subscription;
      final needsInfo = apolloConfig.useResolveInfo && !isSubscription;
      final params = [
        ...argList,
        if (_injectsContext(field)) 'context: GraphLinkContext',
        if (needsInfo) 'info: GraphQLResolveInfo',
      ];
      final returnDecl = isSubscription ? 'AsyncIterable<$returnTs>' : 'Promise<$returnTs>';
      methods.add('${field.name}(${params.join(', ')}): $returnDecl;');
    }

    for (final mapping in service.serviceMapping) {
      methods.add(_serviceMappingMethod(mapping, importedTypes));
    }

    final needsResolveInfoImport = apolloConfig.useResolveInfo;
    final needsContextImport = service.fields.any(_injectsContext) ||
        service.serviceMapping.any((m) => _injectsContext(m.field));

    final imp = _imports(importedTypes);
    final lines = [
      if (needsContextImport) "import { GraphLinkContext } from '../context.js';",
      if (needsResolveInfoImport) "import { GraphQLResolveInfo } from 'graphql';",
      if (hasUpload) "import type { FileUpload } from '../file-upload.js';",
      if (imp.isNotEmpty) imp,
    ];
    return '${lines.join('\n')}\n\n${_interface(service.token, methods)}';
  }

  String _serviceMappingMethod(GLSchemaMapping mapping, Set<String> importedTypes) {
    final parentName = mapping.type.token;
    _addIfKnown(parentName, importedTypes);
    final fieldTs = tsSerializer.serializeType(mapping.field.type);
    _collectType(mapping.field.type, importedTypes);

    if (mapping.isBatch) {
      return '${mapping.key}(items: ${parentName}[]): Promise<Map<${parentName}, ${fieldTs}>>;';
    }
    final argParams = mapping.field.arguments.map((arg) {
      _collectType(arg.type, importedTypes);
      return '${arg.codeName}: ${tsSerializer.serializeType(arg.type)}';
    });
    final nonBatchParams = [
      'item: ${parentName}',
      ...argParams,
      if (_injectsContext(mapping.field)) 'context: GraphLinkContext',
      if (apolloConfig.useResolveInfo) 'info: GraphQLResolveInfo',
    ];
    return '${mapping.key}(${nonBatchParams.join(', ')}): Promise<${fieldTs}>;';
  }

  // ── guards/XxxGuard.ts ────────────────────────────────────────────────────

  @override
  String? serializeGuard(GLService service) {
    final importedTypes = <String>{};
    final methods = <String>[];

    for (final field in service.fields) {
      if (!fieldHasValidation(field)) continue;
      final argList = field.arguments.map((arg) {
        _collectType(arg.type, importedTypes);
        return '${arg.codeName}: ${tsSerializer.serializeType(arg.type)}';
      }).toList();
      final guardParams = [...argList, if (_injectsContext(field)) 'context: GraphLinkContext', if (apolloConfig.useResolveInfo) 'info: GraphQLResolveInfo'];
      methods.add('${validationMethodName(field.name.token)}(${guardParams.join(', ')}): Promise<void>;');
    }

    if (methods.isEmpty) return null;

    final imp = _imports(importedTypes);
    final resolveInfoImport = apolloConfig.useResolveInfo ? "import { GraphQLResolveInfo } from 'graphql';" : '';
    final needsContextImport = service.fields.where(fieldHasValidation).any(_injectsContext);
    final lines = [
      if (needsContextImport) "import { GraphLinkContext } from '../context.js';",
      if (resolveInfoImport.isNotEmpty) resolveInfoImport,
      if (imp.isNotEmpty) imp,
    ];
    return '${lines.join('\n')}\n\n${_interface(_guardName(service), methods)}';
  }

  // ── loaders/XxxLoaders.ts ─────────────────────────────────────────────────

  String? serializeLoader(GLService service) {
    final batchMappings = service.mappings.where((m) => m.isBatch).toList();
    if (batchMappings.isEmpty) return null;

    final importedTypes = <String>{};
    for (final m in batchMappings) {
      _addIfKnown(m.type.token, importedTypes);
      _collectType(m.field.type, importedTypes);
    }

    final serviceImport = _kebabJs(service.token);
    final buf = StringBuffer();
    buf.writeln("import DataLoader from 'dataloader';");
    buf.writeln("import { ${service.token} } from '../services/$serviceImport';");
    final imp = _imports(importedTypes);
    if (imp.isNotEmpty) buf.writeln(imp);
    buf.writeln();

    for (final mapping in batchMappings) {
      buf.writeln(_loaderFactory(mapping, service.token));
    }
    return buf.toString();
  }

  String _loaderFactory(GLSchemaMapping mapping, String serviceName) {
    final parentName = mapping.type.token;
    final fieldTs = tsSerializer.serializeType(mapping.field.type);
    final factoryName = 'create${mapping.key.firstUp}Loader';
    final serviceVar = serviceName.firstLow;

    return '''export function $factoryName($serviceVar: $serviceName) {
  return new DataLoader<$parentName, $fieldTs>(async (items) => {
    const map = await $serviceVar.${mapping.key}([...items]);
    return items.map(v => map.get(v) ?? new Error(`$fieldTs not found for ${parentName.firstLow} \${(v as any).id}`));
  });
}
''';
  }

  // ── resolvers/buildResolvers.ts ───────────────────────────────────────────

  @override
  List<String> serializeResolvers() => [_serializeResolvers()];

  String _serializeResolvers() {
    final services = grammar.services.values.toList();
    final buf = StringBuffer();

    buf.writeln("import { IResolvers } from '@graphql-tools/utils';");
    final needsResolveInfo = apolloConfig.useResolveInfo;
    final graphqlImports = needsResolveInfo ? 'GraphQLError, GraphQLResolveInfo' : 'GraphQLError';
    buf.writeln("import { $graphqlImports } from 'graphql';");
    buf.writeln("import { GraphLinkContext } from '../context.js';");
    if (hasUploads) {
      buf.writeln("import GraphQLUpload from 'graphql-upload/GraphQLUpload.mjs';");
    }

    // collect types referenced via callToJson (projectable types + enums)
    final resolverTypes = <String>{};
    for (final service in services) {
      for (final field in service.fields) {
        _collectType(field.type, resolverTypes);
      }
      for (final mapping in service.mappings) {
        _collectType(mapping.field.type, resolverTypes);
      }
    }
    final resolverTypeImports = _imports(resolverTypes);
    if (resolverTypeImports.isNotEmpty) buf.writeln(resolverTypeImports);

    // service + guard imports (guard only if service has @glValidate fields)
    for (final service in services) {
      buf.writeln("import { ${service.token} } from '../services/${_kebabJs(service.token)}';");
      if (_hasGuard(service)) {
        final guard = _guardName(service);
        buf.writeln("import { $guard } from '../guards/${_kebabJs(guard)}';");
      }
    }

    // loader imports
    for (final service in services) {
      final batchMappings = service.mappings.where((m) => m.isBatch).toList();
      if (batchMappings.isEmpty) continue;
      final loaderFile = _loaderFileJs(service);
      for (final m in batchMappings) {
        buf.writeln("import { create${m.key.firstUp}Loader } from '../loaders/$loaderFile';");
      }
    }

    buf.writeln();
    buf.write('export function buildResolvers(\n');
    // required service params first
    for (final service in services) {
      buf.writeln('  ${service.token.firstLow}: ${service.token},');
    }
    for (final service in services) {
      if (_hasGuard(service)) {
        final guard = _guardName(service);
        buf.writeln('  ${guard.firstLow}: $guard,');
      }
    }
    buf.writeln('): IResolvers {');

    for (final service in services) {
      for (final m in service.mappings.where((m) => m.isBatch)) {
        buf.writeln('  const ${m.key}Loader = create${m.key.firstUp}Loader(${service.token.firstLow});');
      }
    }

    buf.writeln('  return {');
    for (final name in grammar.uploadScalarNames) {
      buf.writeln('    $name: GraphQLUpload,');
    }
    _writeRootBlock(buf, services, GLQueryType.query, 'Query');
    _writeRootBlock(buf, services, GLQueryType.mutation, 'Mutation');
    _writeSubscriptionBlock(buf, services);
    _writeTypeMappings(buf, services);
    buf.writeln('  };');
    buf.writeln('}');
    return buf.toString();
  }

  bool _hasGuard(GLService service) => service.fields.any(fieldHasValidation);

  /// Builds the resolver `args` destructuring pattern. Each entry is plain
  /// shorthand (`{ id }`) when the wire name is a legal identifier, or a rename
  /// (`{ return: return_ }`) when the wire name is a reserved word, so the local
  /// binding is safe while the property key stays the GraphQL wire name.
  String _argsDestructure(
      List<String> wireNames, List<String> codeNames, String emptyToken) {
    if (wireNames.isEmpty) return emptyToken;
    final parts = <String>[];
    for (var i = 0; i < wireNames.length; i++) {
      parts.add(wireNames[i] == codeNames[i]
          ? wireNames[i]
          : '${wireNames[i]}: ${codeNames[i]}');
    }
    return '{ ${parts.join(', ')} }';
  }

  void _writeRootBlock(StringBuffer buf, List<GLService> services, GLQueryType type, String block) {
    final entries = <_RootEntry>[];
    for (final service in services) {
      for (final field in service.fields) {
        if (field.getDirectiveByName(glValidate)?.generated == true) continue;
        if (service.getTypeByFieldName(field.name.token) != type) continue;
        entries.add(_RootEntry(
          service: service,
          fieldName: field.name.token,
          argNames: field.arguments.map((a) => a.token).toList(),
          argCodeNames: field.arguments.map((a) => a.codeName).toList(),
          argTypes: field.arguments.map((a) => a.type).toList(),
          returnType: field.type,
          needsInfo: apolloConfig.useResolveInfo,
          contextInjected: _injectsContext(field),
        ));
      }
    }
    if (entries.isEmpty) return;

    buf.writeln('    $block: {');
    for (final e in entries) {
      final sVar = e.service.token.firstLow;
      final gVar = _guardName(e.service).firstLow;
      final argsDestructure =
          _argsDestructure(e.argNames, e.argCodeNames, '__');

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
              ? 'const $resolved = await Promise.all($local);'
              : 'const $resolved = await $local;');
        }
      }

      final callArgs = [...resolvedArgNames, if (e.contextInjected) 'context', if (e.needsInfo) 'info'].join(', ');
      final serviceCall = '$sVar.${e.fieldName}($callArgs)';
      final toJsonExpr = tsSerializer.callToJson('_r', e.returnType);
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

      buf.writeln('      ${e.fieldName}: async $resolverSignature => {');
      for (final line in uploadAwaitLines) { buf.writeln('        $line'); }
      if (validateCall != null) buf.writeln('        $validateCall');
      buf.writeln('        return $returnExpr;');
      buf.writeln('      },');
    }
    buf.writeln('    },');
  }

  void _writeSubscriptionBlock(StringBuffer buf, List<GLService> services) {
    final entries = <_RootEntry>[];
    for (final service in services) {
      for (final field in service.fields) {
        if (service.getTypeByFieldName(field.name.token) != GLQueryType.subscription) continue;
        entries.add(_RootEntry(
          service: service,
          fieldName: field.name.token,
          argNames: field.arguments.map((a) => a.token).toList(),
          argCodeNames: field.arguments.map((a) => a.codeName).toList(),
          argTypes: field.arguments.map((a) => a.type).toList(),
          returnType: field.type,
          needsInfo: false,
          contextInjected: _injectsContext(field),
        ));
      }
    }
    if (entries.isEmpty) return;

    buf.writeln('    Subscription: {');
    for (final e in entries) {
      final sVar = e.service.token.firstLow;
      final argsDestructure =
          _argsDestructure(e.argNames, e.argCodeNames, '__');
      final callArgs = [...e.argCodeNames, if (e.contextInjected) 'context'].join(', ');
      final subscribeSignature = _resolverSignature('_', argsDestructure, e.contextInjected, false);
      final toJsonExpr = tsSerializer.callToJson('payload', e.returnType);
      buf.writeln('      ${e.fieldName}: {');
      buf.writeln('        subscribe: $subscribeSignature => $sVar.${e.fieldName}($callArgs),');
      buf.writeln('        resolve: (payload: any) => $toJsonExpr,');
      buf.writeln('      },');
    }
    buf.writeln('    },');
  }

  void _writeTypeMappings(StringBuffer buf, List<GLService> services) {
    final byType = <String, List<_MappingEntry>>{};
    for (final service in services) {
      for (final mapping in service.mappings) {
        byType.putIfAbsent(mapping.type.token, () => []);
        byType[mapping.type.token]!.add(_MappingEntry(mapping: mapping, service: service));
      }
    }

    for (final typeName in byType.keys) {
      buf.writeln('    $typeName: {');
      for (final entry in byType[typeName]!) {
        final m = entry.mapping;
        final sVar = entry.service.token.firstLow;
        buf.write('      ${m.field.name}: ');
        if (m.forbid) {
          buf.writeln("() => { throw new GraphQLError('Access denied', { extensions: { code: 'FORBIDDEN' } }); },");
        } else if (m.identity || m.forwarded) {
          buf.writeln('(parent) => parent.${m.field.name},');
        } else if (m.isBatch) {
          final toJsonExpr = tsSerializer.callToJson('_r', m.field.type);
          buf.writeln('(parent) => ${m.key}Loader.load(parent).then((_r) => $toJsonExpr),');
        } else {
          final argNames = m.field.arguments.map((a) => a.token).toList();
          final argCodeNames =
              m.field.arguments.map((a) => a.codeName).toList();
          final argsDestructure = _argsDestructure(argNames, argCodeNames, '_');
          final needsInfo = apolloConfig.useResolveInfo;
          final ctx = _injectsContext(m.field);
          final mappingCallArgs = [
            'parent',
            ...argCodeNames,
            if (ctx) 'context',
            if (needsInfo) 'info',
          ].join(', ');
          final mappingResolverArgs = _resolverSignature('parent', argsDestructure, ctx, needsInfo);
          final toJsonExpr = tsSerializer.callToJson('_r', m.field.type);
          buf.writeln('$mappingResolverArgs => $sVar.${m.key}($mappingCallArgs).then((_r) => $toJsonExpr),');
        }
      }
      buf.writeln('    },');
    }
  }

  // ── index.ts ──────────────────────────────────────────────────────────────

  @override
  String serializeEntryPoint() {
    final services = grammar.services.values.toList();

    // service + guard imports
    final buf = StringBuffer();
    buf.writeln("import express, { Express, Request, Response } from 'express';");
    buf.writeln("import cors from 'cors';");
    buf.writeln("import { ApolloServer } from '@apollo/server';");
    buf.writeln("import { expressMiddleware } from '@apollo/server/express4';");
    if (hasSubscriptions) {
      buf.writeln("import { createServer as createHttpServer, Server } from 'http';");
      buf.writeln("import { WebSocketServer } from 'ws';");
      buf.writeln("import { useServer } from 'graphql-ws/lib/use/ws';");
      buf.writeln("import { makeExecutableSchema } from '@graphql-tools/schema';");
      buf.writeln("import { ApolloServerPluginDrainHttpServer } from '@apollo/server/plugin/drainHttpServer';");
    }
    if (hasUploads) {
      buf.writeln("import graphqlUploadExpress from 'graphql-upload/graphqlUploadExpress.mjs';");
    }
    buf.writeln("import { GraphLinkContext } from './context.js';");
    buf.writeln("import { typeDefs } from './typeDefs.js';");
    buf.writeln("import { buildResolvers } from './resolvers/build-resolvers.js';");
    for (final service in services) {
      buf.writeln("import { ${service.token} } from './services/${_kebabJs(service.token)}';");
      if (_hasGuard(service)) {
        final guard = _guardName(service);
        buf.writeln("import { $guard } from './guards/${_kebabJs(guard)}';");
      }
    }
    buf.writeln();

    // GraphLinkServices interface
    final serviceFields = <String>[];
    for (final service in services) {
      serviceFields.add('${service.token.firstLow}: ${service.token};');
      if (_hasGuard(service)) {
        final guard = _guardName(service);
        serviceFields.add('${guard.firstLow}: $guard;');
      }
    }
    serviceFields.add('contextFactory?: (req: Request, res: Response) => GraphLinkContext | Promise<GraphLinkContext>;');
    buf.writeln(_cg.createInterface(
      interfaceName: 'GraphLinkServices',
      fields: serviceFields,
    ));
    buf.writeln();

    // buildResolvers call: services first, guards last (mirrors param order)
    final serviceArgs = services.map((s) => 'services.${s.token.firstLow}').join(', ');
    final guardArgs = services
        .where((s) => _hasGuard(s))
        .map((s) => 'services.${_guardName(s).firstLow}')
        .join(', ');
    final resolverArgs = [serviceArgs, if (guardArgs.isNotEmpty) guardArgs].join(', ');

    final middlewareLine = hasUploads
        ? "app.use('${apolloConfig.graphqlPath}', graphqlUploadExpress(), expressMiddleware(server, {"
        : "app.use('${apolloConfig.graphqlPath}', expressMiddleware(server, {";

    final List<String> createServerBody;
    if (hasSubscriptions) {
      createServerBody = [
        'const app = express();',
        'app.use(cors());',
        'app.use(express.json());',
        '',
        'const schema = makeExecutableSchema(${_cg.block([
          'typeDefs,',
          'resolvers: buildResolvers($resolverArgs),',
        ])});',
        'const httpServer = createHttpServer(app);',
        'const wsServer = new WebSocketServer(${_cg.block([
          'server: httpServer,',
          "path: '${apolloConfig.graphqlPath}',",
        ])});',
        'const cleanup = useServer({ schema }, wsServer as any);',
        '',
        'const server = new ApolloServer<GraphLinkContext>(${_cg.block([
          'schema,',
          // graphql-upload sends multipart/form-data, which Apollo's CSRF prevention
          // blocks by default unless the client sends a preflight-style header.
          if (hasUploads) 'csrfPrevention: false,',
          'plugins: [',
          '  ApolloServerPluginDrainHttpServer({ httpServer }),',
          '  {',
          '    async serverWillStart() {',
          '      return {',
          '        async drainServer() {',
          '          await cleanup.dispose();',
          '        },',
          '      };',
          '    },',
          '  },',
          '],',
        ])});',
        '',
        'await server.start();',
        middlewareLine,
        '  context: async ({ req, res }) =>',
        '    services.contextFactory ? services.contextFactory(req, res) : {} as GraphLinkContext,',
        '}));',
        'return httpServer;',
      ];
    } else {
      createServerBody = [
        'const app = express();',
        'app.use(cors());',
        'app.use(express.json());',
        '',
        'const server = new ApolloServer<GraphLinkContext>(${_cg.block([
          'typeDefs,',
          'resolvers: buildResolvers($resolverArgs),',
          // graphql-upload sends multipart/form-data, which Apollo's CSRF prevention
          // blocks by default unless the client sends a preflight-style header.
          if (hasUploads) 'csrfPrevention: false,',
        ])});',
        '',
        'await server.start();',
        middlewareLine,
        '  context: async ({ req, res }) =>',
        '    services.contextFactory ? services.contextFactory(req, res) : {} as GraphLinkContext,',
        '}));',
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

    return buf.toString();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _tsUploadType(GLType type) =>
      type is GLListType ? 'FileUpload[]' : 'FileUpload';

  String _guardName(GLService service) =>
      '${service.token.replaceFirst('Service', '')}Guard';

  /// kebab-case filename with .js extension (for import statements)
  String _kebabJs(String typeName) => '${typeName.toKebabCase()}.js';

  String _loaderFileJs(GLService service) =>
      '${service.token.replaceFirst('Service', '').toKebabCase()}-loaders.js';

  String _interface(String name, List<String> methods) {
    final buf = StringBuffer();
    buf.writeln('export interface $name {');
    for (final m in methods) {
      buf.writeln('  $m');
    }
    buf.write('}');
    return buf.toString();
  }

  String _imports(Set<String> typeNames) {
    final lines = <String>[];
    for (final name in typeNames) {
      String subdir;
      if (grammar.types.containsKey(name) || grammar.interfaces.containsKey(name)) {
        subdir = 'types';
      } else if (grammar.inputs.containsKey(name)) {
        subdir = 'inputs';
      } else if (grammar.enums.containsKey(name)) {
        subdir = 'enums';
      } else {
        continue;
      }
      lines.add("import { $name } from '../$subdir/${name.toKebabCase()}.js';");
    }
    return lines.join('\n');
  }

  void _collectType(GLType type, Set<String> out) {
    if (type is GLListType) {
      _collectType(type.inlineType, out);
    } else {
      _addIfKnown(type.token, out);
    }
  }

  void _addIfKnown(String name, Set<String> out) {
    if (grammar.types.containsKey(name) ||
        grammar.interfaces.containsKey(name) ||
        grammar.inputs.containsKey(name) ||
        grammar.enums.containsKey(name)) {
      out.add(name);
    }
  }
}

class _RootEntry {
  final GLService service;
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
  _RootEntry({
    required this.service,
    required this.fieldName,
    required this.argNames,
    required this.argCodeNames,
    required this.argTypes,
    required this.returnType,
    required this.needsInfo,
    required this.contextInjected,
  });
}

class _MappingEntry {
  final GLSchemaMapping mapping;
  final GLService service;
  _MappingEntry({required this.mapping, required this.service});
}
