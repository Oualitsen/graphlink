import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_reactive_flavor.dart';
import 'package:graphlink/src/serializers/java/java_imports.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';

const _request = 'glRequest__';
const _body = 'glBody__';
const _json = 'glJson__';
const _fields = 'glFields__';
const _parts = 'glParts__';
const _utils = 'GraphLinkRestUtils';

class _ImportSink extends GLToken {
  _ImportSink() : super('glImportSink__'.toToken());
}

class JavaRestOperationSerializer {
  final GLParser _grammar;
  final JavaCodeGenUtils _cg;
  final JavaSerializer _serializer;
  final JavaReactiveFlavor _flavor;
  final bool commaLists;
  final bool bracketNesting;

  JavaRestOperationSerializer(
    this._grammar,
    this._cg,
    this._serializer,
    this._flavor, {
    this.commaLists = false,
    this.bracketNesting = false,
  });

  static const _primitives = {'boolean', 'byte', 'short', 'int', 'long', 'float', 'double', 'char'};

  late GLImportContainer _container;
  late _ImportSink _sink;

  String get _listOptions => ', $bracketNesting, $commaLists';

  bool _isUpload(GLRestArgument a) => _grammar.uploadScalarNames.contains(a.argument.type.firstType.token);

  bool _hasProgress(GLRestOperation op) => op.bodyKind == RestBodyKind.raw || op.bodyKind == RestBodyKind.multipart;

  GLType _nonNull(GLType type) => type is GLListType ? GLListType(type.type, false) : GLType(type.tokenInfo, false);

  String _name(GLRestArgument a) => a.argument.codeName;

  bool _nullable(GLRestArgument a) => a.argument.type.nullable;

  String _value(GLRestArgument a) => _serializer.toJsonExpr(a.argument.type, _name(a), context: _sink);

  String _presentValue(GLRestArgument a) => _serializer.toJsonExpr(_nonNull(a.argument.type), _name(a), context: _sink);

  String _argType(GLRestArgument a) {
    final type = a.argument.type;
    if (_isUpload(a)) return type.isList ? 'List<GLUpload>' : 'GLUpload';
    return _serializer.serializeType(type);
  }

  String operationToMethod(GLRestOperation op, GLImportContainer container) {
    _container = container;
    _sink = _ImportSink();
    container.imports.addAll([JavaImports.list, JavaImports.map, JavaImports.arrayList, JavaImports.objects, JavaImports.collections]);

    final methods = <String>[_fullMethod(op, container)];
    if (_hasProgress(op) || op.responseKind == RestResponseKind.binary) {
      methods.add(_overload(op));
    }
    container.imports.addAll(_sink.staticImports);
    return methods.join('\n\n');
  }

  List<String> _progressParams(GLRestOperation op) => [
        if (_hasProgress(op)) 'UploadProgressCallback onProgress',
        if (op.responseKind == RestResponseKind.binary) 'DownloadProgressCallback onReceiveProgress',
      ];

  String _fullMethod(GLRestOperation op, GLImportContainer container) {
    return _cg.createMethod(
      returnType: 'public ${_returnType(op)}',
      methodName: op.field.codeName,
      arguments: [..._signature(op), ..._progressParams(op)],
      statements: [
        ..._defaultCoalesces(op),
        ..._nullChecks(op),
        ..._bodyStatements(op),
        _cg.constDecl(_request, _requestExpression(op), type: 'RestRequest'),
        ..._execution(op),
      ],
    );
  }

  String _overload(GLRestOperation op) {
    final names = [
      ...op.arguments.map(_name),
      ..._progressParams(op).map((_) => 'null'),
    ];
    final call = '${op.field.codeName}(${names.join(', ')})';
    return _cg.createMethod(
      returnType: 'public ${_returnType(op)}',
      methodName: op.field.codeName,
      arguments: _signature(op),
      statements: [_returnsValue(op) ? 'return $call;' : '$call;'],
    );
  }

  bool _returnsValue(GLRestOperation op) => _flavor.isReactive || op.responseKind != RestResponseKind.none;

  String _returnType(GLRestOperation op) {
    switch (op.responseKind) {
      case RestResponseKind.none:
        return _flavor.voidType;
      case RestResponseKind.binary:
        return op.allowsEmptyBody ? _flavor.maybeType('GLDownload') : _flavor.singleType('GLDownload');
      case RestResponseKind.text:
      case RestResponseKind.json:
        final type = _serializer.serializeType(op.field.type);
        return op.allowsEmptyBody ? _flavor.maybeType(type) : _flavor.singleType(type);
    }
  }

  List<String> _signature(GLRestOperation op) => [
        for (final a in op.arguments) '${_argType(a)} ${_name(a)}',
      ];

  List<String> _defaultCoalesces(GLRestOperation op) {
    return [
      for (final a in op.arguments)
        if (a.argument.defaultValue != null)
          _cg.ifStatement(
            condition: '${_name(a)} == null',
            ifBlockStatements: ['${_name(a)} = ${_serializer.serializeDefaultLiteral(a.argument.type, a.argument.defaultValue!.value)};'],
          ),
    ];
  }

  List<String> _nullChecks(GLRestOperation op) {
    return [
      for (final a in op.arguments)
        if (!_nullable(a) && a.argument.defaultValue == null && !_primitives.contains(_argType(a)))
          'Objects.requireNonNull(${_name(a)}, "${_name(a)} is required");',
    ];
  }

  String _requestExpression(GLRestOperation op) {
    final query = _entries(op, RestArgRole.query);
    return 'new ${_cg.callExpression('RestRequest', [
      '"${op.method.wireName}"',
      _pathExpression(op),
      query.isEmpty ? 'Collections.emptyList()' : _concat(query),
      _headers(op),
      op.bodyKind == RestBodyKind.none ? 'null' : _body,
      _hasProgress(op) ? 'onProgress' : 'null',
      '${op.responseKind == RestResponseKind.binary}',
    ])}';
  }

  String _concat(List<String> lists) => lists.length == 1 ? lists.first : '$_utils.restConcat(${lists.join(', ')})';

  String _pathExpression(GLRestOperation op) {
    final byName = {
      for (final a in op.arguments)
        if (a.role == RestArgRole.path) a.wireName!: a,
    };
    final parts = <String>[];
    var last = 0;
    for (final m in restPlaceholder.allMatches(op.path)) {
      final literal = op.path.substring(last, m.start);
      if (literal.isNotEmpty) parts.add('"${_escapeLiteral(literal)}"');
      parts.add('$_utils.restEncode(String.valueOf(${_value(byName[m.group(1)]!)}))');
      last = m.end;
    }
    final tail = op.path.substring(last);
    if (tail.isNotEmpty || parts.isEmpty) parts.add('"${_escapeLiteral(tail)}"');
    if (parts.length == 1 && parts.first.startsWith('"')) return parts.first;
    return parts.first.startsWith('"') ? parts.join(' + ') : '"" + ${parts.join(' + ')}';
  }

  String _escapeLiteral(String text) => text.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  String _headers(GLRestOperation op) {
    final parts = <String>[
      '$_utils.restHeader("Accept", "${op.accept}")',
      ..._contentTypeEntries(op),
      for (final a in op.arguments)
        if (a.role == RestArgRole.header) _headerEntry(a),
    ];
    return '$_utils.restMerge(${parts.join(', ')})';
  }

  List<String> _contentTypeEntries(GLRestOperation op) {
    switch (op.bodyKind) {
      case RestBodyKind.none:
      case RestBodyKind.multipart:
        return const [];
      case RestBodyKind.raw:
        final arg = op.arguments.firstWhere((a) => a.role == RestArgRole.body);
        final name = _name(arg);
        final value = op.contentType == null ? '$name.getMimeType()' : '"${op.contentType}"';
        return [
          _nullable(arg)
              ? '$_utils.restHeader("Content-Type", ${_cg.ternaryOp(condition: '$name == null', positiveStatement: 'null', negativeStatement: value)})'
              : '$_utils.restHeader("Content-Type", $value)',
        ];
      case RestBodyKind.json:
      case RestBodyKind.form:
        final value = '"${op.contentType}"';
        return [
          _bodyMayBeNull(op)
              ? '$_utils.restHeader("Content-Type", ${_cg.ternaryOp(condition: '$_body == null', positiveStatement: 'null', negativeStatement: value)})'
              : '$_utils.restHeader("Content-Type", $value)',
        ];
    }
  }

  String _headerEntry(GLRestArgument a) {
    if (a.encoding == RestEncoding.spread) {
      return '$_utils.restHeaders(${_value(a)}, ${_nameMap(a.spreadFields)})';
    }
    return '$_utils.restHeader("${a.wireName}", ${_value(a)})';
  }

  String _nameMap(Map<String, String> names) =>
      '$_utils.restNames(${names.entries.map((e) => '"${e.key}", "${e.value}"').join(', ')})';

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
        return '$_utils.restSpreadEntries($value, ${_nameMap(a.spreadFields)}$_listOptions)';
      case RestEncoding.json:
        final encoded = _nullable(a)
            ? _cg.ternaryOp(
                condition: '${_name(a)} == null',
                positiveStatement: 'null',
                negativeStatement: 'restEncodeJson(${_presentValue(a)})')
            : 'restEncodeJson(${_presentValue(a)})';
        return '$_utils.restEntries("${a.wireName}", $encoded)';
      case RestEncoding.flat:
      case null:
        return '$_utils.restEntries("${a.wireName}", $value$_listOptions)';
    }
  }

  bool _bodyMayBeNull(GLRestOperation op) {
    if (op.bodyKind == RestBodyKind.form || op.bodyKind == RestBodyKind.multipart) return true;
    return _nullable(op.arguments.firstWhere((a) => a.role == RestArgRole.body));
  }

  List<String> _bodyStatements(GLRestOperation op) {
    switch (op.bodyKind) {
      case RestBodyKind.none:
        return const [];
      case RestBodyKind.json:
        final arg = op.arguments.firstWhere((a) => a.role == RestArgRole.body);
        return [_bodyDecl(_nullGuard(arg, 'new RestBody.Json(restEncodeJson(${_presentValue(arg)}))'))];
      case RestBodyKind.raw:
        final arg = op.arguments.firstWhere((a) => a.role == RestArgRole.body);
        return [_bodyDecl(_nullGuard(arg, 'new RestBody.Raw(${_name(arg)})'))];
      case RestBodyKind.form:
        return _collected(_entries(op, RestArgRole.field), 'new RestBody.Form($_fields)', _fields, 'Map.Entry<String, String>');
      case RestBodyKind.multipart:
        return _collected(_partEntries(op), 'new RestBody.Multipart($_parts)', _parts, 'RestPart');
    }
  }

  String _bodyDecl(String value) => _cg.constDecl(_body, value, type: 'RestBody');

  String _nullGuard(GLRestArgument arg, String expression) {
    if (!_nullable(arg)) return expression;
    return _cg.ternaryOp(condition: '${_name(arg)} == null', positiveStatement: 'null', negativeStatement: expression);
  }

  List<String> _collected(List<String> items, String body, String variable, String elementType) {
    return [
      _cg.constDecl(variable, items.isEmpty ? 'Collections.<$elementType>emptyList()' : _concat(items), type: 'List<$elementType>'),
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
        ? '(${_cg.ternaryOp(condition: '$name == null', positiveStatement: 'Collections.<RestPart>emptyList()', negativeStatement: present)})'
        : present;
    if (_isUpload(a)) {
      if (a.argument.type.isList) {
        _container.imports.add(JavaImports.collectors);
        return guarded('$name.stream().map(e -> RestPart.file("${a.wireName}", e)).collect(Collectors.toList())');
      }
      return guarded('Collections.singletonList(RestPart.file("${a.wireName}", $name))');
    }
    if (a.encoding == RestEncoding.json) {
      return guarded('Collections.singletonList(RestPart.text("${a.wireName}", restEncodeJson(${_presentValue(a)}), "application/json"))');
    }
    return '$_utils.restParts(${_entry(a)})';
  }

  List<String> _execution(GLRestOperation op) {
    final invalidation = _invalidation(op);
    final after = invalidation.isEmpty ? '() -> {}' : '() -> ${_cg.block(invalidation)}';
    final path = _listOf(op.responsePathSegments);
    final orNull = op.allowsEmptyBody ? 'OrNull' : '';
    switch (op.responseKind) {
      case RestResponseKind.none:
        return ['${_flavor.isReactive ? 'return ' : ''}restVoid($_request, $after);'];
      case RestResponseKind.text:
        return ['return restText$orNull($_request, $after);'];
      case RestResponseKind.binary:
        return ['return restDownload$orNull($_request, onReceiveProgress, $after);'];
      case RestResponseKind.json:
        if (op.cacheTtl > 0) return [_cachedReturn(op, path)];
        return ['return restJson$orNull($_request, $path, $_json -> ${_decode(op)}, $after);'];
    }
  }

  String _decode(GLRestOperation op) {
    if (op.responseKind == RestResponseKind.text) return _json;
    return _serializer.fromJsonExpr(op.field.type, _json, context: _sink);
  }

  String _listOf(List<String> items) {
    if (items.isEmpty) return 'Collections.emptyList()';
    return 'Arrays.asList(${items.map((e) => '"$e"').join(', ')})';
  }

  String _cachedReturn(GLRestOperation op, String path) {
    _container.imports.addAll([JavaImports.arrays, JavaImports.hashMap]);
    final variables = [
      for (final a in op.arguments)
        if (!_isUpload(a)) 'glVariables__.put("${a.name}", ${_value(a)});',
    ];
    final fetch = 'restFetch($_request, $path, ${op.allowsEmptyBody})';
    return [
      'Map<String, Object> glVariables__ = new HashMap<>();',
      ...variables,
      'return ${_cg.callExpression(_flavor.isReactive && op.allowsEmptyBody ? 'restCachedOrNull' : 'restCached', [
        '"${op.name}"',
        'glVariables__',
        '${op.cacheTtl}L',
        _listOf(op.cacheTags),
        '${op.staleIfOffline}',
        '() -> $fetch',
        '$_json -> ${_decode(op)}',
      ])};',
    ].join('\n');
  }

  List<String> _invalidation(GLRestOperation op) {
    if (op.type != GLQueryType.mutation) return const [];
    if (op.invalidatesAll) return ['glStore__.invalidateAll();'];
    if (op.invalidateTags.isNotEmpty) {
      _container.imports.add(JavaImports.arrays);
      return ['invalidateByTags(${_listOf(op.invalidateTags)});'];
    }
    return const [];
  }
}
