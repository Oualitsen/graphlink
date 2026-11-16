import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_intercept_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_server_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/serializers/typescript/express_apollo_rest_constants.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
import 'package:graphlink/src/typescript_code_gen_utils.dart';

const _supportImports = [
  'S',
  'Shapes',
  'bodyArg',
  'checked',
  'formArg',
  'formListArg',
  'handle',
  'jsonArg',
  'headerArg',
  'headerListArg',
  'methodNotAllowed',
  'nestedArg',
  'notFound',
  'pathArg',
  'queryArg',
  'queryListArg',
  'queryParams',
  'readForm',
  'restErrorHandler',
  'sendJson',
  'sendNoContent',
  'sendText',
  'wrap',
];

class _RouteBinding {
  final GLRestOperation op;
  final GLService service;

  _RouteBinding(this.op, this.service);

  String get serviceVar => service.token.firstLow;
}

/// The REST adapter of an Express server: one router holding every REST operation, bound to the same service
/// interfaces the GraphQL resolvers use.
class ExpressApolloRestSerializer {
  final GLParser grammar;
  final TypeScriptSerializer tsSerializer;
  final ExpressApolloServerConfig apolloConfig;
  final _cg = TypeScriptCodeGenUtils();

  ExpressApolloRestSerializer(this.grammar, this.tsSerializer, this.apolloConfig);

  bool get hasRest => grammar.restOperations.isNotEmpty;

  bool get hasUploads => grammar.restOperations.values.any((op) => op.arguments.any((a) => _isUpload(a.argument.type)));

  bool get hasDownloads => grammar.restOperations.values.any((op) => op.responseKind == RestResponseKind.binary);

  String serializeDownloads() {
    final imports = [
      "import { Response } from 'express';",
      "import { Readable } from 'node:stream';",
      "import { pipeline } from 'node:stream/promises';",
    ];
    return '${GLClassModel(imports: imports, body: expressRestDownload).toFileContent()}\n';
  }

  bool get hasForm => grammar.restOperations.values.any((op) => op.bodyKind == RestBodyKind.form);

  bool get hasMultipart => grammar.restOperations.values.any((op) => op.bodyKind == RestBodyKind.multipart);

  String serializeUploads() {
    final imports = [
      "import { Request${hasMultipart ? ', Response' : ''} } from 'express';",
      "import type { FileUpload } from '../file-upload.js';",
      if (hasMultipart) ...[
        "import busboy from 'busboy';",
        "import { createReadStream, createWriteStream } from 'node:fs';",
        "import { mkdtemp, rm } from 'node:fs/promises';",
        "import { tmpdir } from 'node:os';",
        "import { join } from 'node:path';",
        "import { pipeline } from 'node:stream/promises';",
        "import { ArgOptions, FormFields, RestError, Shape, hasBody, parseScalar } from './support.js';",
      ],
    ];
    return '${GLClassModel(imports: imports, body: '$expressRestUploadsRaw${hasMultipart ? expressRestUploadsMultipart : ''}').toFileContent()}\n';
  }

  String serializeRestRouter() {
    final bindings = _bindings();
    final routes = [for (final binding in bindings) _route(binding)];
    final usesContext = bindings.any((b) => _injectsContext(b.op) || _intercepted(b.op));
    final intercepted = bindings.any((b) => _intercepted(b.op));
    final interceptor = intercepted ? grammar.interfaces[glInterceptorInterfaceName]! : null;
    final tagEnum = intercepted ? grammar.enums[glInterceptorTagEnumName] : null;
    final services = bindings.map((b) => b.service).toSet().toList();
    final guarded = bindings.where((b) => _hasValidation(b.op)).map((b) => b.service).toSet().toList();

    final imports = [
      "import express, { Request, Response, Router } from 'express';",
      if (usesContext) "import { GraphLinkContext } from '../context.js';",
      if (interceptor != null)
        "import { ${interceptor.codeName} } from '../interfaces/${tsSerializer.getFileNameFor(interceptor).replaceAll('.ts', '.js')}';",
      if (tagEnum != null)
        "import { ${tagEnum.codeName} } from '../enums/${tsSerializer.getFileNameFor(tagEnum).replaceAll('.ts', '.js')}';",
      "import { ${_supportImports.join(', ')} } from './support.js';",
      if (hasDownloads) "import { sendDownload } from './download.js';",
      if (hasUploads) "import { rawUploadArg${hasMultipart ? ', readMultipart, fileArg, fileListArg' : ''} } from './uploads.js';",
      for (final service in services)
        "import { ${service.token} } from '../services/${service.token.toKebabCase()}.js';",
      for (final service in guarded)
        "import { ${_guardName(service)} } from '../guards/${_guardName(service).toKebabCase()}.js';",
      ..._typeImports(bindings),
    ];

    final body = StringBuffer();
    body.writeln(_cg.createInterface(interfaceName: 'RestServices', exported: true, fields: [
      for (final service in services) '${service.token.firstLow}: ${service.token};',
      for (final service in guarded) '${_guardName(service).firstLow}: ${_guardName(service)};',
      if (interceptor != null) 'interceptor?: ${interceptor.codeName};',
      if (usesContext)
        'contextFactory?: (req: Request, res: Response) => GraphLinkContext | Promise<GraphLinkContext>;',
    ]));
    body.writeln();
    body.writeln(_shapes(bindings));
    body.writeln();
    if (usesContext) {
      body.writeln(_cg.createFunction(
        functionName: 'restContext',
        arguments: ['services: RestServices', 'req: Request', 'res: Response'],
        returnType: 'GraphLinkContext',
        async: true,
        statements: [
          'return services.contextFactory ? await services.contextFactory(req, res) : ({} as GraphLinkContext);',
        ],
      ));
      body.writeln();
    }
    body.writeln(_cg.createFunction(
      functionName: 'buildRestRouter',
      arguments: ['services: RestServices'],
      returnType: 'Router',
      exported: true,
      statements: [
        _cg.constDecl('router', 'Router()'),
        'router.use(express.json());',
        if (hasForm) "router.use(express.text({ type: 'application/x-www-form-urlencoded' }));",
        ...routes,
        ..._methodNotAllowedRoutes(bindings),
        ..._notFoundRoute(bindings),
        'router.use(restErrorHandler);',
        'return router;',
      ],
    ));
    return '${GLClassModel(imports: imports, body: body.toString()).toFileContent()}\n';
  }

  List<_RouteBinding> _bindings() {
    final bindings = <_RouteBinding>[];
    for (final service in grammar.services.values) {
      for (final op in grammar.restOperationsOf(service)) {
        bindings.add(_RouteBinding(op, service));
      }
    }
    return bindings;
  }

  // ── route ─────────────────────────────────────────────────────────────────

  String _route(_RouteBinding binding) {
    final op = binding.op;
    final statements = <String>[];
    final callArgs = <String>[];
    if (op.bodyKind == RestBodyKind.multipart) statements.add(_cg.constDecl('form', 'await readMultipart(req, res)'));
    if (op.bodyKind == RestBodyKind.form) statements.add(_cg.constDecl('form', 'readForm(req)'));
    if (op.arguments.any(_readsStructuredQuery)) statements.add(_cg.constDecl('query', 'queryParams(req)'));
    for (final restArg in op.arguments) {
      statements.addAll(_argument(restArg));
      callArgs.add(restArg.argument.codeName);
    }
    final rawArgs = List<String>.of(callArgs);
    final passesContext = _injectsContext(op);
    if (passesContext || _intercepted(op)) {
      statements.add(_cg.constDecl('context', 'await restContext(services, req, res)'));
    }
    if (passesContext) callArgs.add('context');
    if (_intercepted(op)) statements.add(_runBefore(op, rawArgs));
    final service = 'services.${binding.serviceVar}';
    if (_hasValidation(op)) {
      final guard = 'services.${_guardName(binding.service).firstLow}';
      statements.add('await $guard.${GLService.getValidationMethodName(op.field.name.token)}(${callArgs.join(', ')});');
    }
    final call = '$service.${op.field.codeName}(${callArgs.join(', ')})';
    statements.addAll(_response(op, call));
    final handler = 'handle(async (req, res) => ${_cg.block(statements)})';
    return "router.${op.method.name}(${_expressPath(op).quote()}, $handler);";
  }

  bool _intercepted(GLRestOperation op) => grammar.isIntercepted(op.field, op.type);

  String _runBefore(GLRestOperation op, List<String> rawArgs) {
    final tagEnum = grammar.enums[glInterceptorTagEnumName];
    final tag = grammar.interceptTag(op.field, op.type);
    final callArgs = [
      if (tagEnum != null) tag == null ? 'null' : '${tagEnum.codeName}.${tagEnum.values.firstWhere((v) => v.token == tag).codeName}',
      op.name.quote(),
      '[${rawArgs.join(', ')}]',
      'context',
      if (apolloConfig.useResolveInfo) 'null',
    ];
    return 'await services.interceptor!.runBefore(${callArgs.join(', ')});';
  }

  List<String> _response(GLRestOperation op, String call) {
    if (op.responseKind == RestResponseKind.none) {
      return ['await $call;', 'sendNoContent(res);'];
    }
    final result = _cg.constDecl('result', 'await $call');
    if (op.responseKind == RestResponseKind.binary) return [result, 'await sendDownload(res, result);'];
    if (op.responseKind == RestResponseKind.text) return [result, 'sendText(res, result);'];
    final needsJson = _needsConversion(op.field.type);
    final json = needsJson ? tsSerializer.toJsonExpr(op.field.type, 'result') : 'result';
    final path = op.responsePathSegments;
    return [result, 'sendJson(res, ${path.isEmpty ? json : 'wrap($json, [${path.map((s) => s.quote()).join(', ')}])'});'];
  }

  // ── arguments ─────────────────────────────────────────────────────────────

  List<String> _argument(GLRestArgument restArg) {
    final arg = restArg.argument;
    final code = arg.codeName;
    final options = _options(arg);
    if (_isStructured(restArg)) return _convert(code, arg.type, _readStructured(restArg, options));
    switch (restArg.role) {
      case RestArgRole.path:
        return _convert(code, arg.type, "pathArg(req, ${_pathKey(restArg.wireName!).quote()}, ${_shape(arg.type)})");
      case RestArgRole.query:
        return restArg.encoding == RestEncoding.spread && _isInput(arg.type)
            ? _spread(restArg, 'query')
            : _convert(code, arg.type, _readValue(restArg, 'query', options));
      case RestArgRole.header:
        return restArg.encoding == RestEncoding.spread && _isInput(arg.type)
            ? _spread(restArg, 'header')
            : _convert(code, arg.type, _readValue(restArg, 'header', options));
      case RestArgRole.part:
        return _convert(code, arg.type, _readPart(restArg, options));
      case RestArgRole.body:
        if (_isUpload(arg.type)) return [_cg.constDecl(code, 'rawUploadArg(req)')];
        final read = 'bodyArg(req, ${_shape(arg.type)}, shapes, $options)';
        return _convert(code, arg.type, read);
      case RestArgRole.field:
        return _convert(code, arg.type, _readPart(restArg, options));
    }
  }

  /// An input object, a list of them, or any value sent as JSON text, carried by the query string or a form.
  bool _isStructured(GLRestArgument restArg) {
    if (restArg.role != RestArgRole.query && restArg.role != RestArgRole.field) return false;
    if (restArg.encoding == RestEncoding.json) return true;
    return _isInput(restArg.argument.type) && !(restArg.role == RestArgRole.query && restArg.encoding == RestEncoding.spread);
  }

  bool _readsStructuredQuery(GLRestArgument restArg) {
    if (restArg.role != RestArgRole.query) return false;
    if (_isStructured(restArg)) return true;
    if (restArg.encoding != RestEncoding.spread || !_isInput(restArg.argument.type)) return false;
    return grammar.inputs[restArg.argument.type.firstType.token]!.fields.any((f) => _isInput(f.type));
  }

  String _readStructured(GLRestArgument restArg, String options) {
    final type = restArg.argument.type;
    final params = restArg.role == RestArgRole.query ? 'query' : 'form.fields';
    final helper = restArg.encoding == RestEncoding.json ? 'jsonArg' : 'nestedArg';
    return '$helper($params, ${restArg.wireName!.quote()}, ${_shape(type)}, shapes, $options)';
  }

  String _readPart(GLRestArgument restArg, String options) {
    final type = restArg.argument.type;
    final wire = restArg.wireName!.quote();
    if (_isUpload(type)) {
      return "${type is GLListType ? 'fileListArg' : 'fileArg'}(form, $wire, ${options.contains('optional') ? '{ optional: true }' : '{}'})";
    }
    final list = type is GLListType;
    return "form${list ? 'List' : ''}Arg(form, $wire, ${_shape(list ? type.inlineType : type)}, $options)";
  }

  bool _isUpload(GLType type) => grammar.uploadScalarNames.contains(type.firstType.token);

  String _readValue(GLRestArgument restArg, String source, String options) {
    final type = restArg.argument.type;
    final list = type is GLListType;
    final helper = '${source}${list ? 'List' : ''}Arg';
    final shape = _shape(list ? type.inlineType : type);
    return "$helper(req, ${restArg.wireName!.quote()}, $shape, $options)";
  }

  List<String> _spread(GLRestArgument restArg, String source) {
    final arg = restArg.argument;
    final input = grammar.inputs[arg.type.firstType.token]!;
    final fieldLines = <String>[];
    for (final field in input.fields) {
      final wire = restArg.spreadFields[field.name.token] ?? field.name.token;
      if (source == 'query' && _isInput(field.type)) {
        fieldLines.add('${field.name.token.quote()}: nestedArg(query, ${wire.quote()}, ${_shape(field.type)}, shapes, { optional: true }),');
        continue;
      }
      final list = field.type is GLListType;
      final helper = '$source${list ? 'List' : ''}Arg';
      final shape = _shape(list ? field.type.inlineType : field.type);
      fieldLines.add('${field.name.token.quote()}: $helper(req, ${wire.quote()}, $shape, { optional: true }),');
    }
    final wireName = '${arg.codeName}Wire';
    final shape = "{ k: 'ref', name: ${input.token.quote()} }";
    final collected = _cg.constDecl(
        wireName, 'Object.fromEntries(Object.entries(${_cg.block(fieldLines)}).filter(([, value]) => value != null))');
    final value = arg.type.nullable
        ? _cg.ternaryOp(
            condition: 'Object.keys($wireName).length === 0',
            positiveStatement: 'null',
            negativeStatement: tsSerializer.fromJsonExpr(
                GLType(arg.type.tokenInfo, false), "checked($wireName, $shape, shapes)"))
        : tsSerializer.fromJsonExpr(GLType(arg.type.tokenInfo, false), "checked($wireName, $shape, shapes)");
    return [collected, _cg.constDecl(arg.codeName, value)];
  }

  List<String> _convert(String name, GLType type, String read) {
    if (!_needsConversion(type)) return [_cg.constDecl(name, read)];
    final wire = '${name}Wire';
    return [_cg.constDecl(wire, read), _cg.constDecl(name, tsSerializer.fromJsonExpr(type, wire))];
  }

  String _options(GLArgumentDefinition arg) {
    final defaultValue = arg.defaultValue?.value;
    final parts = [
      if (arg.type.nullable || defaultValue != null) 'optional: true',
      if (defaultValue != null) 'defaultValue: ${_literal(defaultValue)}',
    ];
    return parts.isEmpty ? '{}' : '{ ${parts.join(', ')} }';
  }

  String _literal(Object value) => value is String ? value.quote() : value.toString();

  // ── shapes ────────────────────────────────────────────────────────────────

  String _shape(GLType type) {
    if (type is GLListType) {
      return "{ k: 'list', of: ${_shape(type.inlineType)}, nullable: ${type.inlineType.nullable} }";
    }
    final token = type.token;
    final enumDefinition = grammar.enums[token];
    if (enumDefinition != null) {
      return "{ k: 'enum', values: [${enumDefinition.values.map((v) => v.wireName.quote()).join(', ')}] }";
    }
    if (_isInput(type)) return "{ k: 'ref', name: ${token.quote()} }";
    switch (token) {
      case 'String':
      case 'ID':
        return 'S.string';
      case 'Int':
        return 'S.int';
      case 'Float':
        return 'S.float';
      case 'Boolean':
        return 'S.boolean';
      default:
        return "{ k: 'any' }";
    }
  }

  String _shapes(List<_RouteBinding> bindings) {
    final names = <String>{};
    final pending = [
      for (final binding in bindings)
        for (final restArg in binding.op.arguments)
          if (_isInput(restArg.argument.type)) restArg.argument.type.firstType.token,
    ];
    while (pending.isNotEmpty) {
      final name = pending.removeLast();
      if (!names.add(name)) continue;
      for (final field in grammar.inputs[name]!.fields) {
        if (_isInput(field.type)) pending.add(field.type.firstType.token);
      }
    }
    final entries = [
      for (final name in names)
        "$name: ${_cg.block([
              "k: 'object',",
              'fields: ${_cg.block([
                    for (final field in grammar.inputs[name]!.fields)
                      '${field.name.token.quote()}: { shape: ${_shape(field.type)}, required: ${!field.type.nullable && field.initialValue == null} },',
                  ])},',
            ])},",
    ];
    return _cg.constDecl('shapes', entries.isEmpty ? '{}' : _cg.block(entries), type: 'Shapes');
  }

  // ── routes that exist for another method only ─────────────────────────────

  List<String> _methodNotAllowedRoutes(List<_RouteBinding> bindings) {
    final methodsByPath = <String, List<String>>{};
    for (final binding in bindings) {
      methodsByPath.putIfAbsent(_expressPath(binding.op), () => []).add(binding.op.method.wireName);
    }
    return [
      for (final entry in methodsByPath.entries)
        "router.all(${entry.key.quote()}, methodNotAllowed([${entry.value.map((m) => m.quote()).join(', ')}]));",
    ];
  }

  /// Requests under the prefix every REST path shares, but matching no route, get a JSON 404.
  List<String> _notFoundRoute(List<_RouteBinding> bindings) {
    final prefixes = [
      for (final binding in bindings)
        _expressPath(binding.op).split('/').where((s) => s.isNotEmpty).takeWhile((s) => !s.startsWith(':')).toList(),
    ];
    var common = prefixes.first;
    for (final prefix in prefixes.skip(1)) {
      var length = 0;
      while (length < common.length && length < prefix.length && common[length] == prefix[length]) {
        length++;
      }
      common = common.sublist(0, length);
    }
    if (common.isEmpty) return const [];
    return ["router.use(${'/${common.join('/')}'.quote()}, notFound);"];
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  bool _hasValidation(GLRestOperation op) => op.field.hasDirective(glValidate);

  bool _injectsContext(GLRestOperation op) => apolloConfig.injectContext || op.field.hasDirective(glInjectContext);

  bool _isInput(GLType type) => grammar.inputs.containsKey(type.firstType.token);

  bool _needsConversion(GLType type) {
    final token = type.firstType.token;
    return grammar.isEnum(token) || grammar.isProjectableType(token);
  }

  String _guardName(GLService service) => '${service.token.replaceFirst('Service', '')}Guard';

  String _pathKey(String placeholder) => placeholder.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');

  String _expressPath(GLRestOperation op) =>
      op.path.replaceAllMapped(restPlaceholder, (m) => ':${_pathKey(m.group(1)!)}');

  List<String> _typeImports(List<_RouteBinding> bindings) {
    final names = <String>{};
    void collect(GLType type) {
      final token = type.firstType.token;
      if (grammar.isEnum(token) || grammar.isProjectableType(token) || grammar.types.containsKey(token)) names.add(token);
    }

    for (final binding in bindings) {
      collect(binding.op.field.type);
      for (final restArg in binding.op.arguments) {
        collect(restArg.argument.type);
      }
    }
    final seen = <String>{};
    final lines = <String>[];
    for (final name in names) {
      final token = grammar.types[name] ?? grammar.interfaces[name] ?? grammar.inputs[name] ?? grammar.enums[name];
      if (token == null) continue;
      final line = tsSerializer.serializeImportToken(token);
      if (line.isNotEmpty && seen.add(line)) lines.add(line);
    }
    return lines;
  }
}
