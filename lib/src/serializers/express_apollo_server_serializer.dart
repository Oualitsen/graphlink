import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_intercept_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_validation_extension.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_schema_mapping.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/express_apollo_server_constants.dart';
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

  String serializeFileUploadType() => fileUploadType;

  String serializeGraphqlUploadDeclarations() => graphqlUploadDeclarations;

  // ── interfaces/gl-interceptor.ts ─────────────────────────────────────────

  bool get hasInterceptor => grammar.usesInterceptor;

  /// Appends the Apollo-specific `context`/`info` params onto the shared
  /// `runBefore` IR, then serializes normally. The two import lines are
  /// hand-written since `GraphLinkContext`/`GraphQLResolveInfo` aren't schema
  /// tokens the generic import resolver knows about.
  String? serializeInterceptorInterface() {
    if (!hasInterceptor) return null;
    final def = grammar.interfaces[glInterceptorInterfaceName]!;
    _addInterceptorTargetArgs(def);

    final buf = StringBuffer();
    buf.writeln("import { GraphLinkContext } from '../context.js';");
    if (apolloConfig.useResolveInfo) {
      buf.writeln("import { GraphQLResolveInfo } from 'graphql';");
    }
    buf.write(tsSerializer.serializeTypeDefinition(def));
    return buf.toString();
  }

  void _addInterceptorTargetArgs(GLInterfaceDefinition def) {
    final runBefore = def.fields.firstWhere((f) => f.name.token == glInterceptorRunBeforeMethod);
    if (runBefore.arguments.any((a) => a.token == 'context')) return;
    runBefore.addArgument(
        GLArgumentDefinition('context'.toToken(), GLType('GraphLinkContext'.toToken(), true), []));
    if (apolloConfig.useResolveInfo) {
      runBefore.addArgument(
          GLArgumentDefinition('info'.toToken(), GLType('GraphQLResolveInfo'.toToken(), true), []));
    }
  }

  // ── context.ts ────────────────────────────────────────────────────────────

  @override
  String serializeContext() {
    final batch = _batchMappings();
    if (batch.isEmpty) return graphLinkContextInterface;

    final typeNames = <String>{};
    for (final e in batch) {
      _addIfKnown(e.mapping.type.token, typeNames);
      _collectType(e.mapping.field.type, typeNames);
    }
    // context.ts sits one level above types/ etc., so rewrite the shared '../'
    // import prefix to './'.
    final typeImports = _imports(typeNames).replaceAll("from '../", "from './");

    final loaderFields = [
      for (final e in batch) '${e.mapping.key}: ${_loaderFieldType(e.mapping)};',
    ];

    final buf = StringBuffer();
    buf.writeln("import DataLoader from 'dataloader';");
    if (typeImports.isNotEmpty) buf.writeln(typeImports);
    buf.writeln();
    buf.writeln(_cg.createInterface(interfaceName: 'GraphLinkLoaders', fields: loaderFields));
    buf.writeln();
    buf.write(graphLinkContextInterface);
    return buf.toString();
  }

  List<_MappingEntry> _batchMappings() => [
        for (final service in grammar.services.values)
          for (final m in service.mappings.where((m) => m.isBatch))
            _MappingEntry(mapping: m, service: service),
      ];

  /// [mapping]'s real declared arguments, excluding the synthetic parent
  /// (`value`) argument every mapping carries.
  List<GLArgumentDefinition> _realMappingArgs(GLSchemaMapping mapping) =>
      mapping.field.arguments.where((a) => !a.skipOnGraphqlSerialization).toList();

  /// The `GraphLinkLoaders` field type for a batch [mapping] — a plain
  /// `DataLoader` when zero-arg, or a memoized-loader-getter function when
  /// the field carries real arguments (see `_loaderFactory`).
  String _loaderFieldType(GLSchemaMapping mapping) {
    final dataLoaderType =
        'DataLoader<${tsSerializer.resolveCodeName(mapping.type.token)}, ${tsSerializer.serializeType(mapping.field.type)}>';
    final realArgs = _realMappingArgs(mapping);
    if (realArgs.isEmpty) return dataLoaderType;
    final params = realArgs.map((a) => '${a.codeName}: ${tsSerializer.serializeType(a.type)}').join(', ');
    return '($params) => $dataLoaderType';
  }

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

    // A batch mapping resolves many parents in one call, so it has no single
    // GraphQLResolveInfo — exclude `info` from its signature (as subscriptions do).
    final batchKeys =
        service.mappings.where((m) => m.isBatch).map((m) => m.key).toSet();

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
      final isBatch = batchKeys.contains(field.name.token);
      final needsInfo = apolloConfig.useResolveInfo && !isSubscription && !isBatch;
      final params = [
        ...argList,
        if (_injectsContext(field)) 'context: GraphLinkContext',
        if (needsInfo) 'info: GraphQLResolveInfo',
      ];
      final returnDecl = isSubscription ? 'AsyncIterable<$returnTs>' : 'Promise<$returnTs>';
      methods.add('${field.name}(${params.join(', ')}): $returnDecl;');
    }

    final needsResolveInfoImport = apolloConfig.useResolveInfo &&
        service.fields.any((f) =>
            f.getDirectiveByName(glValidate)?.generated != true &&
            service.getTypeByFieldName(f.name.token) != GLQueryType.subscription &&
            !batchKeys.contains(f.name.token));
    final needsContextImport = service.fields.any(_injectsContext);

    final imp = _imports(importedTypes);
    final lines = [
      if (needsContextImport) "import { GraphLinkContext } from '../context.js';",
      if (needsResolveInfoImport) "import { GraphQLResolveInfo } from 'graphql';",
      if (hasUpload) "import type { FileUpload } from '../file-upload.js';",
      if (imp.isNotEmpty) imp,
    ];
    return '${lines.join('\n')}\n\n${_cg.createInterface(interfaceName: service.token, fields: methods)}';
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
    return '${lines.join('\n')}\n\n${_cg.createInterface(interfaceName: _guardName(service), fields: methods)}';
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
    if (batchMappings.any((m) => _injectsContext(m.field))) {
      buf.writeln("import { GraphLinkContext } from '../context.js';");
    }
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
    final parentName = tsSerializer.resolveCodeName(mapping.type.token);
    final fieldTs = tsSerializer.serializeType(mapping.field.type);
    final factoryName = 'create${mapping.key.firstUp}Loader';
    final serviceVar = serviceName.firstLow;
    final realArgs = _realMappingArgs(mapping);
    final argCodeNames = realArgs.map((a) => a.codeName).toList();

    final String mapCallback;
    if (mapping.field.type.nullable) {
      // A nullable batch field legitimately resolves to null when the service
      // has no entry for a parent.
      mapCallback = 'v => map.get(v) ?? null';
    } else {
      // A non-nullable field requires a value per key. Returning an Error (not
      // throwing) rejects only this key's promise, not the whole batch. Keep the
      // client-facing message generic and log the full parent object server-side.
      final callbackBody = _cg.block([
        'const r = map.get(v);',
        _cg.ifStatement(
          condition: 'r == null',
          ifBlockStatements: [
            "console.error('${mapping.key}: no result for', v);",
            "return new Error('${mapping.key} resolution failed');",
          ],
        ),
        'return r;',
      ]);
      mapCallback = 'v => $callbackBody';
    }
    final ctx = _injectsContext(mapping.field);
    final serviceCallArgs = [
      ...argCodeNames,
      '[...items]',
      if (ctx) 'context',
    ].join(', ');
    final loaderBody = _cg.block([
      'const map = await $serviceVar.${mapping.key}($serviceCallArgs);',
      'return items.map($mapCallback);',
    ]);
    final newLoaderExpr = 'new DataLoader<$parentName, $fieldTs>(async (items) => $loaderBody)';
    final factoryArgs = ['$serviceVar: $serviceName', if (ctx) 'context: GraphLinkContext'];

    if (realArgs.isEmpty) {
      return '${_cg.createFunction(
        functionName: factoryName,
        arguments: factoryArgs,
        exported: true,
        statements: ['return $newLoaderExpr;'],
      )}\n';
    }

    // A single DataLoader only batches calls sharing the same argument value,
    // so return a per-arguments memoized getter instead of one instance.
    final params = realArgs.map((a) => '${a.codeName}: ${tsSerializer.serializeType(a.type)}').join(', ');
    return '${_cg.createFunction(
      functionName: factoryName,
      arguments: factoryArgs,
      exported: true,
      statements: [
        'const cache = new Map<string, DataLoader<$parentName, $fieldTs>>();',
        'return ($params) => ${_cg.block([
          'const key = JSON.stringify([${argCodeNames.join(', ')}]);',
          'let loader = cache.get(key);',
          _cg.ifStatement(condition: '!loader', ifBlockStatements: [
            'loader = $newLoaderExpr;',
            'cache.set(key, loader);',
          ]),
          'return loader;',
        ])};',
      ],
    )}\n';
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
        _collectType(field.type, resolverTypes);
      }
      for (final mapping in service.mappings) {
        _collectType(mapping.field.type, resolverTypes);
      }
    }
    final resolverTypeImports = _imports(resolverTypes);

    final imports = <String>[
      "import { IResolvers } from '@graphql-tools/utils';",
      "import { ${apolloConfig.useResolveInfo ? 'GraphQLError, GraphQLResolveInfo' : 'GraphQLError'} } from 'graphql';",
      _hasBatchLoaders
          ? "import { GraphLinkContext, GraphLinkLoaders } from '../context.js';"
          : "import { GraphLinkContext } from '../context.js';",
      if (hasUploads) "import GraphQLUpload from 'graphql-upload/GraphQLUpload.mjs';",
      if (resolverTypeImports.isNotEmpty) resolverTypeImports,
      // service + guard imports (guard only if service has @glValidate fields)
      for (final service in services) ...[
        "import { ${service.token} } from '../services/${_kebabJs(service.token)}';",
        if (_hasGuard(service)) "import { ${_guardName(service)} } from '../guards/${_kebabJs(_guardName(service))}';",
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
        if (_hasGuard(service)) '${_guardName(service).firstLow}: ${_guardName(service)}',
      if (hasInterceptor)
        'interceptor: ${grammar.interfaces[glInterceptorInterfaceName]!.codeName}',
    ];

    final query = _serializeRootBlock(services, GLQueryType.query, 'Query');
    final mutation = _serializeRootBlock(services, GLQueryType.mutation, 'Mutation');
    final subscription = _serializeSubscriptionBlock(services);
    final resolverMap = [
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

  /// The `tag` call-site argument for `runBefore` — a single-element list, or
  /// empty when no `GlInterceptorTag` enum was generated (no tag param exists
  /// to pass).
  List<String> _interceptorTagCallArg(GLField field, [GLQueryType? type]) {
    final tagEnum = grammar.enums[glInterceptorTagEnumName];
    if (tagEnum == null) return const [];
    final tag = grammar.interceptTag(field, type);
    if (tag == null) return const ['null'];
    final member = tagEnum.values.firstWhere((v) => v.token == tag).codeName;
    return ['${tagEnum.codeName}.$member'];
  }

  /// `runBefore(...)` call inserted as the first statement of an intercepted
  /// resolver, before any upload/validation/service call.
  String? _runBeforeStatement(_RootEntry e) {
    if (!e.intercepted) return null;
    final callArgs = [
      ..._interceptorTagCallArg(e.field, e.queryType),
      '"${e.fieldName}"',
      '[${e.argCodeNames.join(', ')}]',
      'context',
      // `info` is a required param, so a resolver that doesn't destructure it
      // (e.g. a subscription) must still pass literal `null` positionally.
      if (apolloConfig.useResolveInfo) (e.needsInfo ? 'info' : 'null'),
    ].join(', ');
    return 'await interceptor.runBefore($callArgs);';
  }

  bool _hasGuard(GLService service) => service.fields.any(fieldHasValidation);

  bool get _hasBatchLoaders =>
      grammar.services.values.any((s) => s.mappings.any((m) => m.isBatch));

  bool get _anyBatchInjectsContext =>
      _batchMappings().any((e) => _injectsContext(e.mapping.field));

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

  /// Builds a resolver-map entry `fieldName: <value>,`. With [signature],
  /// [bodyStatements] become an `async (…) => { … }` function body; without it,
  /// they become an object literal (e.g. a subscription's `{ subscribe, resolve }`).
  String _entry(String fieldName, List<String> bodyStatements, {String? signature}) {
    final block = _cg.block(bodyStatements);
    final value = signature != null ? 'async $signature => $block' : block;
    return '$fieldName: $value,';
  }

  String? _serializeRootBlock(List<GLService> services, GLQueryType type, String blockName) {
    final entries = <_RootEntry>[];
    for (final service in services) {
      for (final field in service.fields) {
        if (field.getDirectiveByName(glValidate)?.generated == true) continue;
        if (service.getTypeByFieldName(field.name.token) != type) continue;
        final intercepted = grammar.isIntercepted(field, type);
        entries.add(_RootEntry(
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
          contextInjected: _injectsContext(field) || intercepted,
          intercepted: intercepted,
        ));
      }
    }
    if (entries.isEmpty) return null;

    final fieldEntries = <String>[];
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
    final entries = <_RootEntry>[];
    for (final service in services) {
      for (final field in service.fields) {
        if (service.getTypeByFieldName(field.name.token) != GLQueryType.subscription) continue;
        final intercepted = grammar.isIntercepted(field, GLQueryType.subscription);
        entries.add(_RootEntry(
          service: service,
          field: field,
          queryType: GLQueryType.subscription,
          fieldName: field.name.token,
          argNames: field.arguments.map((a) => a.token).toList(),
          argCodeNames: field.arguments.map((a) => a.codeName).toList(),
          argTypes: field.arguments.map((a) => a.type).toList(),
          returnType: field.type,
          needsInfo: false,
          contextInjected: _injectsContext(field) || intercepted,
          intercepted: intercepted,
        ));
      }
    }
    if (entries.isEmpty) return null;

    final fieldEntries = <String>[];
    for (final e in entries) {
      final sVar = e.service.token.firstLow;
      final argsDestructure =
          _argsDestructure(e.argNames, e.argCodeNames, '__');
      final callArgs = [...e.argCodeNames, if (e.contextInjected) 'context'].join(', ');
      final subscribeSignature = _resolverSignature('_', argsDestructure, e.contextInjected, false);
      final toJsonExpr = tsSerializer.callToJson('payload', e.returnType);
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
    final byType = <String, List<_MappingEntry>>{};
    for (final service in services) {
      for (final mapping in service.mappings) {
        byType.putIfAbsent(mapping.type.token, () => []);
        byType[mapping.type.token]!.add(_MappingEntry(mapping: mapping, service: service));
      }
    }

    return [
      for (final typeName in byType.keys)
        '$typeName: ${_cg.block([
          for (final entry in byType[typeName]!)
            '${entry.mapping.field.name}: ${_mappingResolver(entry.mapping, entry.service.token.firstLow)},',
        ])}',
    ];
  }

  /// `runBefore(...)` call for an intercepted mapping field, inserted once
  /// per resolved parent (not inside the DataLoader's batch function, which
  /// only sees an already-collapsed array with no single caller to attribute
  /// the check to).
  String _mappingRunBeforeStatement(GLSchemaMapping m) {
    final argCodeNames = _realMappingArgs(m).map((a) => a.codeName).toList();
    final callArgs = [
      ..._interceptorTagCallArg(m.field),
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
      final realArgs = _realMappingArgs(m);
      final argNames = realArgs.map((a) => a.token).toList();
      final argCodeNames = realArgs.map((a) => a.codeName).toList();
      final argsDestructure = _argsDestructure(argNames, argCodeNames, '_');
      final loaderAccess = realArgs.isEmpty
          ? 'context.loaders.${m.key}'
          : 'context.loaders.${m.key}(${argCodeNames.join(', ')})';
      final toJsonExpr = tsSerializer.callToJson('_r', m.field.type);
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
    final argsDestructure = _argsDestructure(argNames, argCodeNames, '_');
    final needsInfo = apolloConfig.useResolveInfo;
    final ctx = _injectsContext(m.field) || intercepted;
    final mappingCallArgs = [
      ...m.field.arguments
          .map((a) => a.skipOnGraphqlSerialization ? 'parent' : a.codeName),
      if (ctx) 'context',
      if (needsInfo) 'info',
    ].join(', ');
    final mappingResolverArgs = _resolverSignature('parent', argsDestructure, ctx, needsInfo);
    final toJsonExpr = tsSerializer.callToJson('_r', m.field.type);
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
    if (hasInterceptor) {
      final interceptorDef = grammar.interfaces[glInterceptorInterfaceName]!;
      buf.writeln(
          "import { ${interceptorDef.codeName} } from './interfaces/${tsSerializer.getFileNameFor(interceptorDef).replaceAll('.ts', '.js')}';");
    }
    for (final service in services) {
      buf.writeln("import { ${service.token} } from './services/${_kebabJs(service.token)}';");
      if (_hasGuard(service)) {
        final guard = _guardName(service);
        buf.writeln("import { $guard } from './guards/${_kebabJs(guard)}';");
      }
    }
    for (final service in services) {
      for (final m in service.mappings.where((m) => m.isBatch)) {
        buf.writeln("import { create${m.key.firstUp}Loader } from './loaders/${_loaderFileJs(service)}';");
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
    if (hasInterceptor) {
      serviceFields.add(
          'interceptor?: ${grammar.interfaces[glInterceptorInterfaceName]!.codeName};');
    }
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
          '${m.key}: create${m.key.firstUp}Loader(services.${service.token.firstLow}${_injectsContext(m.field) ? ', context' : ''}),',
    ];
    if (loaderFields.isNotEmpty) {
      buf.writeln(_cg.createFunction(
        functionName: 'createLoaders',
        arguments: [
          'services: GraphLinkServices',
          if (_anyBatchInjectsContext) 'context: GraphLinkContext',
        ],
        statements: ['return ${_cg.block(loaderFields)};'],
      ));
      buf.writeln();
    }

    // buildResolvers call: services first, guards last (mirrors param order)
    final serviceArgs = services.map((s) => 'services.${s.token.firstLow}').join(', ');
    final guardArgs = services
        .where((s) => _hasGuard(s))
        .map((s) => 'services.${_guardName(s).firstLow}')
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
        'const cleanup = useServer({ schema${_wsContextOption()} }, wsServer as any);',
        '',
        'const server = new ApolloServer<GraphLinkContext>(${_cg.block([
          'schema,',
          // graphql-upload sends multipart/form-data, which Apollo's CSRF prevention
          // blocks by default unless the client sends a preflight-style header.
          if (hasUploads) 'csrfPrevention: false,',
          'plugins: $pluginsArray,',
        ])});',
        '',
        'await server.start();',
        _registerMiddleware(),
        'return httpServer;',
      ];
    } else {
      createServerBody = [
        if (interceptorGuard != null) interceptorGuard,
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
        _registerMiddleware(),
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

  /// The `context` option for the WS (`useServer`) transport. Subscriptions have
  /// no `contextFactory` (no req/res), so the WS context carries only per-request
  /// loaders — built after the context object exists when they need to forward it.
  String _wsContextOption() {
    if (!_hasBatchLoaders) return '';
    if (_anyBatchInjectsContext) {
      final body = _cg.block([
        'const context = {} as GraphLinkContext;',
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
    if (_anyBatchInjectsContext) {
      // Loaders forward the request context to their batch service methods, so
      // the context object must exist before the loaders are built.
      final body = _cg.block([
        'const context: GraphLinkContext = services.contextFactory ? await services.contextFactory(req, res) : {} as GraphLinkContext;',
        'context.loaders = createLoaders(services, context);',
        'return context;',
      ]);
      contextCallback = 'context: async ({ req, res }) => $body,';
    } else if (_hasBatchLoaders) {
      final body = _cg.block([
        'const base = services.contextFactory ? await services.contextFactory(req, res) : {} as GraphLinkContext;',
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
    return "app.use('${apolloConfig.graphqlPath}', ${uploadHandler}expressMiddleware(server, $options));";
  }

  String _tsUploadType(GLType type) =>
      type is GLListType ? 'FileUpload[]' : 'FileUpload';

  String _guardName(GLService service) =>
      '${service.token.replaceFirst('Service', '')}Guard';

  /// kebab-case filename with .js extension (for import statements)
  String _kebabJs(String typeName) => '${typeName.toKebabCase()}.js';

  String _loaderFileJs(GLService service) =>
      '${service.token.replaceFirst('Service', '').toKebabCase()}-loaders.js';

  /// Resolves each collected wire token to its definition and delegates to the
  /// TypeScript serializer's import logic, which routes interfaces/unions to
  /// `../interfaces/`, types to `../types/`, and follows `@glSkipOnServer(mapTo:)`
  /// to the mapped target (e.g. `ArticleWithCount` → `Article`). Deduplicated so
  /// several mapped-away types collapsing onto one target import once.
  String _imports(Set<String> typeNames) {
    final seen = <String>{};
    final lines = <String>[];
    for (final name in typeNames) {
      final token = grammar.types[name] ??
          grammar.interfaces[name] ??
          grammar.inputs[name] ??
          grammar.enums[name];
      if (token == null) continue;
      final line = tsSerializer.serializeImportToken(token);
      if (line.isEmpty || !seen.add(line)) continue;
      lines.add(line);
    }
    return lines.join('\n');
  }

  void _collectType(GLType type, Set<String> out) {
    if (type is GLListType) {
      _collectType(type.inlineType, out);
    } else if (type is GLMapType) {
      _collectType(type.keyType, out);
      _collectType(type.valueType, out);
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
  _RootEntry({
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

class _MappingEntry {
  final GLSchemaMapping mapping;
  final GLService service;
  _MappingEntry({required this.mapping, required this.service});
}
