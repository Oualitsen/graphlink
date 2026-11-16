import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_schema_mapping.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_intercept_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_response_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_server_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_source_extension.dart';
import 'package:graphlink/src/python_code_gen_utils.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/python/fastapi_ariadne_rest_serializer.dart';
import 'package:graphlink/src/serializers/python/fastapi_ariadne_server_constants.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:graphlink/src/serializers/server_serializer.dart';

class FastapiAriadneServerSerializer extends ServerSerializer with ServerSerializerUtils {
  final PythonSerializer py;
  final FastapiAriadneServerConfig config;
  final _cg = PythonCodeGenUtils();

  FastapiAriadneServerSerializer(super.grammar, this.py, this.config);

  late final FastapiAriadneRestSerializer rest = FastapiAriadneRestSerializer(grammar, py, config);

  bool get hasRest => rest.hasRest;

  bool get hasInterceptor => grammar.usesInterceptor;

  bool get hasRestUploads => rest.hasUploads;

  bool get hasRestDownloads => rest.hasDownloads;

  // ── naming ────────────────────────────────────────────────────────────────

  String methodName(String wire) {
    final name = wire.toSnakeCaseWords();
    return _pythonKeywords.contains(name) ? '${name}_' : name;
  }

  String moduleName(String typeName) => typeName.toSnakeCaseWords();

  String serviceVar(GLService service) => moduleName(service.token);

  String guardName(GLService service) => '${service.token.replaceFirst('Service', '')}Guard';

  String guardVar(GLService service) => moduleName(guardName(service));

  String loaderFileName(GLService service) => '${moduleName(service.token.replaceFirst('Service', ''))}_loaders';

  String serviceFileName(GLService service) => moduleName(service.token);

  String guardFileName(GLService service) => moduleName(guardName(service));

  String get interceptorClassName => grammar.interfaces[glInterceptorInterfaceName]!.codeName;

  String get interceptorFileName => moduleName(interceptorClassName);

  bool injectsContext(GLField field) => config.injectContext || field.hasDirective(glInjectContext);

  bool _guardPassesInfo(GLField field) => config.useResolveInfo && !grammar.isRestField(field);

  bool _passesInfo(GLService service, GLField field) {
    if (!config.useResolveInfo || grammar.isRestField(field)) return false;
    if (service.getTypeByFieldName(field.name.token) == GLQueryType.subscription) return false;
    return !service.mappings.any((m) => m.isBatch && m.key == field.name.token);
  }

  bool _hasGuard(GLService service) => service.fields.any(fieldHasValidation);

  bool _carriesSource(String typeName) => grammar.sourceTypeNames.contains(typeName);

  List<GLArgumentDefinition> _realMappingArgs(GLSchemaMapping mapping) =>
      mapping.field.arguments.where((a) => !a.skipOnGraphqlSerialization).toList();

  // ── static support files ──────────────────────────────────────────────────

  String serializeSourceSupport() => fastapiSourceSupport;

  String serializeLoaderRuntime() => fastapiLoaderRuntime;

  String serializeGuards() => fastapiGuards;

  String serializeWsHandler() => fastapiWsHandler;

  String serializeFileUpload() => fastapiFileUpload;

  @override
  String serializeContext() => fastapiContextBase;

  @override
  String serializeTypeDefs() {
    final schema = GLGraphqlSerializer(grammar).generateSchema();
    final escaped = schema.replaceAll(r'\', r'\\').replaceAll('"""', r'\"\"\"');
    return 'TYPE_DEFS = """\n$escaped"""\n';
  }

  // ── interceptor Protocol ──────────────────────────────────────────────────

  String? serializeInterceptorInterface() {
    if (!hasInterceptor) return null;
    final tagEnum = grammar.enums[glInterceptorTagEnumName];
    final imports = [
      'from __future__ import annotations',
      '',
      'from typing import Any, List, Optional, Protocol',
      '',
      'from ..context import GraphLinkContext',
      if (config.useResolveInfo) 'from graphql import GraphQLResolveInfo',
      if (tagEnum != null) 'from ..enums.${py.moduleNameFor(tagEnum)} import ${tagEnum.codeName}',
    ];
    final runBefore = _cg.createMethod(
      async: true,
      methodName: 'run_before',
      arguments: [
        'self',
        if (tagEnum != null) 'tag: Optional[${tagEnum.codeName}]',
        'operation: str',
        'args: List[Any]',
        'context: GraphLinkContext',
        if (config.useResolveInfo) 'info: Optional[GraphQLResolveInfo]',
      ],
      returnType: 'None',
      statements: ['...'],
    );
    return '${imports.join('\n')}\n\n\n${_cg.createClass(className: interceptorClassName, baseClassNames: ['Protocol'], statements: [runBefore])}\n';
  }

  // ── services/<service>.py ─────────────────────────────────────────────────

  @override
  String serializeService(GLService service) {
    final types = <String>{};
    final methods = <String>[];
    var hasUpload = false;
    var hasDownload = false;

    for (final field in service.fields) {
      if (field.getDirectiveByName(glValidate)?.generated == true) continue;
      final params = <String>['self'];
      for (final arg in field.arguments) {
        if (isUploadScalar(arg.type)) {
          hasUpload = true;
          params.add('${arg.codeName}: ${_uploadType(arg.type)}');
        } else {
          _collectType(arg.type, types);
          params.add('${arg.codeName}: ${py.serializeType(arg.type)}');
        }
      }
      final isDownload = grammar.downloadScalarNames.contains(field.type.firstType.token);
      if (isDownload) hasDownload = true;
      _collectType(field.type, types);
      final returnType = grammar.voidScalarNames.contains(field.type.firstType.token)
          ? 'None'
          : isDownload
              ? (field.type.nullable ? 'Optional[GraphLinkDownload]' : 'GraphLinkDownload')
              : py.serializeType(field.type);
      if (injectsContext(field)) params.add('context: GraphLinkContext');
      final isSubscription = service.getTypeByFieldName(field.name.token) == GLQueryType.subscription;
      if (_passesInfo(service, field)) params.add('info: GraphQLResolveInfo');
      methods.add(_cg.createMethod(
        async: !isSubscription,
        methodName: methodName(field.name.token),
        arguments: params,
        returnType: isSubscription ? 'AsyncIterator[$returnType]' : returnType,
      ));
    }

    final body = _cg.createClass(
      className: service.token,
      baseClassNames: ['Protocol'],
      statements: _spaced(methods),
    );
    return _module(
      body: body,
      imports: [
        if (service.fields.any(injectsContext)) 'from ..context import GraphLinkContext',
        if (service.fields.any((f) => _passesInfo(service, f))) 'from graphql import GraphQLResolveInfo',
        if (hasUpload) 'from ..file_upload import FileUpload',
        if (hasDownload) 'from ..rest.download import GraphLinkDownload',
        ..._importLines(types),
      ],
    );
  }

  // ── guards/<guard>.py ─────────────────────────────────────────────────────

  @override
  String? serializeGuard(GLService service) {
    final types = <String>{};
    final methods = <String>[];
    for (final field in service.fields) {
      if (!fieldHasValidation(field)) continue;
      final params = <String>['self'];
      for (final arg in field.arguments) {
        _collectType(arg.type, types);
        params.add('${arg.codeName}: ${isUploadScalar(arg.type) ? _uploadType(arg.type) : py.serializeType(arg.type)}');
      }
      if (injectsContext(field)) params.add('context: GraphLinkContext');
      if (_guardPassesInfo(field)) params.add('info: GraphQLResolveInfo');
      methods.add(_cg.createMethod(
        async: true,
        methodName: methodName(GLService.getValidationMethodName(field.name.token)),
        arguments: params,
        returnType: 'None',
      ));
    }
    if (methods.isEmpty) return null;
    final guardedFields = service.fields.where(fieldHasValidation);
    return _module(
      body: _cg.createClass(
        className: guardName(service),
        baseClassNames: ['Protocol'],
        statements: _spaced(methods),
      ),
      imports: [
        if (guardedFields.any(injectsContext)) 'from ..context import GraphLinkContext',
        if (guardedFields.any(_guardPassesInfo)) 'from graphql import GraphQLResolveInfo',
        if (guardedFields.any((f) => f.arguments.any((a) => isUploadScalar(a.type)))) 'from ..file_upload import FileUpload',
        ..._importLines(types),
      ],
    );
  }

  // ── loaders/<service>_loaders.py ──────────────────────────────────────────

  String? serializeLoader(GLService service) {
    final batchMappings = service.mappings.where((m) => m.isBatch).toList();
    if (batchMappings.isEmpty) return null;
    final types = <String>{};
    for (final m in batchMappings) {
      _addIfKnown(m.type.token, types);
      _collectType(m.field.type, types);
    }
    final needsContext = batchMappings.any((m) => injectsContext(m.field));
    final needsSource = batchMappings.any((m) => _carriesSource(m.type.token));
    return _module(
      body: batchMappings.map((m) => _loaderFactory(m, service)).join('\n\n\n'),
      imports: [
        'from ..${fastapiRuntimeDir}.graph_link_loader import GraphLinkLoader',
        if (needsContext) 'from ..context import GraphLinkContext',
        if (needsSource) 'from ..source import source_of',
        'from ..services.${serviceFileName(service)} import ${service.token}',
        ..._importLines(types),
      ],
    );
  }

  String _loaderFactory(GLSchemaMapping mapping, GLService service) {
    final realArgs = _realMappingArgs(mapping);
    final argCodeNames = realArgs.map((a) => a.codeName).toList();
    final ctx = injectsContext(mapping.field);
    final sourced = _carriesSource(mapping.type.token);
    final svc = serviceVar(service);
    final callArgs = [
      ...argCodeNames,
      sourced ? '[source_of(item) for item in items]' : 'list(items)',
      if (ctx) 'context',
    ].join(', ');
    final lookup = sourced ? 'mapping.get(source_of(item))' : 'mapping.get(item)';

    final List<String> collect;
    if (mapping.field.type.nullable) {
      collect = ['return [$lookup for item in items]'];
    } else {
      collect = [
        'results: List[Any] = []',
        _cg.forEachLoop(
          variable: 'item',
          iterable: 'items',
          statements: [
            _cg.constDecl('value', lookup),
            _cg.ifStatement(
              condition: 'value is None',
              ifBlockStatements: [
                'print("${mapping.key}: no result for", item)',
                'results.append(Exception("${mapping.key} resolution failed"))',
              ],
              elseBlockStatements: ['results.append(value)'],
            ),
          ],
        ),
        'return results',
      ];
    }
    final loadBatch = _cg.createMethod(
      async: true,
      methodName: 'load_batch',
      arguments: ['items: List[Any]'],
      returnType: 'List[Any]',
      statements: [
        _cg.constDecl('mapping', 'await $svc.${methodName(mapping.key)}($callArgs)'),
        ...collect,
      ],
    );
    final factoryParams = ['$svc: ${service.token}', if (ctx) 'context: GraphLinkContext'];
    final factoryName = 'create_${methodName(mapping.key)}_loader';
    if (realArgs.isEmpty) {
      return _cg.createMethod(
        methodName: factoryName,
        arguments: factoryParams,
        returnType: 'GraphLinkLoader',
        statements: [loadBatch, 'return GraphLinkLoader(load_batch)'],
      );
    }
    final params = realArgs.map((a) => '${a.codeName}: ${py.serializeType(a.type)}').join(', ');
    final argsKey = argCodeNames.length == 1 ? '[${argCodeNames.first}]' : '[${argCodeNames.join(', ')}]';
    final getter = _cg.createMethod(
      methodName: 'loader_for',
      arguments: [params],
      returnType: 'GraphLinkLoader',
      statements: [
        _cg.constDecl('key', 'repr($argsKey)'),
        _cg.constDecl('loader', 'cache.get(key)'),
        _cg.ifStatement(condition: 'loader is None', ifBlockStatements: [
          loadBatch,
          'loader = GraphLinkLoader(load_batch)',
          'cache[key] = loader',
        ]),
        'return loader',
      ],
    );
    return _cg.createMethod(
      methodName: factoryName,
      arguments: factoryParams,
      statements: ['cache: Dict[str, GraphLinkLoader] = {}', getter, 'return loader_for'],
    );
  }

  // ── resolvers.py ──────────────────────────────────────────────────────────

  @override
  List<String> serializeResolvers() => [_serializeResolvers()];

  String _serializeResolvers() {
    final services = grammar.services.values.toList();
    final types = <String>{};
    for (final service in services) {
      for (final field in service.fields) {
        _collectType(field.type, types);
        for (final arg in field.arguments) {
          _collectType(arg.type, types);
        }
      }
      for (final mapping in service.mappings) {
        _collectType(mapping.field.type, types);
      }
    }

    final params = <String>[
      for (final service in services) '${serviceVar(service)}: ${service.token}',
      for (final service in services)
        if (_hasGuard(service)) '${guardVar(service)}: ${guardName(service)}',
      if (hasInterceptor) 'interceptor: Optional[$interceptorClassName] = None',
    ];

    final statements = <String>[];
    final bindings = <String>[];
    void addRoot(String variable, String constructor, List<String> resolvers) {
      if (resolvers.isEmpty) return;
      statements.add('$variable = $constructor()');
      statements.addAll(resolvers);
      bindings.add(variable);
    }

    addRoot('query', 'QueryType', _serializeRoot(services, GLQueryType.query, 'query'));
    addRoot('mutation', 'MutationType', _serializeRoot(services, GLQueryType.mutation, 'mutation'));
    addRoot('subscription', 'SubscriptionType', _serializeSubscriptions(services));
    final typeMappings = _serializeTypeMappings(services);
    statements.addAll(typeMappings.statements);
    bindings.addAll(typeMappings.bindings);
    statements.add('return make_executable_schema(TYPE_DEFS, ${bindings.join(', ')})');

    final buildSchema = _cg.createMethod(
      methodName: 'build_schema',
      arguments: params,
      returnType: 'GraphQLSchema',
      statements: statements,
    );

    final imports = <String>[
      'from __future__ import annotations',
      '',
      'from typing import Any, Dict, List, Optional',
      '',
      'from ariadne import MutationType, ObjectType, QueryType, SubscriptionType, make_executable_schema',
      'from graphql import GraphQLError, GraphQLSchema',
      '',
      'from .context import GraphLinkContext',
      if (grammar.carriesSources) 'from .source import attach_source, source_of',
      if (hasUploads) 'from .file_upload import to_file_upload',
      'from .type_defs import TYPE_DEFS',
      ..._importLines(types, root: true),
      for (final service in services) ...[
        'from .services.${serviceFileName(service)} import ${service.token}',
        if (_hasGuard(service)) 'from .guards.${guardFileName(service)} import ${guardName(service)}',
      ],
      if (hasInterceptor) ...[
        'from .interfaces.$interceptorFileName import $interceptorClassName',
        if (grammar.enums.containsKey(glInterceptorTagEnumName))
          'from .enums.${py.moduleNameFor(grammar.enums[glInterceptorTagEnumName]!)} import ${grammar.enums[glInterceptorTagEnumName]!.codeName}',
      ],
    ];
    return '${imports.join('\n')}\n\n\n$buildSchema\n';
  }

  List<String> _interceptorTagCallArg(GLField field, [GLQueryType? type]) {
    final tagEnum = grammar.enums[glInterceptorTagEnumName];
    if (tagEnum == null) return const [];
    final tag = grammar.interceptTag(field, type);
    if (tag == null) return const ['None'];
    final member = tagEnum.values.firstWhere((v) => v.token == tag).codeName;
    return ['${tagEnum.codeName}.$member'];
  }

  String _runBefore(GLField field, GLQueryType? type, String operation, List<String> args, {bool info = false}) {
    final callArgs = [
      ..._interceptorTagCallArg(field, type),
      py.pythonStringLiteral(operation),
      '[${args.join(', ')}]',
      'context',
      if (config.useResolveInfo) info ? 'info' : 'None',
    ].join(', ');
    return 'await interceptor.run_before($callArgs)';
  }

  String _argAccess(String wire) => 'args.get(${py.pythonStringLiteral(wire)})';

  List<String> _decodeArgs(GLField field) => _decodeRealArgs(field.arguments);

  String _decodeArg(GLArgumentDefinition arg) {
    final access = _argAccess(arg.token);
    if (!isUploadScalar(arg.type)) return py.fromJsonExpr(arg.type, access);
    if (arg.type is! GLListType) return 'to_file_upload($access)';
    final list = _cg.listComprehension(expression: 'to_file_upload(e0)', variable: 'e0', iterable: access);
    return arg.type.nullable ? _cg.nullSafe(access, list, true) : list;
  }

  List<String> _serializeRoot(List<GLService> services, GLQueryType type, String binding) {
    final result = <String>[];
    for (final service in services) {
      for (final field in service.fields) {
        if (field.getDirectiveByName(glValidate)?.generated == true) continue;
        if (grammar.isRestField(field)) continue;
        if (service.getTypeByFieldName(field.name.token) != type) continue;
        result.add(_rootResolver(service, field, type, binding));
      }
    }
    return result;
  }

  String _rootResolver(GLService service, GLField field, GLQueryType type, String binding) {
    final intercepted = grammar.isIntercepted(field, type);
    final ctx = injectsContext(field) || intercepted;
    final argNames = field.arguments.map((a) => a.codeName).toList();
    final callArgs = [...argNames, if (injectsContext(field)) 'context', if (_passesInfo(service, field)) 'info'].join(', ');
    final guardArgs = [...argNames, if (injectsContext(field)) 'context', if (_guardPassesInfo(field)) 'info'].join(', ');
    final method = methodName(field.name.token);
    final call = '${serviceVar(service)}.$method($callArgs)';
    final guardCall = fieldHasValidation(field)
        ? 'await ${guardVar(service)}.${methodName(GLService.getValidationMethodName(field.name.token))}($guardArgs)'
        : null;
    final resultExpr = py.carryingSource(() => py.toJsonExpr(field.type, 'result'));
    final name = '${binding}_$method';
    return _cg.createMethod(
      decorators: ['@$binding.field(${py.pythonStringLiteral(field.name.token)})'],
      async: true,
      methodName: name,
      arguments: ['_', 'info', '**args'],
      statements: [
        if (ctx) 'context: GraphLinkContext = info.context',
        ..._decodeArgs(field),
        if (intercepted) _runBefore(field, type, field.name.token, argNames, info: true),
        if (guardCall != null) guardCall,
        'result = await $call',
        'return $resultExpr',
      ],
    );
  }

  List<String> _serializeSubscriptions(List<GLService> services) {
    final result = <String>[];
    for (final service in services) {
      for (final field in service.fields) {
        if (service.getTypeByFieldName(field.name.token) != GLQueryType.subscription) continue;
        final intercepted = grammar.isIntercepted(field, GLQueryType.subscription);
        final ctx = injectsContext(field) || intercepted;
        final argNames = field.arguments.map((a) => a.codeName).toList();
        final callArgs = [...argNames, if (injectsContext(field)) 'context'].join(', ');
        final method = methodName(field.name.token);
        final wire = py.pythonStringLiteral(field.name.token);
        result.add(_cg.createMethod(
          decorators: ['@subscription.source($wire)'],
          async: true,
          methodName: 'subscription_${method}_source',
          arguments: ['_', 'info', '**args'],
          statements: [
            if (ctx) 'context: GraphLinkContext = info.context',
            ..._decodeArgs(field),
            if (intercepted) _runBefore(field, GLQueryType.subscription, field.name.token, argNames),
            _cg.forEachLoop(
              async: true,
              variable: 'item',
              iterable: '${serviceVar(service)}.$method($callArgs)',
              statements: ['yield item'],
            ),
          ],
        ));
        final payloadJson = py.carryingSource(() => py.toJsonExpr(field.type, 'payload'));
        result.add(_cg.createMethod(
          decorators: ['@subscription.field($wire)'],
          methodName: 'subscription_$method',
          arguments: ['payload', 'info', '**args'],
          statements: ['return $payloadJson'],
        ));
      }
    }
    return result;
  }

  _TypeMappings _serializeTypeMappings(List<GLService> services) {
    final byType = <String, List<_MappingEntry>>{};
    for (final service in services) {
      for (final mapping in service.mappings) {
        byType.putIfAbsent(mapping.type.token, () => []).add(_MappingEntry(mapping, service));
      }
    }
    final passThrough = _mapToPassThroughFields();
    final statements = <String>[];
    final bindings = <String>[];
    for (final typeName in {...byType.keys, ...passThrough.keys}) {
      final variable = '${moduleName(typeName)}_type';
      statements.add('$variable = ObjectType(${py.pythonStringLiteral(typeName)})');
      bindings.add(variable);
      for (final entry in byType[typeName] ?? <_MappingEntry>[]) {
        final resolver = _mappingResolver(entry.mapping, entry.service, variable);
        if (resolver != null) statements.add(resolver);
      }
      for (final name in passThrough[typeName] ?? <String>[]) {
        statements.add(_cg.createMethod(
          decorators: ['@$variable.field(${py.pythonStringLiteral(name)})'],
          methodName: '${variable}_${name.toSnakeCaseWords()}_passthrough',
          arguments: ['parent', 'info', '**args'],
          statements: ['return parent'],
        ));
      }
    }
    return _TypeMappings(statements, bindings);
  }

  Map<String, List<String>> _mapToPassThroughFields() {
    final result = <String, List<String>>{};
    for (final type in grammar.types.values) {
      final source = type.getDirectiveByName(glSkipOnServer)?.getArgValueAsString(glMapTo);
      if (source == null) continue;
      final mapped = {
        for (final service in grammar.services.values)
          for (final mapping in service.mappings)
            if (mapping.type.token == type.token) mapping.field.name.token,
      };
      for (final field in type.fields) {
        if (field.type is GLListType || field.type.token != source || mapped.contains(field.name.token)) continue;
        result.putIfAbsent(type.token, () => []).add(field.name.token);
      }
    }
    return result;
  }

  String? _mappingResolver(GLSchemaMapping m, GLService service, String variable) {
    final wire = py.pythonStringLiteral(m.field.name.token);
    final name = '${variable}_${m.field.name.token.toSnakeCaseWords()}';
    final decorator = '@$variable.field($wire)';
    final intercepted = grammar.isIntercepted(m.field);
    final realArgs = _realMappingArgs(m);
    final argCodeNames = realArgs.map((a) => a.codeName).toList();
    final runBefore = intercepted ? _runBefore(m.field, null, '${m.type.token}.${m.field.name.token}', argCodeNames) : null;

    if (m.forbid) {
      return _cg.createMethod(
        decorators: [decorator],
        methodName: name,
        arguments: ['parent', 'info', '**args'],
        statements: ['raise GraphQLError("Access denied", extensions={"code": "FORBIDDEN"})'],
      );
    }
    if (m.identity || m.forwarded) {
      if (runBefore == null) return null;
      return _cg.createMethod(
        decorators: [decorator],
        async: true,
        methodName: name,
        arguments: ['parent', 'info', '**args'],
        statements: [
          'context: GraphLinkContext = info.context',
          ..._decodeRealArgs(realArgs),
          runBefore,
          'return parent.get($wire)',
        ],
      );
    }

    final ctx = injectsContext(m.field) || intercepted;
    final resultJson = py.carryingSource(() => py.toJsonExpr(m.field.type, 'result'));
    if (m.isBatch) {
      final loader = realArgs.isEmpty
          ? 'context.loaders.${methodName(m.key)}'
          : 'context.loaders.${methodName(m.key)}(${argCodeNames.join(', ')})';
      return _cg.createMethod(
        decorators: [decorator],
        async: true,
        methodName: name,
        arguments: ['parent', 'info', '**args'],
        statements: [
          'context: GraphLinkContext = info.context',
          ..._decodeRealArgs(realArgs),
          if (runBefore != null) runBefore,
          'result = await $loader.load(parent)',
          'return $resultJson',
        ],
      );
    }
    final callArgs = [
      for (final a in m.field.arguments)
        a.skipOnGraphqlSerialization ? (_carriesSource(m.type.token) ? 'source_of(parent)' : 'parent') : a.codeName,
      if (injectsContext(m.field)) 'context',
      if (config.useResolveInfo) 'info',
    ].join(', ');
    return _cg.createMethod(
      decorators: [decorator],
      async: true,
      methodName: name,
      arguments: ['parent', 'info', '**args'],
      statements: [
        if (ctx) 'context: GraphLinkContext = info.context',
        ..._decodeRealArgs(realArgs),
        if (runBefore != null) runBefore,
        'result = await ${serviceVar(service)}.${methodName(m.key)}($callArgs)',
        'return $resultJson',
      ],
    );
  }

  List<String> _decodeRealArgs(List<GLArgumentDefinition> args) => [
        for (final arg in args) _cg.constDecl(arg.codeName, _decodeArg(arg)),
      ];

  // ── app.py ────────────────────────────────────────────────────────────────

  @override
  String serializeEntryPoint() {
    final services = grammar.services.values.toList();
    final restOnly = grammar.restOnly;
    final guarded = services.where(_hasGuard).toList();

    final imports = <String>[
      'from __future__ import annotations',
      '',
      'from dataclasses import dataclass',
      'from typing import Any, Callable, Optional',
      '',
      'from fastapi import FastAPI',
      'from fastapi.middleware.cors import CORSMiddleware',
      if (!restOnly) ...[
        'from ariadne.asgi import GraphQL',
        'from ariadne.explorer import ExplorerHttp405',
        'from starlette.routing import Route, WebSocketRoute',
      ],
      '',
      'from .context import GraphLinkContext',
      if (!restOnly) ...[
        'from .$fastapiRuntimeDir.graph_link_guards import DEFAULT_MAX_QUERY_DEPTH, format_error, max_depth_rule',
        'from .$fastapiRuntimeDir.graph_link_ws import GraphLinkWSHandler',
        'from .resolvers import build_schema',
      ],
      if (hasRest) 'from .rest.router import build_rest_router',
      if (hasInterceptor) 'from .interfaces.$interceptorFileName import $interceptorClassName',
      for (final service in services) ...[
        'from .services.${serviceFileName(service)} import ${service.token}',
        if (_hasGuard(service)) 'from .guards.${guardFileName(service)} import ${guardName(service)}',
      ],
      for (final service in services)
        for (final m in service.mappings.where((m) => m.isBatch))
          'from .loaders.${loaderFileName(service)} import create_${methodName(m.key)}_loader',
    ];

    final fields = <String>[
      for (final service in services) '${serviceVar(service)}: ${service.token}',
      for (final service in guarded) '${guardVar(service)}: ${guardName(service)}',
      if (hasInterceptor) 'interceptor: Optional[$interceptorClassName] = None',
      'max_query_depth: Optional[int] = None',
      'context_factory: Optional[Callable[[Any], GraphLinkContext]] = None',
    ];
    final servicesClass = _cg.createClass(
      className: 'GraphLinkServices',
      decorators: ['@dataclass'],
      statements: fields,
    );

    final loaderLines = [
      for (final service in services)
        for (final m in service.mappings.where((m) => m.isBatch))
          'context.loaders.${methodName(m.key)} = create_${methodName(m.key)}_loader(services.${serviceVar(service)}${injectsContext(m.field) ? ', context' : ''})',
    ];
    final createContext = _cg.createMethod(
      methodName: 'create_context',
      arguments: ['services: GraphLinkServices', 'request: Any'],
      returnType: 'GraphLinkContext',
      statements: [
        _cg.constDecl(
          'context',
          _cg.ternaryOp(
            condition: 'services.context_factory is not None',
            positiveStatement: 'services.context_factory(request)',
            negativeStatement: 'GraphLinkContext(request)',
          ),
        ),
        ...loaderLines,
        'return context',
      ],
    );

    final interceptorGuard = hasInterceptor
        ? _cg.ifStatement(condition: 'services.interceptor is None', ifBlockStatements: [
            'raise ValueError("GraphLinkServices.interceptor is required: the schema uses @glIntercept.")',
          ])
        : null;
    final schemaArgs = [
      for (final service in services) 'services.${serviceVar(service)}',
      for (final service in guarded) 'services.${guardVar(service)}',
      if (hasInterceptor) 'services.interceptor',
    ].join(', ');
    final graphqlPath = py.pythonStringLiteral(config.graphqlPath);

    final createApp = _cg.createMethod(
      methodName: 'create_app',
      arguments: ['services: GraphLinkServices'],
      returnType: 'FastAPI',
      statements: [
        if (interceptorGuard != null) interceptorGuard,
        _cg.constDecl('app', 'FastAPI(docs_url=None, redoc_url=None, openapi_url=None)'),
        'app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])',
        if (!restOnly) ...[
          _cg.constDecl(
            'max_depth',
            _cg.ternaryOp(
              condition: 'services.max_query_depth is not None',
              positiveStatement: 'services.max_query_depth',
              negativeStatement: 'DEFAULT_MAX_QUERY_DEPTH',
            ),
          ),
          _cg.constDecl('schema', 'build_schema($schemaArgs)'),
          _cg.constDecl(
            'graphql_app',
            _cg.callExpression('GraphQL', [
              'schema',
              'context_value=lambda request, _data: create_context(services, request)',
              'validation_rules=[max_depth_rule(max_depth)]',
              'error_formatter=format_error',
              'execute_get_queries=True',
              'debug=False',
              'explorer=ExplorerHttp405()',
              'websocket_handler=GraphLinkWSHandler()',
            ]),
          ),
          'app.router.routes.append(Route($graphqlPath, graphql_app))',
          'app.router.routes.append(WebSocketRoute($graphqlPath, graphql_app))',
        ],
        if (hasRest) 'app.include_router(build_rest_router(services, lambda request: create_context(services, request)))',
        'return app',
      ],
    );
    return '${imports.join('\n')}\n\n\n$servicesClass\n\n\n$createContext\n\n\n$createApp\n';
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  List<String> _spaced(List<String> members) {
    if (members.isEmpty) return ['pass'];
    return [
      for (var i = 0; i < members.length; i++) ...[if (i > 0) '', members[i]],
    ];
  }

  String _uploadType(GLType type) {
    final upload = type is GLListType ? 'List[FileUpload]' : 'FileUpload';
    return type.nullable ? 'Optional[$upload]' : upload;
  }

  String _module({required String body, required List<String> imports}) {
    final typing = <String>[
      if (body.contains('Any')) 'Any',
      if (body.contains('AsyncIterator')) 'AsyncIterator',
      if (body.contains('Dict[')) 'Dict',
      if (body.contains('List[')) 'List',
      if (body.contains('Optional[')) 'Optional',
      if (body.contains('Protocol')) 'Protocol',
    ];
    final lines = <String>[
      'from __future__ import annotations',
      '',
      if (typing.isNotEmpty) 'from typing import ${typing.join(', ')}',
      '',
      ...{...imports},
      '',
      '',
      body.trimRight(),
    ];
    return '${lines.join('\n').replaceAll(RegExp(r'\n{4,}'), '\n\n\n')}\n';
  }

  List<String> _importLines(Set<String> typeNames, {bool root = false}) {
    final seen = <String>{};
    final lines = <String>[];
    for (final name in typeNames) {
      final token = grammar.types[name] ?? grammar.interfaces[name] ?? grammar.inputs[name] ?? grammar.enums[name];
      if (token == null) continue;
      var line = py.serializeImportToken(token);
      if (root) line = line.replaceFirst('from ..', 'from .');
      if (line.isEmpty || !seen.add(line)) continue;
      lines.add(line);
    }
    return lines;
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

class _TypeMappings {
  final List<String> statements;
  final List<String> bindings;
  _TypeMappings(this.statements, this.bindings);
}

class _MappingEntry {
  final GLSchemaMapping mapping;
  final GLService service;
  _MappingEntry(this.mapping, this.service);
}

const _pythonKeywords = {
  'False', 'None', 'True', 'and', 'as', 'assert', 'async', 'await', 'break', 'class', 'continue', 'def', 'del', 'elif',
  'else', 'except', 'finally', 'for', 'from', 'global', 'if', 'import', 'in', 'is', 'lambda', 'nonlocal', 'not', 'or',
  'pass', 'raise', 'return', 'try', 'while', 'with', 'yield',
};
