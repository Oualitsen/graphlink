import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/serializers/swift/swift_serializer.dart';
import 'package:graphlink/src/swift_code_gen_utils.dart';

const _request = 'glRequest__';
const _body = 'glBody__';
const _json = 'glJson__';
const _result = 'glResult__';
const _fields = 'glFields__';
const _parts = 'glParts__';

class SwiftRestOperationSerializer {
  final GLParser _grammar;
  final SwiftCodeGenUtils _cg;
  final SwiftSerializer _serializer;
  final bool commaLists;
  final bool bracketNesting;

  SwiftRestOperationSerializer(
    this._grammar,
    this._cg,
    this._serializer, {
    this.commaLists = false,
    this.bracketNesting = false,
  });

  String get _listOptions =>
      [if (bracketNesting) 'bracket: true', if (commaLists) 'comma: true'].map((e) => ', $e').join();

  bool _isUpload(GLRestArgument a) => _grammar.uploadScalarNames.contains(a.argument.type.firstType.token);

  bool _hasProgress(GLRestOperation op) => op.bodyKind == RestBodyKind.raw || op.bodyKind == RestBodyKind.multipart;

  String _name(GLRestArgument a) => a.argument.codeName;

  bool _nullable(GLRestArgument a) => a.argument.type.nullable;

  String _toJson(String variable, GLType type, int depth) {
    if (type.isList) {
      final inner = type.inlineType;
      final name = 'e$depth';
      final innerExpr = _toJson(name, inner, depth + 1);
      if (name == innerExpr) return SwiftCodeGenUtils.safeCall(variable, 'map { \$0 as Any? }', type.nullable);
      return SwiftCodeGenUtils.mapCall(
        receiver: variable,
        param: name,
        body: innerExpr,
        chainThroughOptional: type.nullable,
      );
    }
    if (_grammar.isEnum(type.token) || _grammar.isInput(type.token)) {
      return SwiftCodeGenUtils.safeCall(variable, 'toJson()', type.nullable);
    }
    return variable;
  }

  String _value(GLRestArgument a) => _toJson(_name(a), a.argument.type, 0);

  String operationToMethod(GLRestOperation op) {
    final statements = [
      ..._bodyStatements(op),
      _requestDecl(op),
      ..._execution(op),
    ];
    final returns = _returnType(op) == 'Void' ? '' : ' -> ${_returnType(op)}';
    return 'public func ${op.field.codeName}${_cg.parentheses(_signature(op))} async throws$returns ${_cg.block(statements)}';
  }

  String _requestDecl(GLRestOperation op) {
    final expression = _requestExpression(op);
    return _cg.constDecl(_request, expression.contains('restEncodeJson') ? 'try $expression' : expression);
  }

  String _returnType(GLRestOperation op) {
    switch (op.responseKind) {
      case RestResponseKind.none:
        return 'Void';
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
      final type = _isUpload(a)
          ? '${arg.type.isList ? '[GLUpload]' : 'GLUpload'}${arg.type.nullable ? '?' : ''}'
          : _serializer.serializeType(arg.type);
      if (arg.defaultValue != null) {
        return '${arg.codeName}: $type = ${_serializer.serializeDefaultLiteral(arg.type, arg.defaultValue!.value)}';
      }
      return arg.type.nullable ? '${arg.codeName}: $type = nil' : '${arg.codeName}: $type';
    }).toList();
    if (_hasProgress(op)) args.add('onProgress: UploadProgressCallback? = nil');
    if (op.responseKind == RestResponseKind.binary) args.add('onReceiveProgress: DownloadProgressCallback? = nil');
    return args;
  }

  String _requestExpression(GLRestOperation op) {
    final query = _entries(op, RestArgRole.query);
    return _cg.callExpression('RestRequest', [
      'method: "${op.method.wireName}"',
      'path: ${_pathExpression(op)}',
      'query: ${query.isEmpty ? '[]' : query.join(' + ')}',
      'headers: ${_headers(op)}',
      if (op.bodyKind != RestBodyKind.none) 'body: $_body',
      if (_hasProgress(op)) 'onSendProgress: onProgress',
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
      buffer.write(op.path.substring(last, m.start).escapeForSwiftStringLiteral());
      buffer.write('\\(restPath(${_value(byName[m.group(1)]!)}))');
      last = m.end;
    }
    buffer.write(op.path.substring(last).escapeForSwiftStringLiteral());
    return '"$buffer"';
  }

  String _headers(GLRestOperation op) {
    final parts = <String>[
      '["Accept": "${op.accept}"]',
      ..._contentTypeEntries(op),
      for (final a in op.arguments)
        if (a.role == RestArgRole.header) _headerEntry(a),
    ];
    return 'restHeaderSet(${parts.join(', ')})';
  }

  List<String> _contentTypeEntries(GLRestOperation op) {
    switch (op.bodyKind) {
      case RestBodyKind.none:
      case RestBodyKind.multipart:
        return const [];
      case RestBodyKind.raw:
        final arg = op.arguments.firstWhere((a) => a.role == RestArgRole.body);
        final name = _name(arg);
        final value = op.contentType == null ? '$name${arg.argument.type.nullable ? '!' : ''}.mimeType' : '"${op.contentType}"';
        return [
          arg.argument.type.nullable
              ? 'restHeader("Content-Type", ${_cg.ternaryOp(condition: '$name == nil', positiveStatement: 'nil', negativeStatement: value)})'
              : '["Content-Type": $value]',
        ];
      case RestBodyKind.json:
      case RestBodyKind.form:
        final value = '"${op.contentType}"';
        return [
          _bodyMayBeNull(op)
              ? 'restHeader("Content-Type", ${_cg.ternaryOp(condition: '$_body == nil', positiveStatement: 'nil', negativeStatement: value)})'
              : '["Content-Type": $value]',
        ];
    }
  }

  String _headerEntry(GLRestArgument a) {
    final value = _value(a);
    if (a.encoding == RestEncoding.spread) {
      return 'restHeaders($value, ${_nameList(a.spreadFields)})';
    }
    return 'restHeader("${a.wireName}", $value)';
  }

  String _nameList(Map<String, String> names) =>
      '[${names.entries.map((e) => '("${e.key}", "${e.value}")').join(', ')}]';

  List<String> _entries(GLRestOperation op, RestArgRole role) => [
        for (final a in op.arguments)
          if (a.role == role) _entry(a),
      ];

  String _entry(GLRestArgument a) {
    final value = _value(a);
    switch (a.encoding) {
      case RestEncoding.spread:
        return 'restSpreadEntries($value, ${_nameList(a.spreadFields)}$_listOptions)';
      case RestEncoding.json:
        final encoded = _nullable(a)
            ? _cg.ternaryOp(
                condition: '${_name(a)} == nil',
                positiveStatement: 'nil',
                negativeStatement: 'restEncodeJsonString($value)')
            : 'restEncodeJsonString($value)';
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
        return [_bodyDecl(_nullGuard(arg, 'RestBody.json(restEncodeJson(${_value(arg)}))'), throwing: true)];
      case RestBodyKind.raw:
        final arg = op.arguments.firstWhere((a) => a.role == RestArgRole.body);
        return [_bodyDecl(_nullGuard(arg, 'RestBody.raw(${_name(arg)}${arg.argument.type.nullable ? '!' : ''})'))];
      case RestBodyKind.form:
        return _collected(_entries(op, RestArgRole.field), '.form($_fields)', _fields, '[RestEntry]');
      case RestBodyKind.multipart:
        return _collected(_partEntries(op), '.multipart($_parts)', _parts, '[RestPart]');
    }
  }

  String _bodyDecl(String value, {bool throwing = false}) =>
      _cg.constDecl(_body, throwing ? 'try $value' : value, type: 'RestBody?');

  String _nullGuard(GLRestArgument arg, String expression) {
    if (!arg.argument.type.nullable) return expression;
    return _cg.ternaryOp(condition: '${_name(arg)} == nil', positiveStatement: 'nil', negativeStatement: expression);
  }

  List<String> _collected(List<String> items, String body, String variable, String listType) {
    final joined = items.join(' + ');
    final declaration = items.isEmpty ? '[]' : (joined.contains('restEncodeJson') ? 'try $joined' : joined);
    return [
      _cg.constDecl(variable, declaration, type: listType),
      _bodyDecl(_cg.ternaryOp(condition: '$variable.isEmpty', positiveStatement: 'nil', negativeStatement: body)),
    ];
  }

  List<String> _partEntries(GLRestOperation op) => [
        for (final a in op.arguments)
          if (a.role == RestArgRole.part) _partEntry(a),
      ];

  String _partEntry(GLRestArgument a) {
    final name = _name(a);
    final wire = '"${a.wireName}"';
    if (_isUpload(a)) {
      if (a.argument.type.isList) {
        return '${_nullable(a) ? '($name ?? [])' : name}.map { RestPart(name: $wire, file: \$0) }';
      }
      return _nullable(a)
          ? '($name.map { [RestPart(name: $wire, file: \$0)] } ?? [])'
          : '[RestPart(name: $wire, file: $name)]';
    }
    if (a.encoding == RestEncoding.json) {
      final part = '[RestPart(name: $wire, value: restEncodeJsonString(${_value(a)}), mimeType: "application/json")]';
      return _nullable(a) ? '(${_cg.ternaryOp(condition: '$name == nil', positiveStatement: '[]', negativeStatement: part)})' : part;
    }
    return 'restParts(${_entry(a)})';
  }

  String _decode(GLRestOperation op, String value) => _serializer.fromJsonValueExpr(value, op.field.type);

  List<String> _execution(GLRestOperation op) {
    final invalidation = _invalidation(op);
    final path = _stringList(op.responsePathSegments);
    switch (op.responseKind) {
      case RestResponseKind.none:
        return ['try await restVoid($_request)', ...invalidation];
      case RestResponseKind.text:
        return [
          _cg.constDecl(_result, 'try await ${op.allowsEmptyBody ? 'restTextOrNull' : 'restText'}($_request)'),
          ...invalidation,
          'return $_result',
        ];
      case RestResponseKind.binary:
        final call = op.allowsEmptyBody ? 'restDownload' : 'restDownloadRequired';
        return [
          _cg.constDecl(_result, 'try await $call($_request, onProgress: onReceiveProgress)'),
          ...invalidation,
          'return $_result',
        ];
      case RestResponseKind.json:
        if (op.cacheTtl > 0) return [_cachedReturn(op, path)];
        return [
          _cg.constDecl(_json, 'try await restJson($_request, path: $path, allowEmpty: ${op.allowsEmptyBody})'),
          _cg.constDecl(_result, _decode(op, _json)),
          ...invalidation,
          'return $_result',
        ];
    }
  }

  String _stringList(List<String> items) => '[${items.map((e) => '"$e"').join(', ')}]';

  String _cachedReturn(GLRestOperation op, String path) {
    final variables = [
      for (final a in op.arguments)
        if (!_isUpload(a)) '"${a.name}": ${_value(a)}',
    ];
    return 'return try await ${_cg.callExpression('restCached', [
      '"${op.name}"',
      variables.isEmpty ? '[:]' : '[${variables.join(', ')}]',
      'ttl: ${op.cacheTtl}',
      'tags: ${_stringList(op.cacheTags)}',
      'staleIfOffline: ${op.staleIfOffline}',
      'fetch: { try await self.restJson($_request, path: $path, allowEmpty: ${op.allowsEmptyBody}) }',
      'decode: { $_json in ${_decode(op, _json)} }',
    ])}';
  }

  List<String> _invalidation(GLRestOperation op) {
    if (op.type != GLQueryType.mutation) return const [];
    if (op.invalidatesAll) return ['await store.invalidateAll()'];
    if (op.invalidateTags.isNotEmpty) return ['try await invalidateByTags(${_stringList(op.invalidateTags)})'];
    return const [];
  }
}
