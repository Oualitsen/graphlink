import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_shcema_mapping.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/graphq_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:graphlink/src/typescript_code_gen_utils.dart';

class ExpressApolloServerSerializer {
  final GLParser grammar;
  final TypeScriptSerializer tsSerializer;
  final ExpressApolloServerConfig apolloConfig;
  final _cg = TypeScriptCodeGenUtils();

  ExpressApolloServerSerializer(this.grammar, this.tsSerializer, this.apolloConfig);

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
    "declare module 'graphql-upload/GraphQLUpload.js' {",
    "  import { GraphQLScalarType } from 'graphql';",
    '  const GraphQLUpload: GraphQLScalarType;',
    '  export default GraphQLUpload;',
    '}',
    '',
    "declare module 'graphql-upload/graphqlUploadExpress.js' {",
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

  String serializeTypeDefs() {
    final schema = GLGraphqSerializer(grammar).generateSchema();
    final escaped = schema.replaceAll('`', r'\`');
    return 'export const typeDefs = `\n$escaped`;\n';
  }

  // ── services/XxxService.ts ────────────────────────────────────────────────

  String serializeService(GLService service) {
    final importedTypes = <String>{};
    final methods = <String>[];
    var hasUpload = false;

    for (final field in service.fields) {
      if (field.getDirectiveByName(glValidate)?.generated == true) continue;
      final argList = field.arguments.map((arg) {
        if (_isUploadScalar(arg.type)) {
          hasUpload = true;
          return '${arg.token}: ${_tsUploadType(arg.type)}';
        }
        _collectType(arg.type, importedTypes);
        return '${arg.token}: ${tsSerializer.serializeType(arg.type, false)}';
      }).toList();
      final returnTs = tsSerializer.serializeType(field.type, false);
      _collectType(field.type, importedTypes);
      final isSubscription = service.getTypeByFieldName(field.name.token) == GLQueryType.subscription;
      final params = [...argList, 'context: GraphLinkContext', if (apolloConfig.useResolveInfo && !isSubscription) 'info: GraphQLResolveInfo'];
      final returnDecl = isSubscription ? 'AsyncIterable<$returnTs>' : 'Promise<$returnTs>';
      methods.add('${field.name}(${params.join(', ')}): $returnDecl;');
    }

    for (final mapping in service.serviceMapping) {
      methods.add(_serviceMappingMethod(mapping, importedTypes));
    }

    final imp = _imports(importedTypes);
    final lines = [
      "import { GraphLinkContext } from '../context.js';",
      if (apolloConfig.useResolveInfo) "import { GraphQLResolveInfo } from 'graphql';",
      if (hasUpload) "import type { FileUpload } from '../file-upload.js';",
      if (imp.isNotEmpty) imp,
    ];
    return '${lines.join('\n')}\n\n${_interface(service.token, methods)}';
  }

  String _serviceMappingMethod(GLSchemaMapping mapping, Set<String> importedTypes) {
    final parentName = mapping.type.token;
    _addIfKnown(parentName, importedTypes);
    final fieldTs = tsSerializer.serializeType(mapping.field.type, false);
    _collectType(mapping.field.type, importedTypes);

    if (mapping.isBatch) {
      return '${mapping.key}(items: ${parentName}[]): Promise<Map<${parentName}, ${fieldTs}>>;';
    }
    final nonBatchParams = ['item: ${parentName}', 'context: GraphLinkContext', if (apolloConfig.useResolveInfo) 'info: GraphQLResolveInfo'];
    return '${mapping.key}(${nonBatchParams.join(', ')}): Promise<${fieldTs}>;';
  }

  // ── guards/XxxGuard.ts ────────────────────────────────────────────────────

  String? serializeGuard(GLService service) {
    final importedTypes = <String>{};
    final methods = <String>[];

    for (final field in service.fields) {
      // skip synthetic validate fields generated by the parser
      if (field.getDirectiveByName(glValidate)?.generated == true) continue;
      if (field.getDirectiveByName(glValidate) == null) continue;
      final argList = field.arguments.map((arg) {
        _collectType(arg.type, importedTypes);
        return '${arg.token}: ${tsSerializer.serializeType(arg.type, false)}';
      }).toList();
      final guardParams = [...argList, 'context: GraphLinkContext', if (apolloConfig.useResolveInfo) 'info: GraphQLResolveInfo'];
      methods.add('$glValidateMethodPrefix${field.name.token.firstUp}(${guardParams.join(', ')}): Promise<void>;');
    }

    if (methods.isEmpty) return null;

    final imp = _imports(importedTypes);
    final resolveInfoImport = apolloConfig.useResolveInfo ? "import { GraphQLResolveInfo } from 'graphql';" : '';
    final lines = [
      "import { GraphLinkContext } from '../context.js';",
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
    final fieldTs = tsSerializer.serializeType(mapping.field.type, false);
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

  String serializeResolvers() {
    final services = grammar.services.values.toList();
    final buf = StringBuffer();

    buf.writeln("import { IResolvers } from '@graphql-tools/utils';");
    final graphqlImports = apolloConfig.useResolveInfo ? 'GraphQLError, GraphQLResolveInfo' : 'GraphQLError';
    buf.writeln("import { $graphqlImports } from 'graphql';");
    buf.writeln("import { GraphLinkContext } from '../context.js';");
    if (_hasUploads) {
      buf.writeln("import GraphQLUpload from 'graphql-upload/GraphQLUpload.js';");
    }

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

  bool _hasGuard(GLService service) => service.fields.any(
        (f) => f.getDirectiveByName(glValidate) != null &&
            f.getDirectiveByName(glValidate)?.generated != true,
      );

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
          argTypes: field.arguments.map((a) => a.type).toList(),
        ));
      }
    }
    if (entries.isEmpty) return;

    buf.writeln('    $block: {');
    for (final e in entries) {
      final sVar = e.service.token.firstLow;
      final gVar = _guardName(e.service).firstLow;
      final argsDestructure = e.argNames.isEmpty ? '__' : '{ ${e.argNames.join(', ')} }';

      // resolve upload args before passing to service
      final resolvedArgNames = List<String>.from(e.argNames);
      final uploadAwaitLines = <String>[];
      for (int i = 0; i < e.argTypes.length; i++) {
        if (_isUploadScalar(e.argTypes[i])) {
          final original = e.argNames[i];
          final resolved = '_$original';
          resolvedArgNames[i] = resolved;
          uploadAwaitLines.add(e.argTypes[i] is GLListType
              ? 'const $resolved = await Promise.all($original);'
              : 'const $resolved = await $original;');
        }
      }

      final callArgs = [...resolvedArgNames, 'context', if (apolloConfig.useResolveInfo) 'info'].join(', ');
      final serviceCall = '$sVar.${e.fieldName}($callArgs)';
      final hasValidate = e.service.fields
          .firstWhere((f) => f.name.token == e.fieldName)
          .getDirectiveByName(glValidate) != null;
      final validateCall = hasValidate
          ? 'await $gVar.${glValidateMethodPrefix}${e.fieldName.firstUp}($callArgs);'
          : null;
      final resolverSignature = apolloConfig.useResolveInfo
          ? '(_, $argsDestructure, context, info)'
          : '(_, $argsDestructure, context)';

      buf.writeln('      ${e.fieldName}: async $resolverSignature => {');
      for (final line in uploadAwaitLines) buf.writeln('        $line');
      if (validateCall != null) buf.writeln('        $validateCall');
      buf.writeln('        return $serviceCall;');
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
          argTypes: field.arguments.map((a) => a.type).toList(),
        ));
      }
    }
    if (entries.isEmpty) return;

    buf.writeln('    Subscription: {');
    for (final e in entries) {
      final sVar = e.service.token.firstLow;
      final argsDestructure = e.argNames.isEmpty ? '__' : '{ ${e.argNames.join(', ')} }';
      final callArgs = [...e.argNames, 'context'].join(', ');
      buf.writeln('      ${e.fieldName}: {');
      buf.writeln('        subscribe: (_, $argsDestructure, context) => $sVar.${e.fieldName}($callArgs),');
      buf.writeln('        resolve: (payload: any) => payload,');
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
          buf.writeln('(parent) => ${m.key}Loader.load(parent),');
        } else {
          final mappingCallArgs = apolloConfig.useResolveInfo ? 'parent, context, info' : 'parent, context';
          final mappingResolverArgs = apolloConfig.useResolveInfo ? '(parent, _, context, info)' : '(parent, _, context)';
          buf.writeln('$mappingResolverArgs => $sVar.${m.key}($mappingCallArgs),');
        }
      }
      buf.writeln('    },');
    }
  }

  // ── index.ts ──────────────────────────────────────────────────────────────

  String serializeEntryPoint() {
    final services = grammar.services.values.toList();

    // service + guard imports
    final buf = StringBuffer();
    buf.writeln("import express, { Express, Request, Response } from 'express';");
    buf.writeln("import cors from 'cors';");
    buf.writeln("import { ApolloServer } from '@apollo/server';");
    buf.writeln("import { expressMiddleware } from '@apollo/server/express4';");
    if (_hasSubscriptions) {
      buf.writeln("import { createServer as createHttpServer, Server } from 'http';");
      buf.writeln("import { WebSocketServer } from 'ws';");
      buf.writeln("import { useServer } from 'graphql-ws/lib/use/ws';");
      buf.writeln("import { makeExecutableSchema } from '@graphql-tools/schema';");
      buf.writeln("import { ApolloServerPluginDrainHttpServer } from '@apollo/server/plugin/drainHttpServer';");
    }
    if (_hasUploads) {
      buf.writeln("import graphqlUploadExpress from 'graphql-upload/graphqlUploadExpress.js';");
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

    final middlewareLine = _hasUploads
        ? "app.use('${apolloConfig.graphqlPath}', graphqlUploadExpress(), expressMiddleware(server, {"
        : "app.use('${apolloConfig.graphqlPath}', expressMiddleware(server, {";

    final List<String> createServerBody;
    if (_hasSubscriptions) {
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
      returnType: _hasSubscriptions ? 'Server' : 'Express',
      async: true,
      exported: true,
      statements: createServerBody,
    ));

    return buf.toString();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _isUploadScalar(GLType type) =>
      grammar.uploadScalarNames.contains(type.firstType.token);

  String _tsUploadType(GLType type) =>
      type is GLListType ? 'FileUpload[]' : 'FileUpload';

  bool get _hasUploads =>
      grammar.uploadScalarNames.isNotEmpty &&
      grammar.services.values.any((s) =>
          s.fields.any((f) => f.arguments.any((a) => _isUploadScalar(a.type))));

  bool get _hasSubscriptions => grammar.services.values.any((s) =>
      s.fields.any((f) => s.getTypeByFieldName(f.name.token) == GLQueryType.subscription));

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
  final List<String> argNames;
  final List<GLType> argTypes;
  _RootEntry({required this.service, required this.fieldName, required this.argNames, required this.argTypes});
}

class _MappingEntry {
  final GLSchemaMapping mapping;
  final GLService service;
  _MappingEntry({required this.mapping, required this.service});
}
