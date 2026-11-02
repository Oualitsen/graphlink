import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
import 'package:graphlink/src/typescript_code_gen_utils.dart';

const _request = 'gl_request__';
const _body = 'gl_body__';
const _json = 'gl_json__';
const _result = 'gl_result__';
const _fields = 'gl_fields__';
const _parts = 'gl_parts__';

class TypeScriptRestOperationSerializer {
  final GLParser _grammar;
  final TypeScriptCodeGenUtils _cg;
  final TypeScriptSerializer _serializer;
  final bool observables;
  final bool commaLists;
  final bool bracketNesting;

  TypeScriptRestOperationSerializer(
    this._grammar,
    this._cg,
    this._serializer, {
    this.observables = false,
    this.commaLists = false,
    this.bracketNesting = false,
  });

  String get _listOptions {
    final options = [if (bracketNesting) 'bracket: true', if (commaLists) 'comma: true'];
    return options.isEmpty ? '' : ', { ${options.join(', ')} }';
  }

  bool _isUpload(GLRestArgument a) => _grammar.uploadScalarNames.contains(a.argument.type.firstType.token);

  bool _hasProgress(GLRestOperation op) => op.bodyKind == RestBodyKind.raw || op.bodyKind == RestBodyKind.multipart;

  bool _hasDefault(GLRestArgument a) => a.argument.defaultValue != null;

  String _ref(GLRestArgument a) => _hasDefault(a) ? 'gl_${a.argument.codeName}__' : 'args.${a.argument.codeName}';

  GLType _nonNull(GLType type) => type is GLListType ? GLListType(type.type, false) : GLType(type.tokenInfo, false);

  String _value(GLRestArgument a) => _serializer.callToJson(_ref(a), a.argument.type);

  String _presentValue(GLRestArgument a) => _serializer.callToJson(_ref(a), _nonNull(a.argument.type));

  bool _nullable(GLRestArgument a) => a.argument.type.nullable && !_hasDefault(a);

  String operationToMethod(GLRestOperation op) {
    final returnType = _returnType(op);
    final signature = _signature(op);
    final statements = [
      ..._defaults(op),
      ..._bodyStatements(op),
      _cg.constDecl(_request, _requestExpression(op), type: 'RestRequest'),
      ..._execution(op),
    ];
    if (observables) {
      final wrapped = _cg.observableExpr(returnType, [
        '${_cg.iife(statements).replaceFirst(RegExp(r';$'), '')}.then(',
        '  (gl_value__) => ${_cg.block(['subscriber.next(gl_value__);', 'subscriber.complete();'])},',
        '  (gl_error__) => subscriber.error(gl_error__),',
        ');',
      ]);
      return _cg.createMethod(
        returnType: 'Observable<$returnType>',
        methodName: op.field.codeName,
        arguments: signature,
        statements: ['return $wrapped;'],
      );
    }
    return _cg.createMethod(
      returnType: returnType,
      methodName: op.field.codeName,
      arguments: signature,
      async: true,
      statements: statements,
    );
  }

  String _returnType(GLRestOperation op) {
    switch (op.responseKind) {
      case RestResponseKind.none:
        return 'void';
      case RestResponseKind.binary:
        return op.allowsEmptyBody ? 'GLDownload | null' : 'GLDownload';
      case RestResponseKind.text:
      case RestResponseKind.json:
        return _serializer.serializeType(op.field.type);
    }
  }

  List<String> _signature(GLRestOperation op) {
    final members = op.arguments.map((a) {
      final arg = a.argument;
      final type = _isUpload(a)
          ? '${arg.type.isList ? 'GLUpload[]' : 'GLUpload'}${arg.type.nullable ? ' | null' : ''}'
          : _serializer.serializeType(arg.type);
      final optional = (arg.type.nullable || _hasDefault(a)) ? '?' : '';
      return '${arg.codeName}$optional: $type;';
    }).toList();
    return [
      if (members.isNotEmpty) 'args: ${_cg.block(members)}',
      if (_hasProgress(op)) 'onProgress?: UploadProgressCallback',
      if (op.responseKind == RestResponseKind.binary) 'onReceiveProgress?: DownloadProgressCallback',
    ];
  }

  List<String> _defaults(GLRestOperation op) {
    return [
      for (final a in op.arguments)
        if (_hasDefault(a))
          _cg.constDecl(
            _ref(a),
            'args.${a.argument.codeName} ?? ${_serializer.serializeDefaultLiteral(a.argument.type, a.argument.defaultValue!.value)}',
          ),
    ];
  }

  String _requestExpression(GLRestOperation op) {
    final query = _entries(op, RestArgRole.query);
    return _cg.block([
      "method: '${op.method.wireName}',",
      'path: ${_pathExpression(op)},',
      if (query.isNotEmpty) 'query: ${_cg.arrayLiteral(query)},' else 'query: [],',
      'headers: ${_headers(op)},',
      if (op.bodyKind != RestBodyKind.none) 'body: $_body ?? undefined,',
      if (_hasProgress(op)) 'onSendProgress: onProgress,',
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
      buffer.write('\${restEncode(String(${_value(byName[m.group(1)]!)}))}');
      last = m.end;
    }
    buffer.write(_escapeLiteral(op.path.substring(last)));
    return '`$buffer`';
  }

  String _inlineList(List<String> items) => '[${items.map((e) => "'$e'").join(', ')}]';

  String _escapeLiteral(String text) => text.replaceAll(r'\', r'\\').replaceAll('`', r'\`').replaceAll(r'$', r'\$');

  String _headers(GLRestOperation op) {
    final entries = <String>[
      "'Accept': '${op.accept}',",
      ..._contentTypeEntries(op),
      for (final a in op.arguments)
        if (a.role == RestArgRole.header) _headerEntry(a),
    ];
    return _cg.block(entries);
  }

  List<String> _contentTypeEntries(GLRestOperation op) {
    switch (op.bodyKind) {
      case RestBodyKind.none:
      case RestBodyKind.multipart:
        return const [];
      case RestBodyKind.raw:
        final arg = op.arguments.firstWhere((a) => a.role == RestArgRole.body);
        final ref = _ref(arg);
        final value = op.contentType == null ? '$ref.mimeType' : "'${op.contentType}'";
        return [
          arg.argument.type.nullable
              ? "...restHeader('Content-Type', ${_cg.ternaryOp(condition: '$ref == null', positiveStatement: 'null', negativeStatement: value)}),"
              : "'Content-Type': $value,",
        ];
      case RestBodyKind.json:
      case RestBodyKind.form:
        final value = "'${op.contentType}'";
        return [
          _bodyMayBeNull(op)
              ? "...restHeader('Content-Type', ${_cg.ternaryOp(condition: '$_body === null', positiveStatement: 'null', negativeStatement: value)}),"
              : "'Content-Type': $value,",
        ];
    }
  }

  String _headerEntry(GLRestArgument a) {
    final value = _value(a);
    if (a.encoding == RestEncoding.spread) {
      return '...restHeaders($value, ${_nameMap(a.spreadFields)}),';
    }
    return "...restHeader('${a.wireName}', $value),";
  }

  String _nameMap(Map<String, String> names) =>
      '{ ${names.entries.map((e) => "'${e.key}': '${e.value}'").join(', ')} }';

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
        return '...restSpreadEntries($value, ${_nameMap(a.spreadFields)}$_listOptions)';
      case RestEncoding.json:
        final encoded = _nullable(a)
            ? _cg.ternaryOp(
                condition: '${_ref(a)} == null',
                positiveStatement: 'null',
                negativeStatement: 'JSON.stringify(${_presentValue(a)})')
            : 'JSON.stringify(${_presentValue(a)})';
        return "...restEntries('${a.wireName}', $encoded)";
      case RestEncoding.flat:
      case null:
        return "...restEntries('${a.wireName}', $value$_listOptions)";
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
        return [
          _cg.constDecl(_body, _nullGuard(arg, "{ kind: 'json', json: JSON.stringify(${_presentValue(arg)}) }"),
              type: 'RestBody | null'),
        ];
      case RestBodyKind.raw:
        final arg = op.arguments.firstWhere((a) => a.role == RestArgRole.body);
        return [
          _cg.constDecl(_body, _nullGuard(arg, "{ kind: 'raw', upload: ${_ref(arg)} }"), type: 'RestBody | null'),
        ];
      case RestBodyKind.form:
        return _collected(
            _entries(op, RestArgRole.field), "{ kind: 'form', fields: $_fields }", _fields, 'Array<[string, string]>');
      case RestBodyKind.multipart:
        return _collected(_partEntries(op), "{ kind: 'multipart', parts: $_parts }", _parts, 'RestPart[]');
    }
  }

  String _nullGuard(GLRestArgument arg, String expression) {
    if (!arg.argument.type.nullable) return expression;
    return _cg.ternaryOp(condition: '${_ref(arg)} == null', positiveStatement: 'null', negativeStatement: expression);
  }

  List<String> _collected(List<String> items, String body, String variable, String listType) {
    return [
      _cg.constDecl(variable, _cg.arrayLiteral(items), type: listType),
      _cg.constDecl(
        _body,
        _cg.ternaryOp(condition: '$variable.length === 0', positiveStatement: 'null', negativeStatement: body),
        type: 'RestBody | null',
      ),
    ];
  }

  List<String> _partEntries(GLRestOperation op) {
    return [
      for (final a in op.arguments)
        if (a.role == RestArgRole.part) _partEntry(a),
    ];
  }

  String _partEntry(GLRestArgument a) {
    final ref = _ref(a);
    final nullable = _nullable(a);
    if (_isUpload(a)) {
      final String present;
      if (a.argument.type.isList) {
        present = "...$ref.map((e) => ({ name: '${a.wireName}', file: e }))";
        return nullable ? '...($ref == null ? [] : [$present])' : present;
      }
      final part = "{ name: '${a.wireName}', file: $ref }";
      return nullable ? '...($ref == null ? [] : [$part])' : part;
    }
    if (a.encoding == RestEncoding.json) {
      final part = "{ name: '${a.wireName}', value: JSON.stringify(${_presentValue(a)}), mimeType: 'application/json' }";
      return nullable ? '...($ref == null ? [] : [$part])' : part;
    }
    return '...restParts(${_entry(a).replaceFirst('...', '')})';
  }

  List<String> _execution(GLRestOperation op) {
    final invalidation = _invalidation(op);
    final inlinePath = _inlineList(op.responsePathSegments);
    switch (op.responseKind) {
      case RestResponseKind.none:
        return ['await this.restVoid__($_request);', ...invalidation];
      case RestResponseKind.text:
        return [
          _cg.constDecl(_result, 'await this.${op.allowsEmptyBody ? 'restTextOrNull__' : 'restText__'}($_request)'),
          ...invalidation,
          'return $_result;',
        ];
      case RestResponseKind.binary:
        final call = 'await this.restDownload__($_request, ${op.allowsEmptyBody}, onReceiveProgress)';
        final download = op.allowsEmptyBody ? call : '($call)!';
        return [
          _cg.constDecl(_result, download),
          ...invalidation,
          'return $_result;',
        ];
      case RestResponseKind.json:
        final decode = _serializer.callFromJson(_json, op.field.type);
        if (op.cacheTtl > 0) {
          return [_cachedReturn(op, inlinePath, decode)];
        }
        return [
          _cg.constDecl(_json, 'await this.restJson__($_request, $inlinePath, ${op.allowsEmptyBody})'),
          if (invalidation.isEmpty)
            'return $decode;'
          else ...[
            _cg.constDecl(_result, decode),
            ...invalidation,
            'return $_result;',
          ],
        ];
    }
  }

  String _cachedReturn(GLRestOperation op, String path, String decode) {
    final variables = _cg.block([
      for (final a in op.arguments)
        if (!_isUpload(a)) "'${a.name}': ${_value(a)},",
    ]);
    final tags = _inlineList(op.cacheTags);
    return 'return ${_cg.callExpression('this.restCached__<${_returnType(op)}>', [
      "'${op.name}'",
      variables,
      '${op.cacheTtl}',
      tags,
      '${op.staleIfOffline}',
      '() => this.restJson__($_request, $path, ${op.allowsEmptyBody})',
      '($_json: unknown) => $decode',
    ])};';
  }

  List<String> _invalidation(GLRestOperation op) {
    if (op.type != GLQueryType.mutation) return const [];
    if (op.invalidatesAll) return ['await this.gl_store__.invalidateAll();'];
    if (op.invalidateTags.isNotEmpty) {
      return ['await this._invalidateByTags(${_inlineList(op.invalidateTags)});'];
    }
    return const [];
  }
}
