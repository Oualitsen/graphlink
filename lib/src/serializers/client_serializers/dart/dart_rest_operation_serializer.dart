import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/serializers/dart/dart_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';

const _request = 'glRequest__';
const _body = 'glBody__';
const _json = 'glJson__';
const _result = 'glResult__';
const _fields = 'glFields__';
const _parts = 'glParts__';

class DartRestOperationSerializer {
  final GLParser _grammar;
  final DartCodeGenUtils _cg;
  final GLSerializer _serializer;
  final String Function(String name, GLType type) _toJson;
  final bool commaLists;
  final bool bracketNesting;

  DartRestOperationSerializer(
    this._grammar,
    this._cg,
    this._serializer,
    this._toJson, {
    this.commaLists = false,
    this.bracketNesting = false,
  });

  DartSerializer get _dart => _serializer as DartSerializer;

  String get _listOptions =>
      [if (bracketNesting) 'bracket: true', if (commaLists) 'comma: true'].map((e) => ', $e').join();

  bool _isUpload(GLRestArgument a) => _grammar.uploadScalarNames.contains(a.argument.type.firstType.token);

  bool _hasProgress(GLRestOperation op) => op.bodyKind == RestBodyKind.raw || op.bodyKind == RestBodyKind.multipart;

  String operationToMethod(GLRestOperation op) {
    final isVoid = op.responseKind == RestResponseKind.none;
    final returnType = isVoid
        ? 'void'
        : op.responseKind == RestResponseKind.binary
            ? 'GLDownload${op.allowsEmptyBody ? '?' : ''}'
            : _serializer.serializeType(op.field.type);
    return _cg.createMethod(
      returnType: 'Future<$returnType>',
      methodName: op.field.codeName,
      arguments: _signature(op),
      async: true,
      statements: [
        ..._bodyStatements(op),
        _cg.constDecl(_request, _requestExpression(op)),
        ..._execution(op),
      ],
    );
  }

  List<String> _signature(GLRestOperation op) {
    final args = op.arguments.map((a) {
      final arg = a.argument;
      final nullSuffix = arg.type.nullable ? '?' : '';
      final type = _isUpload(a)
          ? '${arg.type.isList ? 'List<GLUpload>' : 'GLUpload'}$nullSuffix'
          : _serializer.serializeType(arg.type);
      if (arg.defaultValue != null) {
        final literal = _serializer.serializeDefaultLiteral(arg.type, arg.defaultValue!.value, needsConst: true);
        return '$type ${arg.codeName} = $literal';
      }
      return arg.type.nullable ? '$type ${arg.codeName}' : 'required $type ${arg.codeName}';
    }).toList();
    if (_hasProgress(op)) args.add('UploadProgressCallback? onProgress');
    if (op.responseKind == RestResponseKind.binary) args.add('DownloadProgressCallback? onReceiveProgress');
    return args;
  }

  String _value(GLRestArgument a) => _toJson(a.argument.codeName, a.argument.type);

  String _presentValue(GLRestArgument a) => _toJson(a.argument.codeName, _nonNull(a.argument.type));

  GLType _nonNull(GLType type) => type is GLListType ? GLListType(type.type, false) : GLType(type.tokenInfo, false);

  String _requestExpression(GLRestOperation op) {
    final query = _entries(op, RestArgRole.query);
    return _cg.callExpression('RestRequest', [
      "method: '${op.method.wireName}'",
      'path: ${_pathExpression(op)}',
      if (query.isNotEmpty) _cg.listArg('query', query),
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
      buffer.write(_escapeLiteral(op.path.substring(last, m.start)));
      buffer.write('\${Uri.encodeComponent(${_value(byName[m.group(1)]!)}.toString())}');
      last = m.end;
    }
    buffer.write(_escapeLiteral(op.path.substring(last)));
    return "'$buffer'";
  }

  String _escapeLiteral(String text) => text.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$');

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
        final file = op.arguments.firstWhere((a) => a.role == RestArgRole.body).argument;
        final name = file.codeName;
        final entry = "'Content-Type': ${op.contentType == null ? '$name.mimeType' : "'${op.contentType}'"},";
        return [file.type.nullable ? _cg.inlineIfStatement(condition: '$name != null', statement: entry) : entry];
      case RestBodyKind.json:
      case RestBodyKind.form:
        final entry = "'Content-Type': '${op.contentType}',";
        return [_bodyMayBeNull(op) ? _cg.inlineIfStatement(condition: '$_body != null', statement: entry) : entry];
    }
  }

  String _headerEntry(GLRestArgument a) {
    final value = _value(a);
    if (a.encoding == RestEncoding.spread) {
      return '...restHeaders($value, ${_nameMap(a.spreadFields)}),';
    }
    final entry = "'${a.wireName}': restHeaderValue($value),";
    if (!a.argument.type.nullable) return entry;
    return _cg.inlineIfStatement(condition: '${a.argument.codeName} != null', statement: entry);
  }

  String _nameMap(Map<String, String> names) =>
      '{${names.entries.map((e) => "'${e.key}': '${e.value}'").join(', ')}}';

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
        final entry = "MapEntry('${a.wireName}', jsonEncode(${_presentValue(a)}))";
        return a.argument.type.nullable
            ? _cg.inlineIfStatement(condition: '${a.argument.codeName} != null', statement: entry)
            : entry;
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
        return [_cg.constDecl(_body, _nullGuard(arg, 'RestJsonBody(jsonEncode(${_presentValue(arg)}))'))];
      case RestBodyKind.raw:
        final arg = op.arguments.firstWhere((a) => a.role == RestArgRole.body);
        return [_cg.constDecl(_body, _nullGuard(arg, 'RestRawBody(${arg.argument.codeName})'))];
      case RestBodyKind.form:
        return _collected(_entries(op, RestArgRole.field), 'RestFormBody($_fields)', _fields, 'MapEntry<String, String>');
      case RestBodyKind.multipart:
        return _collected(_partEntries(op), 'RestMultipartBody($_parts)', _parts, 'RestPart');
    }
  }

  String _nullGuard(GLRestArgument arg, String expression) {
    if (!arg.argument.type.nullable) return expression;
    return _cg.ternaryOp(
        condition: '${arg.argument.codeName} == null', positiveStatement: 'null', negativeStatement: expression);
  }

  List<String> _collected(List<String> items, String body, String variable, String elementType) {
    final list = '<$elementType>[\n${items.map((e) => '$e,'.ident()).join('\n')}\n]';
    return [
      _cg.constDecl(variable, list),
      _cg.constDecl(_body, _cg.ternaryOp(condition: '$variable.isEmpty', positiveStatement: 'null', negativeStatement: body)),
    ];
  }

  List<String> _partEntries(GLRestOperation op) {
    return [
      for (final a in op.arguments)
        if (a.role == RestArgRole.part) _partEntry(a),
    ];
  }

  String _partEntry(GLRestArgument a) {
    final name = a.argument.codeName;
    if (_isUpload(a)) {
      if (a.argument.type.isList) {
        final spread = "...$name.map((e) => RestPart.file('${a.wireName}', e))";
        return a.argument.type.nullable ? _cg.inlineIfStatement(condition: '$name != null', statement: spread) : spread;
      }
      final part = "RestPart.file('${a.wireName}', $name)";
      return a.argument.type.nullable ? _cg.inlineIfStatement(condition: '$name != null', statement: part) : part;
    }
    if (a.encoding == RestEncoding.json) {
      final part = "RestPart.text('${a.wireName}', jsonEncode(${_presentValue(a)}), mimeType: 'application/json')";
      return a.argument.type.nullable ? _cg.inlineIfStatement(condition: '$name != null', statement: part) : part;
    }
    return '...restParts(${_entry(a).replaceFirst('...', '')})';
  }

  List<String> _execution(GLRestOperation op) {
    final invalidation = _invalidation(op);
    final path = "[${op.responsePathSegments.map((e) => "'$e'").join(', ')}]";
    switch (op.responseKind) {
      case RestResponseKind.none:
        return ['await restVoid__($_request);', ...invalidation];
      case RestResponseKind.text:
        return [
          _cg.constDecl(_result, 'await ${op.allowsEmptyBody ? 'restTextOrNull__' : 'restText__'}($_request)'),
          ...invalidation,
          'return $_result;',
        ];
      case RestResponseKind.binary:
        final call = 'await restDownload__($_request, ${op.allowsEmptyBody}, onReceiveProgress)';
        final download = op.allowsEmptyBody ? call : '($call)!';
        return [
          if (invalidation.isEmpty)
            'return $download;'
          else ...[
            _cg.constDecl(_result, download),
            ...invalidation,
            'return $_result;',
          ],
        ];
      case RestResponseKind.json:
        final decode = _dart.callFromJson(_json, op.field, op.field.type, 0);
        if (op.cacheTtl > 0) {
          return [_cachedReturn(op, path, decode)];
        }
        return [
          _cg.constDecl(_json, 'await restJson__($_request, $path, ${op.allowsEmptyBody})'),
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
    final tags = op.cacheTags.map((e) => e.quote()).toList();
    return 'return ${_cg.callExpression('restCached__', [
      "'${op.name}'",
      variables,
      '${op.cacheTtl}',
      '$tags',
      '${op.staleIfOffline}',
      '() => restJson__($_request, $path, ${op.allowsEmptyBody})',
      _cg.functionLiteral([_json], ['return $decode;']),
    ])};';
  }

  List<String> _invalidation(GLRestOperation op) {
    if (op.type != GLQueryType.mutation) return const [];
    if (op.invalidatesAll) return ['await glStore__.invalidateAll();'];
    if (op.invalidateTags.isNotEmpty) {
      return ['await invalidateByTags(${op.invalidateTags.map((e) => e.quote()).toList()});'];
    }
    return const [];
  }
}
