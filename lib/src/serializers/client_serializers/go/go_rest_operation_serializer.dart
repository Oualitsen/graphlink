import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/go_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/serializers/go/go_serializer.dart';

const _request = 'glRequest__';
const _body = 'glBody__';
const _raw = 'glRaw__';
const _zero = 'glZero__';
const _options = 'glOptions__';
const _fields = 'glFields__';
const _parts = 'glParts__';

class GoRestOperationSerializer {
  final GLParser _grammar;
  final GoCodeGenUtils _cg;
  final GoSerializer _serializer;
  final bool commaLists;
  final bool bracketNesting;

  GoRestOperationSerializer(
    this._grammar,
    this._cg,
    this._serializer, {
    this.commaLists = false,
    this.bracketNesting = false,
  });

  String get _listFlags => '$bracketNesting, $commaLists';

  bool _isUpload(GLRestArgument a) => _grammar.uploadScalarNames.contains(a.argument.type.firstType.token);

  bool _isOptional(GLRestArgument a) => a.argument.defaultValue != null || a.argument.type.nullable;

  bool _hasProgress(GLRestOperation op) => op.bodyKind == RestBodyKind.raw || op.bodyKind == RestBodyKind.multipart;

  bool _hasDownload(GLRestOperation op) => op.responseKind == RestResponseKind.binary;

  String _receiverVar(GLRestOperation op) => 'glSelf__';

  String _receiver(GLRestOperation op) =>
      '${_receiverVar(op)} *${op.type == GLQueryType.query ? 'GraphLinkQueries' : 'GraphLinkMutations'}';

  String _param(GLRestArgument a) {
    final name = a.argument.codeName.firstLow;
    return goParameterReservedWords.contains(name) ? '${name}_' : name;
  }

  String _field(GLRestArgument a) => a.argument.codeName.firstUp;

  String _optionsName(GLRestOperation op) => '${op.field.codeName.firstUp}Options';

  List<GLRestArgument> _required(GLRestOperation op) => op.arguments.where((a) => !_isOptional(a)).toList();

  List<GLRestArgument> _optional(GLRestOperation op) => op.arguments.where(_isOptional).toList();

  bool _hasOptions(GLRestOperation op) => _optional(op).isNotEmpty || _hasProgress(op) || _hasDownload(op);

  String _requiredType(GLRestArgument a) {
    if (_isUpload(a)) return a.argument.type.isList ? '[]GLUpload' : 'GLUpload';
    return _serializer.serializeType(a.argument.type);
  }

  String _optionFieldType(GLRestArgument a) {
    if (_isUpload(a)) return a.argument.type.isList ? '[]GLUpload' : '*GLUpload';
    return _serializer.serializeType(GLType.makeNullable(a.argument.type));
  }

  bool _needsDeref(GLRestArgument a) =>
      a.argument.defaultValue != null &&
      !a.argument.type.nullable &&
      _serializer.usesPointer(GLType.makeNullable(a.argument.type));

  String _value(GLRestArgument a) {
    if (!_isOptional(a)) return _param(a);
    if (a.argument.defaultValue != null) return _param(a);
    return '$_options.${_field(a)}';
  }

  bool _nullableUpload(GLRestArgument a) => _isUpload(a) && a.argument.type.nullable && !a.argument.type.isList;

  String operationToMethod(GLRestOperation op) {
    final returnType = _returnType(op);
    final signature = [
      'ctx context.Context',
      ..._required(op).map((a) => '${_param(a)} ${_requiredType(a)}'),
      if (_hasOptions(op)) 'opts ...${_optionsName(op)}',
    ];
    final statements = [
      if (returnType.isNotEmpty) 'var $_zero $returnType',
      if (_hasOptions(op)) ..._optionsUnpack(op),
      ..._bodyStatements(op),
      _requestDecl(op),
      ..._execution(op, returnType),
    ];
    final method = _cg.createMethod(
      receiver: _receiver(op),
      methodName: op.field.codeName,
      arguments: signature,
      returnType: returnType.isEmpty ? 'error' : '($returnType, error)',
      statements: statements,
    );
    return _hasOptions(op) ? '${_optionsStruct(op)}\n\n$method' : method;
  }

  String _optionsStruct(GLRestOperation op) {
    final fields = [
      ..._optional(op).map((a) => '${_field(a)} ${_optionFieldType(a)}'),
      if (_hasProgress(op)) 'OnProgress UploadProgressCallback',
      if (_hasDownload(op)) 'OnReceiveProgress DownloadProgressCallback',
    ];
    return _cg.structDecl(_optionsName(op), [fields.join('\n')]);
  }

  List<String> _optionsUnpack(GLRestOperation op) => [
        'var $_options ${_optionsName(op)}',
        _cg.inlineIfStatement(condition: 'len(opts) > 0', statement: '$_options = opts[0]'),
        for (final a in _optional(op).where((a) => a.argument.defaultValue != null && !_isUpload(a))) ...[
          _cg.constDecl(_param(a), '$_options.${_field(a)}'),
          _cg.inlineIfStatement(
            condition: '${_param(a)} == nil',
            statement:
                '${_param(a)} = ${_serializer.serializeDefaultLiteral(GLType.makeNullable(a.argument.type), a.argument.defaultValue!.value)}',
          ),
        ],
      ];

  String _returnType(GLRestOperation op) {
    switch (op.responseKind) {
      case RestResponseKind.none:
        return '';
      case RestResponseKind.binary:
        return '*GLDownload';
      case RestResponseKind.text:
      case RestResponseKind.json:
        return _serializer.serializeType(op.field.type);
    }
  }

  String _requestDecl(GLRestOperation op) {
    final query = _entries(op, RestArgRole.query);
    return '$_request := RestRequest{\n${[
      'Method: "${op.method.wireName}",',
      'Path: ${_pathExpression(op)},',
      'Query: ${query.isEmpty ? '[]RestEntry{}' : 'restConcat(${query.join(', ')})'},',
      'Headers: ${_headers(op)},',
      if (op.bodyKind != RestBodyKind.none) 'Body: $_body,',
      if (_hasProgress(op)) 'OnSendProgress: $_options.OnProgress,',
    ].join('\n').identGo()}\n}';
  }

  String _pathExpression(GLRestOperation op) {
    final byName = {
      for (final a in op.arguments)
        if (a.role == RestArgRole.path) a.wireName!: a,
    };
    final pieces = <String>[];
    var last = 0;
    for (final m in restPlaceholder.allMatches(op.path)) {
      final literal = op.path.substring(last, m.start);
      if (literal.isNotEmpty) pieces.add(_serializer.stringLiteral(literal));
      pieces.add('restPath(${_value(byName[m.group(1)]!)})');
      last = m.end;
    }
    final tail = op.path.substring(last);
    if (tail.isNotEmpty || pieces.isEmpty) pieces.add(_serializer.stringLiteral(tail));
    return pieces.join(' + ');
  }

  String _headers(GLRestOperation op) {
    final parts = <String>[
      'map[string]string{"Accept": "${op.accept}"}',
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
        return [op.contentType == null ? 'restRawContentType($_body)' : 'restContentType($_body != nil, "${op.contentType}")'];
      case RestBodyKind.json:
      case RestBodyKind.form:
        return ['restContentType($_body != nil, "${op.contentType}")'];
    }
  }

  String _headerEntry(GLRestArgument a) {
    final value = _value(a);
    if (a.encoding == RestEncoding.spread) return 'restHeaders($value, ${_nameList(a.spreadFields)})';
    return 'restHeader("${a.wireName}", $value)';
  }

  String _nameList(Map<String, String> names) =>
      '[][2]string{${names.entries.map((e) => '{"${e.key}", "${e.value}"}').join(', ')}}';

  List<String> _entries(GLRestOperation op, RestArgRole role) => [
        for (final a in op.arguments)
          if (a.role == role) _entry(a),
      ];

  String _entry(GLRestArgument a) {
    final value = _value(a);
    switch (a.encoding) {
      case RestEncoding.spread:
        return 'restSpreadEntries($value, ${_nameList(a.spreadFields)}, $_listFlags)';
      case RestEncoding.json:
        return 'restJSONEntry("${a.wireName}", $value)';
      case RestEncoding.flat:
      case null:
        return 'restEntries("${a.wireName}", $value, $_listFlags)';
    }
  }

  List<String> _bodyStatements(GLRestOperation op) {
    switch (op.bodyKind) {
      case RestBodyKind.none:
        return const [];
      case RestBodyKind.json:
        final arg = op.arguments.firstWhere((a) => a.role == RestArgRole.body);
        final value = _value(arg);
        final encode = [
          'glBodyData__, err := json.Marshal($value)',
          _cg.ifStatement(condition: 'err != nil', ifBlockStatements: [_failure(op)]),
          '$_body = RestJSONBody{JSON: glBodyData__}',
        ];
        return [
          'var $_body RestBody',
          arg.argument.type.nullable
              ? _cg.ifStatement(condition: '${_nilCheck(arg)} != nil', ifBlockStatements: encode)
              : encode.join('\n'),
        ];
      case RestBodyKind.raw:
        final arg = op.arguments.firstWhere((a) => a.role == RestArgRole.body);
        final value = _value(arg);
        return [
          'var $_body RestBody',
          arg.argument.type.nullable
              ? _cg.ifStatement(condition: '$value != nil', ifBlockStatements: ['$_body = RestRawBody{Upload: *$value}'])
              : '$_body = RestRawBody{Upload: $value}',
        ];
      case RestBodyKind.form:
        return [
          '$_fields := restConcat(${_entries(op, RestArgRole.field).join(', ')})'.replaceFirst('restConcat()', '[]RestEntry{}'),
          'var $_body RestBody',
          _cg.ifStatement(condition: 'len($_fields) > 0', ifBlockStatements: ['$_body = RestFormBody{Fields: $_fields}']),
        ];
      case RestBodyKind.multipart:
        final parts = [for (final a in op.arguments) if (a.role == RestArgRole.part) _partEntry(a)];
        return [
          '$_parts := restConcat(${parts.join(', ')})'.replaceFirst('restConcat()', '[]RestPart{}'),
          'var $_body RestBody',
          _cg.ifStatement(condition: 'len($_parts) > 0', ifBlockStatements: ['$_body = RestMultipartBody{Parts: $_parts}']),
        ];
    }
  }

  String _nilCheck(GLRestArgument a) => _value(a);

  String _partEntry(GLRestArgument a) {
    final value = _value(a);
    final wire = '"${a.wireName}"';
    if (_isUpload(a)) {
      if (a.argument.type.isList) return 'restFileParts($wire, $value)';
      return a.argument.type.nullable ? 'restFilePart($wire, $value)' : 'restFilePart($wire, &$value)';
    }
    if (a.encoding == RestEncoding.json) return 'restJSONPart($wire, $value)';
    return 'restTextParts(${_entry(a)})';
  }

  String _failure(GLRestOperation op) => op.responseKind == RestResponseKind.none ? 'return err' : 'return $_zero, err';

  List<String> _execution(GLRestOperation op, String returnType) {
    final receiver = _receiverVar(op);
    final invalidation = _invalidation(op);
    final path = 'string{${op.responsePathSegments.map((e) => '"$e"').join(', ')}}';
    switch (op.responseKind) {
      case RestResponseKind.none:
        return [
          _cg.ifStatement(
            condition: 'err := $receiver.restVoid(ctx, $_request); err != nil',
            ifBlockStatements: ['return err'],
          ),
          ...invalidation,
          'return nil',
        ];
      case RestResponseKind.text:
        return [
          '$_raw, err := $receiver.${op.allowsEmptyBody ? 'restTextOrNil' : 'restTextBody'}(ctx, $_request)',
          _cg.ifStatement(condition: 'err != nil', ifBlockStatements: ['return $_zero, err']),
          ...invalidation,
          'return $_raw, nil',
        ];
      case RestResponseKind.binary:
        return [
          '$_raw, err := $receiver.restDownload(ctx, $_request, ${op.allowsEmptyBody}, $_options.OnReceiveProgress)',
          _cg.ifStatement(condition: 'err != nil', ifBlockStatements: ['return $_zero, err']),
          ...invalidation,
          'return $_raw, nil',
        ];
      case RestResponseKind.json:
        final decoder = _serializer.isPolymorphic(op.field.type)
            ? _serializer.decoderFor(op.field.type)
            : 'restDecode[$returnType]';
        if (op.cacheTtl > 0) return ['_ = $_zero', _cachedReturn(op, returnType, path, decoder)];
        return [
          '$_raw, err := $receiver.restJSON(ctx, $_request, []$path, ${op.allowsEmptyBody})',
          _cg.ifStatement(condition: 'err != nil', ifBlockStatements: ['return $_zero, err']),
          'glValue__, err := $decoder($_raw)',
          _cg.ifStatement(condition: 'err != nil', ifBlockStatements: ['return $_zero, err']),
          ...invalidation,
          'return glValue__, nil',
        ];
    }
  }

  String _cachedReturn(GLRestOperation op, String returnType, String path, String decoder) {
    final receiver = _receiverVar(op);
    final variables = [
      for (final a in op.arguments)
        if (!_isUpload(a)) '"${a.name}": ${_value(a)},',
    ];
    return 'return restCached[$returnType](\n${[
      'ctx,',
      '&$receiver.GraphLinkRestResolver,',
      '"${op.name}",',
      'map[string]any{${variables.isEmpty ? '' : '\n${variables.join('\n').identGo()}\n'}},',
      '${op.cacheTtl},',
      '[]string{${op.cacheTags.map((e) => '"$e"').join(', ')}},',
      '${op.staleIfOffline},',
      'func() (json.RawMessage, error) {\n\treturn $receiver.restJSON(ctx, $_request, []$path, ${op.allowsEmptyBody})\n},',
      '$decoder,',
    ].join('\n').identGo()}\n)';
  }

  List<String> _invalidation(GLRestOperation op) {
    if (op.type != GLQueryType.mutation) return const [];
    final receiver = _receiverVar(op);
    final failure = op.responseKind == RestResponseKind.none ? 'return err' : 'return $_zero, err';
    if (op.invalidatesAll) {
      return [
        _cg.ifStatement(
          condition: 'err := $receiver.store.InvalidateAll(ctx); err != nil',
          ifBlockStatements: [failure],
        ),
      ];
    }
    if (op.invalidateTags.isEmpty) return const [];
    return [
      _cg.ifStatement(
        condition:
            'err := $receiver.invalidateByTags(ctx, []string{${op.invalidateTags.map((e) => '"$e"').join(', ')}}); err != nil',
        ifBlockStatements: [failure],
      ),
    ];
  }
}
