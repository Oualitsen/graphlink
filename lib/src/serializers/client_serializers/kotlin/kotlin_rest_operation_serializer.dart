import 'package:graphlink/src/kotlin_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_serializer.dart';

const _request = 'glRequest__';
const _body = 'glBody__';
const _json = 'glJson__';
const _result = 'glResult__';
const _fields = 'glFields__';
const _parts = 'glParts__';

class KotlinRestOperationSerializer {
  final GLParser _grammar;
  final KotlinCodeGenUtils _cg;
  final KotlinSerializer _serializer;
  final bool commaLists;
  final bool bracketNesting;

  KotlinRestOperationSerializer(
    this._grammar,
    this._cg,
    this._serializer, {
    this.commaLists = false,
    this.bracketNesting = false,
  });

  String get _listOptions => [if (bracketNesting) 'bracket = true', if (commaLists) 'comma = true']
      .map((e) => ', $e')
      .join();

  bool _isUpload(GLRestArgument a) => _grammar.uploadScalarNames.contains(a.argument.type.firstType.token);

  bool _hasProgress(GLRestOperation op) => op.bodyKind == RestBodyKind.raw || op.bodyKind == RestBodyKind.multipart;

  GLType _nonNull(GLType type) => type is GLListType ? GLListType(type.type, false) : GLType(type.tokenInfo, false);

  String _name(GLRestArgument a) => a.argument.codeName;

  bool _nullable(GLRestArgument a) => a.argument.type.nullable;

  String _value(GLRestArgument a) => _serializer.callToJson(_current, a.argument.type, _name(a), 0);

  String _presentValue(GLRestArgument a) =>
      _serializer.callToJson(_current, _nonNull(a.argument.type), _name(a), 0);

  late GLField _current;

  String operationToMethod(GLRestOperation op) {
    _current = op.field;
    return _cg.suspendFun(
      name: op.field.codeName,
      arguments: _signature(op),
      returnType: _returnType(op),
      statements: [
        ..._bodyStatements(op),
        _cg.constDecl(_request, _requestExpression(op)),
        ..._execution(op),
      ],
    );
  }

  String _returnType(GLRestOperation op) {
    switch (op.responseKind) {
      case RestResponseKind.none:
        return 'Unit';
      case RestResponseKind.binary:
        return op.allowsEmptyBody ? 'GLDownload?' : 'GLDownload';
      case RestResponseKind.text:
      case RestResponseKind.json:
        return _serializer.serializeType(op.field.type);
    }
  }

  List<String> _signature(GLRestOperation op) {
    final args = op.arguments.map((a) {
      final arg = a.argument;
      final nullSuffix = arg.type.nullable ? '?' : '';
      final type = _isUpload(a)
          ? '${arg.type.isList ? 'List<GLUpload>' : 'GLUpload'}$nullSuffix'
          : _serializer.serializeType(arg.type);
      if (arg.defaultValue != null) {
        return '${arg.codeName}: $type = ${_serializer.serializeDefaultLiteral(arg.type, arg.defaultValue!.value)}';
      }
      return arg.type.nullable ? '${arg.codeName}: $type = null' : '${arg.codeName}: $type';
    }).toList();
    if (_hasProgress(op)) args.add('onProgress: UploadProgressCallback? = null');
    if (op.responseKind == RestResponseKind.binary) args.add('onReceiveProgress: DownloadProgressCallback? = null');
    return args;
  }

  String _requestExpression(GLRestOperation op) {
    final query = _entries(op, RestArgRole.query);
    return _cg.callExpression('RestRequest', [
      'method = "${op.method.wireName}"',
      'path = ${_pathExpression(op)}',
      'query = ${query.isEmpty ? 'emptyList()' : query.join(' + ')}',
      'headers = ${_headers(op)}',
      if (op.bodyKind != RestBodyKind.none) 'body = $_body',
      if (_hasProgress(op)) 'onSendProgress = onProgress',
    ]);
  }

  String _pathExpression(GLRestOperation op) {
    final byName = {
      for (final a in op.arguments)
        if (a.role == RestArgRole.path) a.wireName!: a,
    };
    final buffer = StringBuffer();
    var last = 0;
    for (final m in restPlaceholder.allMatches(op.path)) {
      buffer.write(_escapeLiteral(op.path.substring(last, m.start)));
      buffer.write('\${restEncode(${_value(byName[m.group(1)]!)}.toString())}');
      last = m.end;
    }
    buffer.write(_escapeLiteral(op.path.substring(last)));
    return '"$buffer"';
  }

  String _escapeLiteral(String text) => text.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll(r'$', r'\$');

  String _headers(GLRestOperation op) {
    final parts = <String>[
      'mapOf("Accept" to "${op.accept}")',
      ..._contentTypeEntries(op),
      for (final a in op.arguments)
        if (a.role == RestArgRole.header) _headerEntry(a),
    ];
    return parts.join(' + ');
  }

  List<String> _contentTypeEntries(GLRestOperation op) {
    switch (op.bodyKind) {
      case RestBodyKind.none:
      case RestBodyKind.multipart:
        return const [];
      case RestBodyKind.raw:
        final arg = op.arguments.firstWhere((a) => a.role == RestArgRole.body);
        final name = _name(arg);
        final value = op.contentType == null ? '$name.mimeType' : '"${op.contentType}"';
        return [
          arg.argument.type.nullable
              ? 'restHeader("Content-Type", ${_cg.ternaryOp(condition: '$name == null', positiveStatement: 'null', negativeStatement: value)})'
              : 'mapOf("Content-Type" to $value)',
        ];
      case RestBodyKind.json:
      case RestBodyKind.form:
        final value = '"${op.contentType}"';
        return [
          _bodyMayBeNull(op)
              ? 'restHeader("Content-Type", ${_cg.ternaryOp(condition: '$_body == null', positiveStatement: 'null', negativeStatement: value)})'
              : 'mapOf("Content-Type" to $value)',
        ];
    }
  }

  String _headerEntry(GLRestArgument a) {
    final value = _value(a);
    if (a.encoding == RestEncoding.spread) {
      return 'restHeaders($value, ${_nameMap(a.spreadFields)})';
    }
    return 'restHeader("${a.wireName}", $value)';
  }

  String _nameMap(Map<String, String> names) =>
      'mapOf(${names.entries.map((e) => '"${e.key}" to "${e.value}"').join(', ')})';

  List<String> _entries(GLRestOperation op, RestArgRole role) {
    return [
      for (final a in op.arguments)
        if (a.role == role) _entry(a),
    ];
  }

  String _entry(GLRestArgument a) {
    final value = _value(a);
    switch (a.encoding) {
      case RestEncoding.spread:
        return 'restSpreadEntries($value, ${_nameMap(a.spreadFields)}$_listOptions)';
      case RestEncoding.json:
        final encoded = _nullable(a)
            ? _cg.ternaryOp(
                condition: '${_name(a)} == null',
                positiveStatement: 'null',
                negativeStatement: 'restEncodeJson(${_presentValue(a)})')
            : 'restEncodeJson(${_presentValue(a)})';
        return 'restEntries("${a.wireName}", $encoded)';
      case RestEncoding.flat:
      case null:
        return 'restEntries("${a.wireName}", $value$_listOptions)';
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
        return [_bodyDecl(_nullGuard(arg, 'RestJsonBody(restEncodeJson(${_presentValue(arg)}))'))];
      case RestBodyKind.raw:
        final arg = op.arguments.firstWhere((a) => a.role == RestArgRole.body);
        return [_bodyDecl(_nullGuard(arg, 'RestRawBody(${_name(arg)})'))];
      case RestBodyKind.form:
        return _collected(
            _entries(op, RestArgRole.field), 'RestFormBody($_fields)', _fields, 'Pair<String, String>');
      case RestBodyKind.multipart:
        return _collected(_partEntries(op), 'RestMultipartBody($_parts)', _parts, 'RestPart');
    }
  }

  String _bodyDecl(String value) => _cg.constDecl(_body, value, type: 'RestBody?');

  String _nullGuard(GLRestArgument arg, String expression) {
    if (!arg.argument.type.nullable) return expression;
    return _cg.ternaryOp(
        condition: '${_name(arg)} == null', positiveStatement: 'null', negativeStatement: expression);
  }

  List<String> _collected(List<String> items, String body, String variable, String elementType) {
    return [
      _cg.constDecl(variable, items.isEmpty ? 'emptyList<$elementType>()' : items.join(' + '), type: 'List<$elementType>'),
      _bodyDecl(_cg.ternaryOp(condition: '$variable.isEmpty()', positiveStatement: 'null', negativeStatement: body)),
    ];
  }

  List<String> _partEntries(GLRestOperation op) {
    return [
      for (final a in op.arguments)
        if (a.role == RestArgRole.part) _partEntry(a),
    ];
  }

  String _partEntry(GLRestArgument a) {
    final name = _name(a);
    String guarded(String present) => _nullable(a)
        ? '(${_cg.ternaryOp(condition: '$name == null', positiveStatement: 'emptyList<RestPart>()', negativeStatement: present)})'
        : present;
    if (_isUpload(a)) {
      if (a.argument.type.isList) {
        return guarded('$name.map { RestPart.file("${a.wireName}", it) }');
      }
      return guarded('listOf(RestPart.file("${a.wireName}", $name))');
    }
    if (a.encoding == RestEncoding.json) {
      return guarded('listOf(RestPart.text("${a.wireName}", restEncodeJson(${_presentValue(a)}), "application/json"))');
    }
    return 'restParts(${_entry(a)})';
  }

  List<String> _execution(GLRestOperation op) {
    final invalidation = _invalidation(op);
    final path = _listOf(op.responsePathSegments);
    switch (op.responseKind) {
      case RestResponseKind.none:
        return ['restVoid($_request)', ...invalidation];
      case RestResponseKind.text:
        return [
          _cg.constDecl(_result, '${op.allowsEmptyBody ? 'restTextOrNull' : 'restText'}($_request)'),
          ...invalidation,
          'return $_result',
        ];
      case RestResponseKind.binary:
        final call = 'restDownload($_request, ${op.allowsEmptyBody}, onReceiveProgress)';
        return [
          _cg.constDecl(_result, op.allowsEmptyBody ? call : '$call!!'),
          ...invalidation,
          'return $_result',
        ];
      case RestResponseKind.json:
        final decode = _serializer.fromJsonValueExpr(_json, op.field.type);
        if (op.cacheTtl > 0) {
          return [_cachedReturn(op, path, decode)];
        }
        return [
          _cg.constDecl(_json, 'restJson($_request, $path, ${op.allowsEmptyBody})'),
          _cg.constDecl(_result, decode),
          ...invalidation,
          'return $_result',
        ];
    }
  }

  String _listOf(List<String> items) => items.isEmpty ? 'emptyList()' : 'listOf(${items.map((e) => '"$e"').join(', ')})';

  String _cachedReturn(GLRestOperation op, String path, String decode) {
    final variables = [
      for (final a in op.arguments)
        if (!_isUpload(a)) '"${a.name}" to ${_value(a)}',
    ];
    return 'return ${_cg.callExpression('restCached<${_returnType(op)}>', [
      '"${op.name}"',
      variables.isEmpty ? 'emptyMap()' : 'mapOf(${variables.join(', ')})',
      '${op.cacheTtl}L',
      _listOf(op.cacheTags),
      '${op.staleIfOffline}',
      '{ restJson($_request, $path, ${op.allowsEmptyBody}) }',
      '{ $_json -> $decode }',
    ])}';
  }

  List<String> _invalidation(GLRestOperation op) {
    if (op.type != GLQueryType.mutation) return const [];
    if (op.invalidatesAll) return ['store.invalidateAll()'];
    if (op.invalidateTags.isNotEmpty) {
      return ['invalidateByTags(${_listOf(op.invalidateTags)})'];
    }
    return const [];
  }
}
