import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_intercept_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_server_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/python_code_gen_utils.dart';
import 'package:graphlink/src/serializers/python/fastapi_ariadne_rest_constants.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';

const _allMethods = '["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"]';

class _RouteBinding {
  final GLRestOperation op;
  final GLService service;

  _RouteBinding(this.op, this.service);
}

/// The REST adapter of a FastAPI server: one router holding every REST operation, bound to the same service
/// protocols the GraphQL resolvers use.
class FastapiAriadneRestSerializer {
  final GLParser grammar;
  final PythonSerializer py;
  final FastapiAriadneServerConfig config;
  final _cg = PythonCodeGenUtils();

  FastapiAriadneRestSerializer(this.grammar, this.py, this.config);

  bool get hasRest => grammar.restOperations.isNotEmpty;

  bool get hasUploads => grammar.restOperations.values.any((op) => op.arguments.any((a) => _isUpload(a.argument.type)));

  bool get hasDownloads => grammar.restOperations.values.any((op) => op.responseKind == RestResponseKind.binary);

  bool get hasMultipart => grammar.restOperations.values.any((op) => op.bodyKind == RestBodyKind.multipart);

  String serializeSupport() => fastapiRestSupport.trimLeft();

  String serializeDownloads() => fastapiRestDownload.trimLeft();

  String serializeUploads() =>
      '${fastapiRestUploadsRaw.trimLeft()}${hasMultipart ? fastapiRestUploadsMultipart : ''}';

  String methodName(String wire) {
    final name = wire.toSnakeCaseWords();
    return _keywords.contains(name) ? '${name}_' : name;
  }

  String serializeRestRouter() {
    final bindings = _bindings();
    final intercepted = bindings.any((b) => _intercepted(b.op));
    final interceptor = intercepted ? grammar.interfaces[glInterceptorInterfaceName]! : null;
    final tagEnum = intercepted ? grammar.enums[glInterceptorTagEnumName] : null;
    final multipart = bindings.any((b) => b.op.bodyKind == RestBodyKind.multipart);

    final handlers = <String>[];
    final registrations = <String>[];
    for (final binding in bindings) {
      handlers.add(_handler(binding));
      registrations.add(
          'router.add_api_route(${py.pythonStringLiteral(_path(binding.op))}, handle(${_handlerName(binding.op)}), methods=[${py.pythonStringLiteral(binding.op.method.wireName)}])');
    }

    final body = _cg.createMethod(
      methodName: 'build_rest_router',
      arguments: ['services: Any', 'create_context: Callable[[Any], GraphLinkContext]'],
      returnType: 'APIRouter',
      statements: [
        'router = APIRouter()',
        _shapes(bindings),
        for (final handler in handlers) ...['', handler],
        '',
        ...registrations,
        ..._methodNotAllowedRoutes(bindings),
        ..._notFoundRoute(bindings),
        'return router',
      ],
    );

    final imports = <String>[
      'from typing import Any, Callable, Dict, List, Optional',
      '',
      'from fastapi import APIRouter',
      'from starlette.requests import Request',
      'from starlette.responses import Response',
      '',
      'from ..context import GraphLinkContext',
      if (interceptor != null) 'from ..interfaces.${py.moduleNameFor(interceptor)} import ${interceptor.codeName}',
      if (tagEnum != null) 'from ..enums.${py.moduleNameFor(tagEnum)} import ${tagEnum.codeName}',
      'from .support import (',
      '    S,',
      '    body_arg,',
      '    checked,',
      '    form_arg,',
      '    form_list_arg,',
      '    handle,',
      '    header_arg,',
      '    header_list_arg,',
      '    json_arg,',
      '    method_not_allowed,',
      '    nested_arg,',
      '    not_found,',
      '    path_arg,',
      '    query_arg,',
      '    query_list_arg,',
      '    query_params,',
      '    read_form,',
      '    send_json,',
      '    send_no_content,',
      '    send_text,',
      '    wrap,',
      ')',
      if (hasDownloads) 'from .download import send_download',
      if (hasUploads) 'from .uploads import raw_upload_arg${multipart ? ', read_multipart, file_arg, file_list_arg' : ''}',
      ..._typeImports(bindings),
    ];
    return '${imports.join('\n')}\n\n\n$body\n';
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

  String _handlerName(GLRestOperation op) => 'rest_${methodName(op.field.name.token)}';

  String _serviceVar(GLService service) => service.token.toSnakeCaseWords();

  String _guardVar(GLService service) => '${service.token.replaceFirst('Service', '')}Guard'.toSnakeCaseWords();

  // ── route ─────────────────────────────────────────────────────────────────

  String _handler(_RouteBinding binding) {
    final op = binding.op;
    final statements = <String>[];
    final callArgs = <String>[];
    if (op.bodyKind == RestBodyKind.multipart) statements.add('_form = await read_multipart(request)');
    if (op.bodyKind == RestBodyKind.form) statements.add('_form = read_form(request)');
    if (op.arguments.any(_readsStructuredQuery)) statements.add('_query = query_params(request)');
    for (final restArg in op.arguments) {
      statements.addAll(_argument(restArg));
      callArgs.add(restArg.argument.codeName);
    }
    final rawArgs = List<String>.of(callArgs);
    final passesContext = _injectsContext(op);
    if (passesContext || _intercepted(op)) statements.add('_context = create_context(request)');
    if (passesContext) callArgs.add('_context');
    if (_intercepted(op)) statements.add(_runBefore(op, rawArgs));
    final service = 'services.${_serviceVar(binding.service)}';
    if (_hasValidation(op)) {
      final guard = 'services.${_guardVar(binding.service)}';
      statements.add(
          'await $guard.${methodName(GLService.getValidationMethodName(op.field.name.token))}(${callArgs.join(', ')})');
    }
    final call = '$service.${methodName(op.field.name.token)}(${callArgs.join(', ')})';
    statements.addAll(_response(op, call));
    return _cg.createMethod(
      async: true,
      methodName: _handlerName(op),
      arguments: ['request: Request'],
      returnType: 'Response',
      statements: statements,
    );
  }

  bool _intercepted(GLRestOperation op) => grammar.isIntercepted(op.field, op.type);

  String _runBefore(GLRestOperation op, List<String> rawArgs) {
    final tagEnum = grammar.enums[glInterceptorTagEnumName];
    final tag = grammar.interceptTag(op.field, op.type);
    final callArgs = [
      if (tagEnum != null) tag == null ? 'None' : '${tagEnum.codeName}.${tagEnum.values.firstWhere((v) => v.token == tag).codeName}',
      py.pythonStringLiteral(op.name),
      '[${rawArgs.join(', ')}]',
      '_context',
    ];
    return 'await services.interceptor.run_before(${callArgs.join(', ')})';
  }

  List<String> _response(GLRestOperation op, String call) {
    if (op.responseKind == RestResponseKind.none) return ['await $call', 'return send_no_content()'];
    final result = '_result = await $call';
    if (op.responseKind == RestResponseKind.binary) return [result, 'return send_download(_result)'];
    if (op.responseKind == RestResponseKind.text) return [result, 'return send_text(_result)'];
    final json = _needsConversion(op.field.type) ? py.toJsonExpr(op.field.type, '_result') : '_result';
    final path = op.responsePathSegments;
    return [
      result,
      'return send_json(${path.isEmpty ? json : 'wrap($json, [${path.map(py.pythonStringLiteral).join(', ')}])'})',
    ];
  }

  // ── arguments ─────────────────────────────────────────────────────────────

  List<String> _argument(GLRestArgument restArg) {
    final arg = restArg.argument;
    final code = arg.codeName;
    final options = _options(arg);
    if (_isStructured(restArg)) return _convert(code, arg.type, _readStructured(restArg, options));
    switch (restArg.role) {
      case RestArgRole.path:
        return _convert(code, arg.type, 'path_arg(request, ${_pathKey(restArg.wireName!).quoted(py)}, ${_shape(arg.type)})');
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
        if (_isUpload(arg.type)) return [_cg.constDecl(code, 'raw_upload_arg(request)')];
        return _convert(code, arg.type, 'body_arg(request, ${_shape(arg.type)}, shapes, $options)');
      case RestArgRole.field:
        return _convert(code, arg.type, _readPart(restArg, options));
    }
  }

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
    final params = restArg.role == RestArgRole.query ? '_query' : '_form.fields';
    final helper = restArg.encoding == RestEncoding.json ? 'json_arg' : 'nested_arg';
    return '$helper($params, ${py.pythonStringLiteral(restArg.wireName!)}, ${_shape(type)}, shapes, $options)';
  }

  String _readPart(GLRestArgument restArg, String options) {
    final type = restArg.argument.type;
    final wire = py.pythonStringLiteral(restArg.wireName!);
    if (_isUpload(type)) {
      return '${type is GLListType ? 'file_list_arg' : 'file_arg'}(_form, $wire, ${options.contains('optional') ? '{"optional": True}' : '{}'})';
    }
    final list = type is GLListType;
    return 'form${list ? '_list' : ''}_arg(_form, $wire, ${_shape(list ? type.inlineType : type)}, $options)';
  }

  bool _isUpload(GLType type) => grammar.uploadScalarNames.contains(type.firstType.token);

  String _readValue(GLRestArgument restArg, String source, String options) {
    final type = restArg.argument.type;
    final list = type is GLListType;
    final helper = '${source}_${list ? 'list_' : ''}arg';
    return '$helper(request, ${py.pythonStringLiteral(restArg.wireName!)}, ${_shape(list ? type.inlineType : type)}, $options)';
  }

  List<String> _spread(GLRestArgument restArg, String source) {
    final arg = restArg.argument;
    final input = grammar.inputs[arg.type.firstType.token]!;
    final fieldLines = <String>[];
    for (final field in input.fields) {
      final wire = restArg.spreadFields[field.name.token] ?? field.name.token;
      if (source == 'query' && _isInput(field.type)) {
        fieldLines.add(
            '${py.pythonStringLiteral(field.name.token)}: nested_arg(_query, ${py.pythonStringLiteral(wire)}, ${_shape(field.type)}, shapes, {"optional": True}),');
        continue;
      }
      final list = field.type is GLListType;
      final helper = '${source}_${list ? 'list_' : ''}arg';
      final shape = _shape(list ? field.type.inlineType : field.type);
      fieldLines.add(
          '${py.pythonStringLiteral(field.name.token)}: $helper(request, ${py.pythonStringLiteral(wire)}, $shape, {"optional": True}),');
    }
    final wireName = '${arg.codeName}_wire';
    final shape = '{"k": "ref", "name": ${py.pythonStringLiteral(input.token)}}';
    final entries = fieldLines.map((l) => l.identPy()).join('\n');
    final collected = _cg.constDecl(
        wireName, '{k: v for k, v in {\n$entries\n}.items() if v is not None}');
    final decoded = py.fromJsonExpr(GLType(arg.type.tokenInfo, false), 'checked($wireName, $shape, shapes)');
    final value = arg.type.nullable
        ? _cg.ternaryOp(condition: 'not $wireName', positiveStatement: 'None', negativeStatement: decoded)
        : decoded;
    return [collected, _cg.constDecl(arg.codeName, value)];
  }

  List<String> _convert(String name, GLType type, String read) {
    if (!_needsConversion(type)) return [_cg.constDecl(name, read)];
    final wire = '${name}_wire';
    return [_cg.constDecl(wire, read), _cg.constDecl(name, py.fromJsonExpr(type, wire))];
  }

  String _options(GLArgumentDefinition arg) {
    final defaultValue = arg.defaultValue?.value;
    final parts = [
      if (arg.type.nullable || defaultValue != null) '"optional": True',
      if (defaultValue != null) '"default_value": ${_literal(defaultValue)}',
    ];
    return parts.isEmpty ? '{}' : '{${parts.join(', ')}}';
  }

  String _literal(Object value) {
    if (value is String) return py.pythonStringLiteral(value);
    if (value is bool) return value ? 'True' : 'False';
    return value.toString();
  }

  // ── shapes ────────────────────────────────────────────────────────────────

  String _shape(GLType type) {
    if (type is GLListType) {
      return '{"k": "list", "of": ${_shape(type.inlineType)}, "nullable": ${type.inlineType.nullable ? 'True' : 'False'}}';
    }
    final token = type.token;
    final enumDefinition = grammar.enums[token];
    if (enumDefinition != null) {
      return '{"k": "enum", "values": [${enumDefinition.values.map((v) => py.pythonStringLiteral(v.wireName)).join(', ')}]}';
    }
    if (_isInput(type)) return '{"k": "ref", "name": ${py.pythonStringLiteral(token)}}';
    switch (token) {
      case 'String':
      case 'ID':
        return 'S["string"]';
      case 'Int':
        return 'S["int"]';
      case 'Float':
        return 'S["float"]';
      case 'Boolean':
        return 'S["boolean"]';
      default:
        return '{"k": "any"}';
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
        '${py.pythonStringLiteral(name)}: {"k": "object", "fields": {\n${[
          for (final field in grammar.inputs[name]!.fields)
            '${py.pythonStringLiteral(field.name.token)}: {"shape": ${_shape(field.type)}, "required": ${!field.type.nullable && field.initialValue == null ? 'True' : 'False'}},',
        ].map((l) => l.identPy()).join('\n')}\n}},',
    ];
    if (entries.isEmpty) return _cg.constDecl('shapes', '{}', type: 'Dict[str, Any]');
    return _cg.constDecl('shapes', '{\n${entries.map((e) => e.identPy()).join('\n')}\n}', type: 'Dict[str, Any]');
  }

  // ── routes that exist for another method only ─────────────────────────────

  List<String> _methodNotAllowedRoutes(List<_RouteBinding> bindings) {
    final methodsByPath = <String, List<String>>{};
    for (final binding in bindings) {
      methodsByPath.putIfAbsent(_path(binding.op), () => []).add(binding.op.method.wireName);
    }
    return [
      for (final entry in methodsByPath.entries)
        'router.add_api_route(${py.pythonStringLiteral(entry.key)}, method_not_allowed([${entry.value.map(py.pythonStringLiteral).join(', ')}]), methods=$_allMethods)',
    ];
  }

  List<String> _notFoundRoute(List<_RouteBinding> bindings) {
    final prefixes = [
      for (final binding in bindings)
        _path(binding.op).split('/').where((s) => s.isNotEmpty).takeWhile((s) => !s.startsWith('{')).toList(),
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
    final base = '/${common.join('/')}';
    return [
      'router.add_api_route(${py.pythonStringLiteral(base)}, not_found, methods=$_allMethods)',
      'router.add_api_route(${py.pythonStringLiteral('$base/{rest_path:path}')}, not_found, methods=$_allMethods)',
    ];
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  bool _hasValidation(GLRestOperation op) => op.field.hasDirective(glValidate);

  bool _injectsContext(GLRestOperation op) => config.injectContext || op.field.hasDirective(glInjectContext);

  bool _isInput(GLType type) => grammar.inputs.containsKey(type.firstType.token);

  bool _needsConversion(GLType type) {
    final token = type.firstType.token;
    return grammar.isEnum(token) || grammar.isProjectableType(token);
  }

  String _pathKey(String placeholder) => placeholder.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');

  String _path(GLRestOperation op) => op.path.replaceAllMapped(restPlaceholder, (m) => '{${_pathKey(m.group(1)!)}}');

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
      final line = py.serializeImportToken(token);
      if (line.isNotEmpty && seen.add(line)) lines.add(line);
    }
    return lines;
  }
}

extension on String {
  String quoted(PythonSerializer py) => py.pythonStringLiteral(this);
}

const _keywords = {
  'False', 'None', 'True', 'and', 'as', 'assert', 'async', 'await', 'break', 'class', 'continue', 'def', 'del', 'elif',
  'else', 'except', 'finally', 'for', 'from', 'global', 'if', 'import', 'in', 'is', 'lambda', 'nonlocal', 'not', 'or',
  'pass', 'raise', 'return', 'try', 'while', 'with', 'yield',
};
