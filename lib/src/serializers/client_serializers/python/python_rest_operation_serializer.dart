import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_validation_extension.dart';
import 'package:graphlink/src/python_code_gen_utils.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';

const _request = 'gl_request__';
const _body = 'gl_body__';
const _json = 'gl_json__';
const _result = 'gl_result__';
const _fields = 'gl_fields__';
const _parts = 'gl_parts__';

class PythonRestOperationSerializer {
  final GLParser _grammar;
  final PythonCodeGenUtils _cg;
  final PythonSerializer _serializer;
  final bool commaLists;
  final bool bracketNesting;

  PythonRestOperationSerializer(
    this._grammar,
    this._cg,
    this._serializer, {
    this.commaLists = false,
    this.bracketNesting = false,
  });

  String get _listOptions =>
      [if (bracketNesting) 'bracket=True', if (commaLists) 'comma=True'].map((e) => ', $e').join();

  bool _isUpload(GLRestArgument a) => _grammar.uploadScalarNames.contains(a.argument.type.firstType.token);

  bool _hasProgress(GLRestOperation op) => op.bodyKind == RestBodyKind.raw || op.bodyKind == RestBodyKind.multipart;

  bool _hasSentinel(GLRestArgument a) {
    final value = a.argument.defaultValue?.value;
    return value is List || value is Map;
  }

  GLType _nonNull(GLType type) => type is GLListType ? GLListType(type.type, false) : GLType(type.tokenInfo, false);

  String _name(GLRestArgument a) => a.argument.codeName;

  bool _nullable(GLRestArgument a) => a.argument.type.nullable;

  String _toJson(String expr, GLType type, int index) {
    final convertible = _grammar.inputTypeRequiresProjection(type) || _grammar.isEnum(type.token);
    if (!convertible) return expr;
    if (type.isList) {
      final variable = 'e$index';
      final inner = _toJson(variable, type.inlineType, index + 1);
      return _cg.nullSafe(expr, _cg.listComprehension(expression: inner, variable: variable, iterable: expr), type.nullable);
    }
    return _cg.nullSafe(expr, '$expr.to_json()', type.nullable);
  }

  String _value(GLRestArgument a) => _toJson(_name(a), a.argument.type, 0);

  String _presentValue(GLRestArgument a) => _toJson(_name(a), _nonNull(a.argument.type), 0);

  String operationToMethod(GLRestOperation op) {
    return _cg.createMethod(
      async: true,
      methodName: op.field.codeName,
      arguments: _signature(op),
      returnType: _returnType(op),
      statements: [
        ..._sentinels(op),
        ..._bodyStatements(op),
        _cg.constDecl(_request, _requestExpression(op)),
        ..._execution(op),
      ],
    );
  }

  String _returnType(GLRestOperation op) {
    switch (op.responseKind) {
      case RestResponseKind.none:
        return 'None';
      case RestResponseKind.binary:
        return op.allowsEmptyBody ? 'Optional[GLDownload]' : 'GLDownload';
      case RestResponseKind.text:
      case RestResponseKind.json:
        return _serializer.serializeType(op.field.type);
    }
  }

  String _argumentType(GLRestArgument a) {
    final arg = a.argument;
    if (!_isUpload(a)) return _serializer.serializeType(arg.type);
    final base = arg.type.isList ? 'List[GLUpload]' : 'GLUpload';
    return arg.type.nullable ? 'Optional[$base]' : base;
  }

  List<String> _signature(GLRestOperation op) {
    final args = op.arguments.map((a) {
      final arg = a.argument;
      if (arg.defaultValue != null) {
        if (_hasSentinel(a)) {
          final type = arg.type.nullable ? _argumentType(a) : 'Optional[${_argumentType(a)}]';
          return '${arg.codeName}: $type = None';
        }
        return '${arg.codeName}: ${_argumentType(a)} = ${_serializer.serializeDefaultLiteral(arg.type, arg.defaultValue!.value)}';
      }
      return arg.type.nullable ? '${arg.codeName}: ${_argumentType(a)} = None' : '${arg.codeName}: ${_argumentType(a)}';
    }).toList();
    if (_hasProgress(op)) args.add('on_progress: Optional[UploadProgressCallback] = None');
    if (op.responseKind == RestResponseKind.binary) args.add('on_receive_progress: Optional[DownloadProgressCallback] = None');
    return ['self', if (args.isNotEmpty) '*', ...args];
  }

  List<String> _sentinels(GLRestOperation op) => [
        for (final a in op.arguments)
          if (a.argument.defaultValue != null && _hasSentinel(a))
            _cg.ifStatement(
              condition: '${_name(a)} is None',
              ifBlockStatements: [
                '${_name(a)} = ${_serializer.serializeDefaultLiteral(a.argument.type, a.argument.defaultValue!.value)}',
              ],
            ),
      ];

  String _requestExpression(GLRestOperation op) {
    final query = _entries(op, RestArgRole.query);
    return _cg.callExpression('RestRequest', [
      'method="${op.method.wireName}"',
      'path=${_pathExpression(op)}',
      'query=${_unpackedList(query)}',
      'headers=${_headers(op)}',
      if (op.bodyKind != RestBodyKind.none) 'body=$_body',
      if (_hasProgress(op)) 'on_send_progress=on_progress',
    ]);
  }

  String _unpackedList(List<String> items) => items.isEmpty ? '[]' : '[${items.map((e) => '*$e').join(', ')}]';

  String _pathExpression(GLRestOperation op) {
    final byName = {
      for (final a in op.arguments)
        if (a.role == RestArgRole.path) a.wireName!: a,
    };
    final buffer = StringBuffer();
    var last = 0;
    for (final m in restPlaceholder.allMatches(op.path)) {
      buffer.write(_escapeLiteral(op.path.substring(last, m.start)));
      buffer.write('{rest_encode(rest_text(${_value(byName[m.group(1)]!)}))}');
      last = m.end;
    }
    buffer.write(_escapeLiteral(op.path.substring(last)));
    return 'f"$buffer"';
  }

  String _escapeLiteral(String text) =>
      text.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('{', '{{').replaceAll('}', '}}');

  String _headers(GLRestOperation op) {
    final entries = <String>[
      '"Accept": "${op.accept}"',
      ..._contentTypeEntries(op),
      for (final a in op.arguments)
        if (a.role == RestArgRole.header) _headerEntry(a),
    ];
    return '{${entries.join(', ')}}';
  }

  List<String> _contentTypeEntries(GLRestOperation op) {
    switch (op.bodyKind) {
      case RestBodyKind.none:
      case RestBodyKind.multipart:
        return const [];
      case RestBodyKind.raw:
        final arg = op.arguments.firstWhere((a) => a.role == RestArgRole.body);
        final name = _name(arg);
        final value = op.contentType == null ? '$name.mime_type' : '"${op.contentType}"';
        return [
          arg.argument.type.nullable
              ? '**rest_header("Content-Type", ${_cg.ternaryOp(condition: '$name is None', positiveStatement: 'None', negativeStatement: value)})'
              : '"Content-Type": $value',
        ];
      case RestBodyKind.json:
      case RestBodyKind.form:
        final value = '"${op.contentType}"';
        return [
          _bodyMayBeNull(op)
              ? '**rest_header("Content-Type", ${_cg.ternaryOp(condition: '$_body is None', positiveStatement: 'None', negativeStatement: value)})'
              : '"Content-Type": $value',
        ];
    }
  }

  String _headerEntry(GLRestArgument a) {
    final value = _value(a);
    if (a.encoding == RestEncoding.spread) {
      return '**rest_headers($value, ${_nameMap(a.spreadFields)})';
    }
    return '**rest_header("${a.wireName}", $value)';
  }

  String _nameMap(Map<String, String> names) =>
      '{${names.entries.map((e) => '"${e.key}": "${e.value}"').join(', ')}}';

  List<String> _entries(GLRestOperation op, RestArgRole role) => [
        for (final a in op.arguments)
          if (a.role == role) _entry(a),
      ];

  String _entry(GLRestArgument a) {
    final value = _value(a);
    switch (a.encoding) {
      case RestEncoding.spread:
        return 'rest_spread_entries($value, ${_nameMap(a.spreadFields)}$_listOptions)';
      case RestEncoding.json:
        final encoded = _nullable(a)
            ? _cg.ternaryOp(
                condition: '${_name(a)} is None',
                positiveStatement: 'None',
                negativeStatement: 'rest_encode_json(${_presentValue(a)})')
            : 'rest_encode_json(${_presentValue(a)})';
        return 'rest_entries("${a.wireName}", $encoded)';
      case RestEncoding.flat:
      case null:
        return 'rest_entries("${a.wireName}", $value$_listOptions)';
    }
  }

  bool _bodyMayBeNull(GLRestOperation op) {
    if (op.bodyKind == RestBodyKind.form || op.bodyKind == RestBodyKind.multipart) return true;
    return op.arguments.firstWhere((a) => a.role == RestArgRole.body).argument.type.nullable;
  }

  List<String> _bodyStatements(GLRestOperation op) {
    switch (op.bodyKind) {
      case RestBodyKind.none:
        return const [];
      case RestBodyKind.json:
        final arg = op.arguments.firstWhere((a) => a.role == RestArgRole.body);
        return [_bodyDecl(_nullGuard(arg, 'RestJsonBody(rest_encode_json(${_presentValue(arg)}))'))];
      case RestBodyKind.raw:
        final arg = op.arguments.firstWhere((a) => a.role == RestArgRole.body);
        return [_bodyDecl(_nullGuard(arg, 'RestRawBody(${_name(arg)})'))];
      case RestBodyKind.form:
        return _collected(_entries(op, RestArgRole.field), 'RestFormBody($_fields)', _fields, 'List[Tuple[str, str]]');
      case RestBodyKind.multipart:
        return _collected(_partEntries(op), 'RestMultipartBody($_parts)', _parts, 'List[RestPart]');
    }
  }

  String _bodyDecl(String value) => _cg.constDecl(_body, value, type: 'Optional[RestBody]');

  String _nullGuard(GLRestArgument arg, String expression) {
    if (!arg.argument.type.nullable) return expression;
    return _cg.ternaryOp(condition: '${_name(arg)} is None', positiveStatement: 'None', negativeStatement: expression);
  }

  List<String> _collected(List<String> items, String body, String variable, String listType) {
    return [
      _cg.constDecl(variable, _unpackedList(items), type: listType),
      _bodyDecl(_cg.ternaryOp(condition: 'not $variable', positiveStatement: 'None', negativeStatement: body)),
    ];
  }

  List<String> _partEntries(GLRestOperation op) => [
        for (final a in op.arguments)
          if (a.role == RestArgRole.part) _partEntry(a),
      ];

  String _partEntry(GLRestArgument a) {
    final name = _name(a);
    String guarded(String present) => _nullable(a)
        ? _cg.ternaryOp(condition: '$name is None', positiveStatement: '[]', negativeStatement: present)
        : present;
    final wire = '"${a.wireName}"';
    if (_isUpload(a)) {
      if (a.argument.type.isList) {
        return '(${guarded('[RestPart(name=$wire, file=e) for e in $name]')})';
      }
      return '(${guarded('[RestPart(name=$wire, file=$name)]')})';
    }
    if (a.encoding == RestEncoding.json) {
      return '(${guarded('[RestPart(name=$wire, value=rest_encode_json(${_presentValue(a)}), mime_type="application/json")]')})';
    }
    return 'rest_parts(${_entry(a)})';
  }

  List<String> _execution(GLRestOperation op) {
    final invalidation = _invalidation(op);
    final path = _stringList(op.responsePathSegments);
    switch (op.responseKind) {
      case RestResponseKind.none:
        return ['await self.rest_void__($_request)', ...invalidation];
      case RestResponseKind.text:
        return [
          _cg.constDecl(_result, 'await self.${op.allowsEmptyBody ? 'rest_text_or_null__' : 'rest_text__'}($_request)'),
          ...invalidation,
          'return $_result',
        ];
      case RestResponseKind.binary:
        return [
          _cg.constDecl(_result, 'await self.rest_download__($_request, ${_bool(op.allowsEmptyBody)}, on_receive_progress)'),
          ...invalidation,
          'return $_result',
        ];
      case RestResponseKind.json:
        final decode = _serializer.callFromJsonValue(_json, op.field.type);
        if (op.cacheTtl > 0) return [_cachedReturn(op, path, decode)];
        return [
          _cg.constDecl(_json, 'await self.rest_json__($_request, $path, ${_bool(op.allowsEmptyBody)})'),
          _cg.constDecl(_result, decode),
          ...invalidation,
          'return $_result',
        ];
    }
  }

  String _bool(bool value) => value ? 'True' : 'False';

  String _stringList(List<String> items) => '[${items.map((e) => '"$e"').join(', ')}]';

  String _cachedReturn(GLRestOperation op, String path, String decode) {
    final variables = [
      for (final a in op.arguments)
        if (!_isUpload(a)) '"${a.name}": ${_value(a)}',
    ];
    return 'return await ${_cg.callExpression('self.rest_cached__', [
      '"${op.name}"',
      '{${variables.join(', ')}}',
      '${op.cacheTtl}',
      _stringList(op.cacheTags),
      _bool(op.staleIfOffline),
      'lambda: self.rest_json__($_request, $path, ${_bool(op.allowsEmptyBody)})',
      'lambda $_json: $decode',
    ])}';
  }

  List<String> _invalidation(GLRestOperation op) {
    if (op.type != GLQueryType.mutation) return const [];
    if (op.invalidatesAll) return ['await self.gl_store__.invalidate_all()'];
    if (op.invalidateTags.isNotEmpty) return ['await self.invalidate_by_tags(${_stringList(op.invalidateTags)})'];
    return const [];
  }
}
