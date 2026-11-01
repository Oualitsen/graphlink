import 'package:graphlink/src/capture_errors_utils.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_fragment.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/python_code_gen_utils.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_client_vars.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/python_serializer.dart';

class PythonClientOperationSerializer {
  final GLParser _grammar;
  final PythonCodeGenUtils _cg;
  final GLGraphqlSerializer _gqlSerializer;
  final PythonSerializer _serializer;

  PythonClientOperationSerializer(this._grammar, this._cg, this._gqlSerializer, this._serializer);

  bool _shouldInvalidateAll(GLQueryDefinition def) => def.elements.any((e) => e.cacheInvalidateAll);

  Set<String> _invalidationTags(GLQueryDefinition def) => def.elements.expand((e) => e.invalidateCacheTags).toSet();

  bool _isUploadMutation(GLQueryDefinition def) => _grammar.mutationHasUploads(def);

  Set<GLFragmentDefinitionBase> _fragmentsFor(GLQueryDefinition def) => def.fragments(_grammar);

  List<DividedQuery> _divideQuery(GLQueryDefinition def) => _gqlSerializer.divideQueryDefinition(def, _grammar);

  String _typeName(String token) => _serializer.resolveCodeName(token);

  String _literal(String value) => _serializer.pythonStringLiteral(value);

  String _stringList(Iterable<String> values) => '[${values.map(_literal).join(', ')}]';

  // ── Entry points ───────────────────────────────────────────────────────────

  String queryToMethod(GLQueryDefinition def) {
    if (_divideQuery(def).every((e) => e.cacheTTL == 0)) return _simpleQueryMethod(def);
    return _cachedQueryMethod(def);
  }

  String _simpleQueryMethod(GLQueryDefinition def) {
    final fullResponse = _typeName(def.getFullResponseTypeDefinition(_grammar).tokenInfo.token);
    final capture = def.isCaptureErrors(_grammar);
    final call = _cg.callExpression('self.execute_${capture ? 'full' : 'data'}', [
      svQuery,
      svFragmentNames,
      _literal(def.tokenInfo.token),
      _variablesExpr(def),
      '$fullResponse.from_json',
    ]);
    return _cg.createMethod(
      async: true,
      methodName: def.codeName,
      arguments: _arguments(def),
      returnType: _returnType(def),
      statements: [
        ..._argumentDefaults(def),
        _cg.constDecl(svQuery, _literal(_gqlSerializer.serializeQueryDefinition(def))),
        _cg.constDecl(svFragmentNames, _stringList(_fragmentsFor(def).map((f) => f.tokenInfo.token))),
        if (_variablesStatement(def).isNotEmpty) _variablesStatement(def),
        capture ? 'return await $call' : 'return (await $call).data',
      ],
    );
  }

  String _cachedQueryMethod(GLQueryDefinition def) {
    final divided = _divideQuery(def);
    final fullResponse = _typeName(def.getFullResponseTypeDefinition(_grammar).tokenInfo.token);
    final capture = def.isCaptureErrors(_grammar);
    final directives = _gqlSerializer.serializeDirectiveValueList(def.getDirectives(skipGenerated: true));
    final call = _cg.callExpression('self.execute_cached', [
      svPartialQueries,
      _literal(def.tokenInfo.token),
      _literal(directives),
      '$fullResponse.from_json',
      capture ? 'True' : 'False',
    ]);
    return _cg.createMethod(
      async: true,
      methodName: def.codeName,
      arguments: _arguments(def),
      returnType: _returnType(def),
      statements: [
        ..._argumentDefaults(def),
        if (_variablesStatement(def).isNotEmpty) _variablesStatement(def),
        _cg.constDecl(svPartialQueries, '[\n${divided.map(_partialQuery).join(',\n').identPy()}\n]'),
        capture ? 'return await $call' : 'return (await $call).data',
      ],
    );
  }

  String mutationToMethod(GLQueryDefinition def) {
    final isSubscription = def.type == GLQueryType.subscription;
    final isUpload = _isUploadMutation(def);
    return _cg.createMethod(
      async: true,
      methodName: def.codeName,
      arguments: _arguments(def),
      returnType: _returnType(def),
      statements: [
        ..._argumentDefaults(def),
        _cg.constDecl(svQuery, _literal(_gqlSerializer.serializeQueryDefinition(def))),
        _cg.constDecl(svFragmentNames, _stringList(_fragmentsFor(def).map((f) => f.tokenInfo.token))),
        if (isSubscription || isUpload) _cg.constDecl(svFullQuery, 'self.assemble_query($svQuery, $svFragmentNames)'),
        if (_variablesStatement(def).isNotEmpty) _variablesStatement(def),
        if (isSubscription)
          _cg.constDecl(
            svPayload,
            _cg.callExpression('GraphLinkPayload', [
              'query=$svFullQuery',
              'operation_name=${_literal(def.tokenInfo.token)}',
              'variables=${_variablesExpr(def)}',
            ]),
          ),
        _adapterCall(def),
      ],
    );
  }

  // ── Arguments ──────────────────────────────────────────────────────────────

  String _uploadType(GLArgumentDefinition arg) => arg.type.isList ? 'List[GLUpload]' : 'GLUpload';

  String _argumentType(GLArgumentDefinition arg) {
    if (_grammar.uploadScalarNames.contains(arg.type.firstType.token)) {
      return arg.type.nullable ? 'Optional[${_uploadType(arg)}]' : _uploadType(arg);
    }
    return _serializer.serializeType(arg.type);
  }

  bool _defaultNeedsSentinel(GLArgumentDefinition arg) {
    final value = arg.defaultValue?.value;
    return value is List || value is Map;
  }

  List<String> _arguments(GLQueryDefinition def) {
    final args = def.arguments.map((arg) {
      final name = arg.codeName;
      if (arg.defaultValue != null) {
        if (_defaultNeedsSentinel(arg)) {
          final type = arg.type.nullable ? _argumentType(arg) : 'Optional[${_argumentType(arg)}]';
          return '$name: $type = None';
        }
        return '$name: ${_argumentType(arg)} = ${_serializer.serializeDefaultLiteral(arg.type, arg.defaultValue!.value)}';
      }
      if (arg.type.nullable) return '$name: ${_argumentType(arg)} = None';
      return '$name: ${_argumentType(arg)}';
    }).toList();
    if (_isUploadMutation(def)) args.add('on_progress: Optional[UploadProgressCallback] = None');
    return ['self', if (args.isNotEmpty) '*', ...args];
  }

  List<String> _argumentDefaults(GLQueryDefinition def) => [
        for (final arg in def.arguments)
          if (arg.defaultValue != null && _defaultNeedsSentinel(arg))
            _cg.ifStatement(
              condition: '${arg.codeName} is None',
              ifBlockStatements: ['${arg.codeName} = ${_serializer.serializeDefaultLiteral(arg.type, arg.defaultValue!.value)}'],
            ),
      ];

  String _returnType(GLQueryDefinition def) {
    if (def.type == GLQueryType.subscription) {
      return 'AsyncIterator[${_typeName(def.getGeneratedTypeDefinition().tokenInfo.token)}]';
    }
    if (def.isCaptureErrors(_grammar)) {
      return _typeName(def.getFullResponseTypeDefinition(_grammar).tokenInfo.token);
    }
    return _typeName(def.getGeneratedTypeDefinition().tokenInfo.token);
  }

  // ── Variables ──────────────────────────────────────────────────────────────

  String _variablesStatement(GLQueryDefinition def) {
    if (def.arguments.isEmpty) return '';
    final entries = <String>[];
    for (final arg in def.arguments) {
      final input = arg.hoistArgsInput;
      if (input == null) {
        entries.add('${_literal(arg.dartArgumentName)}: ${_argumentValue(def, arg.token)}');
        continue;
      }
      final base = arg.codeName;
      entries.add(arg.type.nullable ? '**($base.to_json() if $base is not None else {})' : '**$base.to_json()');
    }
    return _cg.constDecl(svVariables, '{\n${entries.join(',\n').identPy()}\n}');
  }

  String _variablesExpr(GLQueryDefinition def) => def.arguments.isNotEmpty ? svVariables : '{}';

  String _argumentValue(GLQueryDefinition def, String argName) {
    final arg = def.findByName(argName);
    if (_grammar.uploadScalarNames.contains(arg.type.firstType.token)) {
      if (arg.type.isList) return '[None for _ in ${arg.codeName}]';
      return 'None';
    }
    return _toJsonExpr(arg.codeName, arg.type, 0);
  }

  String _toJsonExpr(String expr, GLType type, int index) {
    final convertible = _grammar.inputTypeRequiresProjection(type) || _grammar.isEnum(type.token);
    if (!convertible) return expr;
    if (type.isList) {
      final variable = 'e$index';
      final inner = _toJsonExpr(variable, type.inlineType, index + 1);
      return _cg.nullSafe(expr, _cg.listComprehension(expression: inner, variable: variable, iterable: expr), type.nullable);
    }
    return _cg.nullSafe(expr, '$expr.to_json()', type.nullable);
  }

  // ── Partial queries ────────────────────────────────────────────────────────

  String _partialQuery(DividedQuery e) {
    final variables = '{${e.variables.map((v) => '${_literal(v.substring(1))}: $svVariables.get(${_literal(v.substring(1))})').join(', ')}}';
    return _cg.callExpression('GraphLinkPartialQuery', [
      'query=${_literal(e.query)}',
      'operation_name=${_literal(e.operationName)}',
      'tags=${_stringList(e.tags)}',
      'ttl=${e.cacheTTL}',
      'element_key=${_literal(e.elementKey)}',
      'fragment_names=${_stringList(e.fragmentNames)}',
      'argument_declarations=${_stringList(e.argumentDeclarations)}',
      'variables=${e.variables.isEmpty ? '{}' : variables}',
      'stale_if_offline=${e.staleIfOffline ? 'True' : 'False'}',
    ]);
  }

  // ── Adapter call ───────────────────────────────────────────────────────────

  String _adapterCall(GLQueryDefinition def) {
    if (def.type == GLQueryType.subscription) {
      final generated = _typeName(def.getGeneratedTypeDefinition().tokenInfo.token);
      return _cg.forEachLoop(
        async: true,
        variable: 'gl_event__',
        iterable: 'self.$svHandler.handle($svPayload)',
        statements: ['yield $generated.from_json(gl_event__)'],
      );
    }
    if (_isUploadMutation(def)) return _multipartAdapterCall(def);
    final fullResponse = _typeName(def.getFullResponseTypeDefinition(_grammar).tokenInfo.token);
    final capture = def.isCaptureErrors(_grammar);
    final call = _cg.callExpression('self.execute_${capture ? 'full' : 'data'}', [
      svQuery,
      svFragmentNames,
      _literal(def.tokenInfo.token),
      _variablesExpr(def),
      '$fullResponse.from_json',
    ]);
    final invalidation = _invalidationCall(def);
    if (capture) {
      return [
        _cg.constDecl(svResult, 'await $call'),
        if (invalidation.isNotEmpty)
          _cg.ifStatement(condition: '$svResult.errors is None', ifBlockStatements: [invalidation]),
        'return $svResult',
      ].join('\n');
    }
    return [
      _cg.constDecl(svResult, 'await $call'),
      if (invalidation.isNotEmpty) invalidation,
      'return $svResult.data',
    ].join('\n');
  }

  String _multipartAdapterCall(GLQueryDefinition def) {
    final uploadArgs = def.arguments.where((a) => _grammar.uploadScalarNames.contains(a.type.firstType.token)).toList();
    final statements = <String>[
      _cg.constDecl(svMultipartMap, '{}', type: 'Dict[str, Any]'),
      _cg.constDecl(svFileParts, '{}', type: 'Dict[str, Any]'),
      '$svSlot = 0',
    ];
    for (final arg in uploadArgs) {
      final name = arg.codeName;
      final wireName = arg.dartArgumentName;
      if (arg.type.isList) {
        statements.add(_cg.forEachLoop(
          variable: '_i',
          iterable: 'range(len($name))',
          statements: [
            '$svMultipartMap[str($svSlot + _i)] = [f"variables.$wireName.{_i}"]',
            '$svFileParts[str($svSlot + _i)] = self.$svUploadConverter($name[_i])',
          ],
        ));
        statements.add('$svSlot += len($name)');
      } else {
        statements.addAll([
          '$svMultipartMap[str($svSlot)] = ["variables.$wireName"]',
          '$svFileParts[str($svSlot)] = self.$svUploadConverter($name)',
          '$svSlot += 1',
        ]);
      }
    }
    final fullResponse = _typeName(def.getFullResponseTypeDefinition(_grammar).tokenInfo.token);
    final capture = def.isCaptureErrors(_grammar);
    final invalidation = _invalidationCall(def);
    statements.addAll([
      _cg.constDecl(
        svParts,
        '{\n${[
          '"operations": json.dumps({"query": $svFullQuery, "variables": $svVariables})',
          '"map": json.dumps($svMultipartMap)',
          '**$svFileParts',
        ].join(',\n').identPy()}\n}',
      ),
      _cg.constDecl(svResponse, 'await self.$svUploadAdapter($svParts, on_progress)'),
      _cg.constDecl(svResult, '$fullResponse.from_json(json.loads($svResponse))'),
      if (capture) ...[
        if (invalidation.isNotEmpty)
          _cg.ifStatement(condition: '$svResult.errors is None', ifBlockStatements: [invalidation]),
        'return $svResult',
      ] else ...[
        _cg.ifStatement(
          condition: '$svResult.errors is not None',
          ifBlockStatements: ['raise GraphLinkException($svResult.errors)'],
        ),
        if (invalidation.isNotEmpty) invalidation,
        'return $svResult.data',
      ],
    ]);
    return statements.join('\n');
  }

  String _invalidationCall(GLQueryDefinition def) {
    if (_shouldInvalidateAll(def)) return 'await self.$svStore.invalidate_all()';
    final tags = _invalidationTags(def);
    if (tags.isNotEmpty) return 'await self.invalidate_by_tags(${_stringList(tags)})';
    return '';
  }
}
