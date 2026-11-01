import 'package:graphlink/src/capture_errors_utils.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/go_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/serializers/client_serializers/go/go_client_vars.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/go_serializer.dart';

const _zero = 'glZero__';

class GoClientOperationSerializer {
  final GLParser _grammar;
  final GoCodeGenUtils _cg;
  final GLGraphqlSerializer _gqlSerializer;
  final GoSerializer _serializer;

  GoClientOperationSerializer(this._grammar, this._cg, this._gqlSerializer, this._serializer);

  // ── Naming & argument classification ───────────────────────────────────────

  String receiverFor(GLQueryType type) {
    switch (type) {
      case GLQueryType.query:
        return 'q *GraphLinkQueries';
      case GLQueryType.mutation:
        return 'm *GraphLinkMutations';
      case GLQueryType.subscription:
        return 's *GraphLinkSubscriptions';
    }
  }

  String _receiverVar(GLQueryType type) => receiverFor(type).split(' ').first;

  String _base(GLQueryType type) => '&${_receiverVar(type)}.GraphLinkResolverBase';

  String _optionsName(GLQueryDefinition def) => '${def.codeName}Options';

  bool _isUploadArg(GLArgumentDefinition arg) => _grammar.uploadScalarNames.contains(arg.type.firstType.token);

  bool _isOptional(GLArgumentDefinition arg) => arg.defaultValue != null || arg.type.nullable;

  String _paramName(GLArgumentDefinition arg) {
    final name = arg.codeName.firstLow;
    return goParameterReservedWords.contains(name) ? '${name}_' : name;
  }

  String _fieldName(GLArgumentDefinition arg) => arg.codeName.firstUp;

  List<GLArgumentDefinition> _required(GLQueryDefinition def) => def.arguments.where((a) => !_isOptional(a)).toList();

  List<GLArgumentDefinition> _optional(GLQueryDefinition def) => def.arguments.where(_isOptional).toList();

  bool _hasOptions(GLQueryDefinition def) => _optional(def).isNotEmpty || _isUploadMutation(def);

  bool _isUploadMutation(GLQueryDefinition def) => _grammar.mutationHasUploads(def);

  String _requiredType(GLArgumentDefinition arg) {
    if (_isUploadArg(arg)) return arg.type.isList ? '[]GLUpload' : 'GLUpload';
    return _serializer.serializeType(arg.type);
  }

  String _optionFieldType(GLArgumentDefinition arg) {
    if (_isUploadArg(arg)) return arg.type.isList ? '[]GLUpload' : '*GLUpload';
    return _serializer.serializeType(GLType.makeNullable(arg.type));
  }

  bool _needsDeref(GLArgumentDefinition arg) =>
      arg.defaultValue != null && !arg.type.nullable && _serializer.usesPointer(GLType.makeNullable(arg.type));

  String _valueExpr(GLArgumentDefinition arg) {
    if (!_isOptional(arg)) return _paramName(arg);
    if (arg.defaultValue != null) return _needsDeref(arg) ? '*${_paramName(arg)}' : _paramName(arg);
    return '$svOptions.${_fieldName(arg)}';
  }

  // ── Method assembly ────────────────────────────────────────────────────────

  String operationMethod(GLQueryDefinition def) {
    final String body;
    switch (def.type) {
      case GLQueryType.query:
        body = _divideQuery(def).every((e) => e.cacheTTL == 0) ? _simpleBody(def) : _cachedBody(def);
        break;
      case GLQueryType.mutation:
        body = _isUploadMutation(def) ? _uploadBody(def) : _simpleBody(def);
        break;
      case GLQueryType.subscription:
        body = _subscriptionBody(def);
        break;
    }
    return _assemble(def, body);
  }

  String _assemble(GLQueryDefinition def, String body) {
    final returnType = _returnType(def);
    final arguments = [
      'ctx context.Context',
      ..._required(def).map((a) => '${_paramName(a)} ${_requiredType(a)}'),
      if (_hasOptions(def)) 'opts ...${_optionsName(def)}',
    ];
    final isSubscription = def.type == GLQueryType.subscription;
    final method = _cg.createMethod(
      receiver: receiverFor(def.type),
      methodName: def.codeName,
      arguments: arguments,
      returnType: isSubscription ? returnType : '($returnType, error)',
      statements: [
        if (!isSubscription) 'var $_zero $returnType',
        if (_hasOptions(def)) ..._optionsUnpack(def),
        body,
      ],
    );
    return _hasOptions(def) ? '${_optionsStruct(def)}\n\n$method' : method;
  }

  String _optionsStruct(GLQueryDefinition def) {
    final fields = [
      ..._optional(def).map((a) => '${_fieldName(a)} ${_optionFieldType(a)}'),
      if (_isUploadMutation(def)) 'OnProgress UploadProgressCallback',
    ];
    return _cg.structDecl(_optionsName(def), [fields.join('\n')]);
  }

  List<String> _optionsUnpack(GLQueryDefinition def) {
    return [
      'var $svOptions ${_optionsName(def)}',
      _cg.inlineIfStatement(condition: 'len(opts) > 0', statement: '$svOptions = opts[0]'),
      for (final arg in _optional(def).where((a) => a.defaultValue != null && !_isUploadArg(a))) ...[
        _cg.constDecl(_paramName(arg), '$svOptions.${_fieldName(arg)}'),
        _cg.inlineIfStatement(
          condition: '${_paramName(arg)} == nil',
          statement:
              '${_paramName(arg)} = ${_serializer.serializeDefaultLiteral(GLType.makeNullable(arg.type), arg.defaultValue!.value)}',
        ),
      ],
    ];
  }

  String _returnType(GLQueryDefinition def) {
    final response = def.getGeneratedTypeDefinition().tokenInfo.token;
    if (def.type == GLQueryType.subscription) return '<-chan GraphLinkEvent[$response]';
    if (def.isCaptureErrors(_grammar)) return def.getFullResponseTypeDefinition(_grammar).tokenInfo.token;
    return response;
  }

  // ── Query text & variables ─────────────────────────────────────────────────

  String _goLiteral(String text) => text.contains('`') ? _serializer.stringLiteral(text) : '`$text`';

  String _stringSlice(Iterable<String> values) =>
      '[]string{${values.map(_serializer.stringLiteral).join(', ')}}';

  Set<String> _fragmentNames(GLQueryDefinition def) => def.fragments(_grammar).map((f) => f.tokenInfo.token).toSet();

  List<DividedQuery> _divideQuery(GLQueryDefinition def) => _gqlSerializer.divideQueryDefinition(def, _grammar);

  List<String> _variableStatements(GLQueryDefinition def) {
    final plain = <String>[];
    final hoisted = <String>[];
    for (final arg in def.arguments) {
      if (arg.hoistArgsInput != null) {
        hoisted.add('glMergeVariables($svVariables, ${_valueExpr(arg)})');
        continue;
      }
      plain.add('${_serializer.stringLiteral(arg.dartArgumentName)}: ${_variableValue(arg)},');
    }
    return [
      '$svVariables := map[string]any{${plain.isEmpty ? '' : '\n${plain.join('\n').identGo()}\n'}}',
      ...hoisted,
    ];
  }

  String _variableValue(GLArgumentDefinition arg) {
    if (_isUploadArg(arg)) return arg.type.isList ? 'make([]any, len(${_valueExpr(arg)}))' : 'nil';
    return _valueExpr(arg);
  }

  // ── Bodies ─────────────────────────────────────────────────────────────────

  String _queryPrelude(GLQueryDefinition def) {
    final fragments = _fragmentNames(def);
    return [
      'const $svQuery = ${_goLiteral(_gqlSerializer.serializeQueryDefinition(def))}',
      '$svFragmentNames := ${fragments.isEmpty ? '[]string{}' : _stringSlice(fragments)}',
    ].join('\n');
  }

  String _simpleBody(GLQueryDefinition def) {
    final fullResponse = def.getFullResponseTypeDefinition(_grammar).tokenInfo.token;
    final type = def.type;
    final captureErrors = def.isCaptureErrors(_grammar);
    final call = _cg.callExpression('${captureErrors ? 'glExecuteFull' : 'glExecuteData'}[$fullResponse]', [
      'ctx',
      _base(type),
      svQuery,
      svFragmentNames,
      _serializer.stringLiteral(def.tokenInfo.token),
      svVariables,
    ]);
    return [
      _queryPrelude(def),
      ..._variableStatements(def),
      '$svResult, err := $call',
      _cg.ifStatement(condition: 'err != nil', ifBlockStatements: ['return $_zero, err']),
      ..._finish(def, captureErrors),
    ].join('\n');
  }

  List<String> _finish(GLQueryDefinition def, bool captureErrors) {
    final invalidation = _invalidation(def);
    if (captureErrors) {
      return [
        if (invalidation.isNotEmpty)
          _cg.ifStatement(condition: 'len($svResult.GetErrors()) == 0', ifBlockStatements: invalidation),
        'return $svResult, nil',
      ];
    }
    return [
      ...invalidation,
      _cg.ifStatement(
        condition: '$svResult.Data == nil',
        ifBlockStatements: [
          'return $_zero, fmt.Errorf("${def.tokenInfo.token}: response contained no data")',
        ],
      ),
      'return *$svResult.Data, nil',
    ];
  }

  List<String> _invalidation(GLQueryDefinition def) {
    final receiver = _receiverVar(def.type);
    if (def.elements.any((e) => e.cacheInvalidateAll)) {
      return [
        _cg.ifStatement(
          condition: 'err := $receiver.store.InvalidateAll(ctx); err != nil',
          ifBlockStatements: ['return $_zero, err'],
        ),
      ];
    }
    final tags = def.elements.expand((e) => e.invalidateCacheTags).toSet();
    if (tags.isEmpty) return const [];
    return [
      _cg.ifStatement(
        condition: 'err := $receiver.invalidateByTags(ctx, ${_stringSlice(tags)}); err != nil',
        ifBlockStatements: ['return $_zero, err'],
      ),
    ];
  }

  String _cachedBody(GLQueryDefinition def) {
    final fullResponse = def.getFullResponseTypeDefinition(_grammar).tokenInfo.token;
    final captureErrors = def.isCaptureErrors(_grammar);
    final directives = _gqlSerializer.serializeDirectiveValueList(def.getDirectives(skipGenerated: true));
    final partials = _divideQuery(def).map(_partialQuery).join('\n');
    final call = _cg.callExpression('glExecuteCached[$fullResponse]', [
      'ctx',
      _base(def.type),
      svPartialQueries,
      _serializer.stringLiteral(def.tokenInfo.token),
      _serializer.stringLiteral(directives),
      '${captureErrors}',
    ]);
    return [
      ..._variableStatements(def),
      '_ = $svVariables',
      '$svPartialQueries := []GraphLinkPartialQuery{\n${partials.identGo()}\n}',
      '$svResult, err := $call',
      _cg.ifStatement(condition: 'err != nil', ifBlockStatements: ['return $_zero, err']),
      ..._finish(def, captureErrors),
    ].join('\n');
  }

  String _partialQuery(DividedQuery e) {
    final variables = e.variables
        .map((v) => '${_serializer.stringLiteral(v.substring(1))}: $svVariables[${_serializer.stringLiteral(v.substring(1))}],')
        .join('\n');
    final fields = [
      'Query: ${_goLiteral(e.query)},',
      'OperationName: ${_serializer.stringLiteral(e.operationName)},',
      'Tags: ${_stringSlice(e.tags)},',
      'TTL: ${e.cacheTTL},',
      'ElementKey: ${_serializer.stringLiteral(e.elementKey)},',
      'FragmentNames: ${_stringSlice(e.fragmentNames)},',
      'ArgumentDeclarations: ${_stringSlice(e.argumentDeclarations)},',
      'Variables: map[string]any{${variables.isEmpty ? '' : '\n${variables.identGo()}\n'}},',
      'StaleIfOffline: ${e.staleIfOffline},',
    ].join('\n');
    return 'NewGraphLinkPartialQuery(GraphLinkPartialQuery{\n${fields.identGo()}\n}),';
  }

  String _subscriptionBody(GLQueryDefinition def) {
    final response = def.getGeneratedTypeDefinition().tokenInfo.token;
    final receiver = _receiverVar(def.type);
    return [
      _queryPrelude(def),
      ..._variableStatements(def),
      '$svFullQuery := $receiver.assembleQuery($svQuery, $svFragmentNames)',
      '$svPayload := GraphLinkPayload{Query: $svFullQuery, OperationName: ${_serializer.stringLiteral(def.tokenInfo.token)}, Variables: $svVariables}',
      'return glMapEvents[$response]($receiver.$svHandler.Handle(ctx, $svPayload))',
    ].join('\n');
  }

  String _uploadBody(GLQueryDefinition def) {
    final fullResponse = def.getFullResponseTypeDefinition(_grammar).tokenInfo.token;
    final captureErrors = def.isCaptureErrors(_grammar);
    final receiver = _receiverVar(def.type);
    final uploadArgs = def.arguments.where(_isUploadArg).toList();
    final slotStatements = <String>[
      '$svMultipartMap := map[string][]string{}',
      '$svFileParts := map[string]any{}',
      'var $svSlot int',
    ];
    for (var index = 0; index < uploadArgs.length; index++) {
      final arg = uploadArgs[index];
      final expr = _valueExpr(arg);
      final key = 'key$index';
      final wire = arg.dartArgumentName;
      if (arg.type.isList) {
        slotStatements.add(_cg.forLoop(
          init: 'i := 0',
          condition: 'i < len($expr)',
          increment: 'i++',
          statements: [
            '$key := strconv.Itoa($svSlot + i)',
            '$svMultipartMap[$key] = []string{fmt.Sprintf("variables.$wire.%d", i)}',
            '$svFileParts[$key] = $receiver.$svUploadConverter($expr[i])',
          ],
        ));
        slotStatements.add('$svSlot += len($expr)');
      } else {
        final body = [
          '$key := strconv.Itoa($svSlot)',
          '$svMultipartMap[$key] = []string{"variables.$wire"}',
          '$svFileParts[$key] = $receiver.$svUploadConverter(${arg.type.nullable ? '*$expr' : expr})',
          '$svSlot++',
        ];
        slotStatements.add(arg.type.nullable
            ? _cg.ifStatement(condition: '$expr != nil', ifBlockStatements: body)
            : body.join('\n'));
      }
    }
    return [
      _queryPrelude(def),
      ..._variableStatements(def),
      '$svFullQuery := $receiver.assembleQuery($svQuery, $svFragmentNames)',
      ...slotStatements,
      '$svOperations, err := json.Marshal(map[string]any{"query": $svFullQuery, "variables": $svVariables})',
      _cg.ifStatement(condition: 'err != nil', ifBlockStatements: ['return $_zero, err']),
      '$svMapJson, err := json.Marshal($svMultipartMap)',
      _cg.ifStatement(condition: 'err != nil', ifBlockStatements: ['return $_zero, err']),
      '$svParts := map[string]any{"operations": string($svOperations), "map": string($svMapJson)}',
      _cg.forEachLoop(variable: 'key, part', iterable: svFileParts, statements: ['$svParts[key] = part']),
      _cg.ifStatement(
        condition: '$receiver.$svUploadAdapter == nil',
        ifBlockStatements: ['return $_zero, errors.New("no upload adapter configured for ${def.tokenInfo.token}")'],
      ),
      '$svResponse, err := $receiver.$svUploadAdapter(ctx, $svParts, $svOptions.OnProgress)',
      _cg.ifStatement(condition: 'err != nil', ifBlockStatements: ['return $_zero, err']),
      'var $svResult $fullResponse',
      _cg.ifStatement(
        condition: 'err := json.Unmarshal([]byte($svResponse), &$svResult); err != nil',
        ifBlockStatements: ['return $_zero, err'],
      ),
      if (!captureErrors)
        _cg.ifStatement(
          condition: 'len($svResult.GetErrors()) > 0',
          ifBlockStatements: ['return $_zero, &GraphLinkException{Errors: $svResult.GetErrors()}'],
        ),
      ..._finish(def, captureErrors),
    ].join('\n');
  }
}

const svOperations = 'glOperations__';
const svMapJson = 'glMapJson__';
