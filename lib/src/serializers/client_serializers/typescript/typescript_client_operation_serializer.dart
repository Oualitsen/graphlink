import 'package:graphlink/src/capture_errors_utils.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_vars.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:graphlink/src/typescript_code_gen_utils.dart';

class TypeScriptClientOperationSerializer {
  final GLParser _parser;
  final TypeScriptCodeGenUtils _cg;
  final GLGraphqlSerializer _gqlSerializer;
  final TypeScriptSerializer _serializer;
  final bool observables;

  TypeScriptClientOperationSerializer(
    this._parser,
    this._cg,
    this._gqlSerializer,
    this._serializer, {
    this.observables = false,
  });

  // ── Schema-level helpers ───────────────────────────────────────────────────

  bool _shouldInvalidateAll(GLQueryDefinition def) =>
      def.elements.any((e) => e.cacheInvalidateAll);

  Set<String> _getInvalidationTags(GLQueryDefinition def) =>
      def.elements.expand((e) => e.invalidateCacheTags).toSet();

  bool _isUploadMutation(GLQueryDefinition def) =>
      _parser.mutationHasUploads(def);


  // ── Helpers shared by operation methods ────────────────────────────────────

  bool get _hasFullResponseSupport =>
      _parser.getTypeByName('GraphLinkError') != null;

  String _returnTypeName(GLQueryDefinition def) {
    if (def.isCaptureErrors(_parser) && _hasFullResponseSupport) {
      return def.getFullResponseTypeDefinition(_parser).tokenInfo.token;
    }
    return def.getGeneratedTypeDefinition().tokenInfo.token;
  }

  String _fragmentNamesExpr(GLQueryDefinition def) {
    final names = def.fragments(_parser).map((f) => "'${f.tokenInfo.token}'").toSet().toList();
    return names.isEmpty ? '[] as string[]' : _cg.arrayLiteral(names);
  }

  String _executeFull(GLQueryDefinition def, String fullResponseTypeName) =>
      'const $svResult = await ${_cg.callExpression('this._executeFull<$fullResponseTypeName>', [
        svQuery,
        svFragmentNames,
        "'${def.tokenInfo}'",
        svVariables,
      ])};';

  String _assembleQuery() =>
      'const $svFullQuery = ${_cg.callExpression('this.assembleQuery', [svQuery, svFragmentNames])};';

  String get _cancelSubscription =>
      'return () => ${_cg.block(['void $svGen.return(undefined);'])};';

  /// Wraps [expr] with a `TypeName.fromJson(...)` call.
  String _fromJson(String expr, String typeName) =>
      '$typeName.fromJson($expr as Record<string, unknown>)';

  // ── Query method ──────────────────────────────────────────────────────────

  String queryToMethod(GLQueryDefinition def) {
    final dividedQueries = _gqlSerializer.divideQueryDefinition(def, _parser);
    if (dividedQueries.every((e) => e.cacheTTL == 0)) {
      return _simpleQueryToMethod(def, dividedQueries);
    }
    return _cachedQueryToMethod(def);
  }

  String _simpleQueryToMethod(
      GLQueryDefinition def, List<DividedQuery> dividedQueries) {
    final returnTypeName = _returnTypeName(def);
    final fullResponseTypeName =
        def.getFullResponseTypeDefinition(_parser).tokenInfo.token;
    final isCE = def.isCaptureErrors(_parser);
    final args = _getMethodArgs(def);
    final queryText = _gqlSerializer.serializeQueryDefinition(def);

    final innerStatements = [
      _generateVariables(def),
      "const $svQuery = '${queryText}';",
      'const $svFragmentNames = ${_fragmentNamesExpr(def)};',
      _executeFull(def, fullResponseTypeName),
      "const gl_fullResponse__ = ${_fromJson(svResult, fullResponseTypeName)};",
      if (!isCE)
        _cg.ifStatement(
          condition: 'gl_fullResponse__.errors',
          ifBlockStatements: observables
              ? ['subscriber.error(gl_fullResponse__.errors);', 'return;']
              : ['throw gl_fullResponse__.errors;'],
        ),
      if (observables) ...[
        isCE
            ? "subscriber.next(gl_fullResponse__);"
            : "subscriber.next(gl_fullResponse__.data!);",
        'subscriber.complete();',
      ] else
        isCE
            ? 'return gl_fullResponse__;'
            : "return gl_fullResponse__.data!;",
    ];

    if (observables) {
      return _cg.createMethod(
        methodName: def.codeName,
        returnType: 'Observable<$returnTypeName>',
        async: false,
        arguments: args.isEmpty ? null : args,
        statements: [
          'return ${_cg.observableExpr(returnTypeName, [_cg.iife(innerStatements)])};',
        ],
      );
    }

    return _cg.createMethod(
      methodName: def.codeName,
      returnType: returnTypeName,
      async: true,
      arguments: args.isEmpty ? null : args,
      statements: innerStatements,
    );
  }

  String _cachedQueryToMethod(GLQueryDefinition def) {
    final dividedQueries = _gqlSerializer.divideQueryDefinition(def, _parser);
    final returnTypeName = _returnTypeName(def);
    final fullResponseTypeName =
        def.getFullResponseTypeDefinition(_parser).tokenInfo.token;
    final isCE = def.isCaptureErrors(_parser);
    // cacheHitValue: for non-CE this is the data map; for CE it's the full response shape.
    final cacheHitValue =
        isCE ? '{ data: $svResponseMap, errors: null }' : svResponseMap;
    final parseAndCacheCall = _cg.callExpression('this._parseAndCache', [
      svResponseText,
      svResponseMap,
      svRemaining,
      if (isCE) 'true',
    ]);

    final args = _getMethodArgs(def);
    final hasFrags = def.fragments(_parser).isNotEmpty;
    final directives = _gqlSerializer
        .serializeDirectiveValueList(def.getDirectives(skipGenerated: true));

    final cacheHitReturn = 'return ${_fromJson(cacheHitValue, returnTypeName)};';
    final cacheHitNext = 'subscriber.next(${_fromJson(cacheHitValue, returnTypeName)});';

    final cacheEntryHandler = _cg.block([
      _cg.ifStatement(condition: '!entry', ifBlockStatements: ['return;']),
      _cg.ifStatement(
        condition: 'entry.stale',
        ifBlockStatements: ['$svStaleData[pq.elementKey] = JSON.parse(entry.data);'],
        elseBlockStatements: ['$svResponseMap[pq.elementKey] = JSON.parse(entry.data);'],
      ),
    ]);
    final cacheFuturesChain = [
      '.filter(pq => pq.ttl > 0)',
      '.map(pq => ${_cg.callExpression('this._getFromCache', ['pq.cacheKey!', 'pq.tags', 'pq.staleIfOffline'])}.then(entry => $cacheEntryHandler).catch(() => ${_cg.block([])}));',
    ].join('\n').ident();

    final innerStatements = [
      _generateVariables(def),
      'const $svPartialQueries = ${_cg.arrayLiteral(dividedQueries.map((dq) => _serializePartialQuery(dq, hasFrags)).toList())};',
      'const $svResponseMap: Record<string, unknown> = {};',
      'const $svStaleData: Record<string, unknown> = {};',
      'const $svCacheFutures = $svPartialQueries\n$cacheFuturesChain',
      'await Promise.all($svCacheFutures);',
      'const $svRemaining = $svPartialQueries.filter(pq => !(pq.elementKey in $svResponseMap));',
      _cg.ifStatement(
        condition: '$svRemaining.length === 0',
        ifBlockStatements: [
          observables ? cacheHitNext : cacheHitReturn,
          if (observables) ...['subscriber.complete();', 'return;'],
        ],
      ),
      'const $svPayload = ${_cg.callExpression('this._buildPayload', [
        svRemaining,
        "'${def.tokenInfo}'",
        directives.isEmpty ? "''" : "'$directives'",
      ])};',
      _cg.tryCatchFinally(
        tryStatements: [
          'const $svResponseText = await this._glCallAdapter($svPayload);',
          'const $svResult = $parseAndCacheCall as unknown as $fullResponseTypeName;',
          if (observables) ...[
            isCE
                ? "subscriber.next(${_fromJson(svResult, returnTypeName)});"
                : "subscriber.next(${_fromJson("$svResult['data']", returnTypeName)});",
            'subscriber.complete();',
          ] else
            isCE
                ? 'return ${_fromJson(svResult, returnTypeName)};'
                : "return ${_fromJson("$svResult['data']", returnTypeName)};",
        ],
        catchVariable: 'e',
        catchStatements: [
          'Object.assign($svResponseMap, $svStaleData);',
          'const $svRemainingCount = $svPartialQueries.filter(pq => !(pq.elementKey in $svResponseMap)).length;',
          _cg.ifStatement(
            condition: '$svRemainingCount > 0',
            ifBlockStatements: [
              if (observables) ...['subscriber.error(e);', 'return;'] else 'throw e;',
            ],
          ),
          if (observables) ...[
            cacheHitNext,
            'subscriber.complete();',
          ] else
            cacheHitReturn,
        ],
      ),
    ];

    if (observables) {
      return _cg.createMethod(
        methodName: def.codeName,
        returnType: 'Observable<$returnTypeName>',
        async: false,
        arguments: args.isEmpty ? null : args,
        statements: [
          'return ${_cg.observableExpr(returnTypeName, [_cg.iife(innerStatements)])};',
        ],
      );
    }

    return _cg.createMethod(
      methodName: def.codeName,
      returnType: returnTypeName,
      async: true,
      arguments: args.isEmpty ? null : args,
      statements: innerStatements,
    );
  }

  // ── Mutation method ───────────────────────────────────────────────────────

  String mutationToMethod(GLQueryDefinition def) {
    if (_isUploadMutation(def)) return uploadMutationToMethod(def);

    final returnTypeName = _returnTypeName(def);
    final fullResponseTypeName =
        def.getFullResponseTypeDefinition(_parser).tokenInfo.token;
    final isCaptureErrors = def.isCaptureErrors(_parser);
    final args = _getMethodArgs(def);
    final invalidation = _serializeInvalidation(def);
    final queryText = _gqlSerializer.serializeQueryDefinition(def);

    final statements = <String>[
      _generateVariables(def),
      "const $svQuery = '${queryText}';",
      'const $svFragmentNames = ${_fragmentNamesExpr(def)};',
    ];

    statements.addAll([
      _executeFull(def, fullResponseTypeName),
      "const gl_fullResponse__ = ${_fromJson(svResult, fullResponseTypeName)};",
      if (!isCaptureErrors)
        _cg.ifStatement(
          condition: 'gl_fullResponse__.errors',
          ifBlockStatements: observables
              ? ['subscriber.error(gl_fullResponse__.errors);', 'return;']
              : ['throw gl_fullResponse__.errors;'],
        ),
      if (invalidation.isNotEmpty)
        isCaptureErrors
            ? _cg.ifStatement(
                condition: "!gl_fullResponse__.errors",
                ifBlockStatements: [invalidation],
              )
            : invalidation,
      if (observables) ...[
        isCaptureErrors
            ? "subscriber.next(gl_fullResponse__);"
            : "subscriber.next(gl_fullResponse__.data!);",
        "subscriber.complete();",
      ] else
        isCaptureErrors
            ? "return gl_fullResponse__;"
            : "return gl_fullResponse__.data!;",
    ]);

    if (observables) {
      return _cg.createMethod(
        methodName: def.codeName,
        returnType: 'Observable<$returnTypeName>',
        async: false,
        arguments: args.isEmpty ? null : args,
        statements: [
          'return ${_cg.observableExpr(returnTypeName, [_cg.iife(statements)])};',
        ],
      );
    }

    return _cg.createMethod(
      methodName: def.codeName,
      returnType: returnTypeName,
      async: true,
      arguments: args.isEmpty ? null : args,
      statements: statements,
    );
  }

  // ── Multipart mutation method ─────────────────────────────────────────────

  String uploadMutationToMethod(GLQueryDefinition def) {
    final returnTypeName = def.getGeneratedTypeDefinition().tokenInfo.token;
    final fullResponseTypeName = def.getFullResponseTypeDefinition(_parser).tokenInfo.token;
    final args = _getMethodArgs(def);
    final invalidation = _serializeInvalidation(def);
    final uploadNames = _parser.uploadScalarNames;
    final uploadArgs = def.arguments
        .where((a) => uploadNames.contains(a.type.firstType.token))
        .toList();
    final queryTextUp = _gqlSerializer.serializeQueryDefinition(def);

    final statements = <String>[
      _generateVariables(def, nullifyUploads: true),
      "const $svQuery = '${queryTextUp}';",
      'const $svFragmentNames = ${_fragmentNamesExpr(def)};',
      _assembleQuery(),
    ];

    statements.addAll([
      "const $svMap: Record<string, string[]> = {};",
      "const $svParts: Record<string, unknown> = {};",
      "let $svSlot = 0;",
    ]);

    for (final arg in uploadArgs) {
      final wireKey = arg.bareName;
      final codeRef = arg.codeName;
      if (arg.type.isList) {
        statements.addAll([
          _cg.forLoop(
            init: 'let _i = 0',
            condition: '_i < args.$codeRef.length',
            increment: '_i++',
            statements: [
              "$svMap[String($svSlot + _i)] = ['variables.$wireKey.' + _i];",
              "$svParts[String($svSlot + _i)] = args.$codeRef[_i];",
            ],
          ),
          "$svSlot += args.$codeRef.length;",
        ]);
      } else {
        statements.addAll([
          "$svMap[String($svSlot)] = ['variables.$wireKey'];",
          "$svParts[String($svSlot)] = args.$codeRef;",
          "$svSlot++;",
        ]);
      }
    }

    final innerStatements = [
      'const $svAllParts: Record<string, unknown> = ${_cg.block([
        "'operations': JSON.stringify(${_cg.block([
          'query: $svFullQuery,',
          "operationName: '${def.tokenInfo}',",
          'variables: $svVariables,',
        ])}),",
        "'map': JSON.stringify($svMap),",
        '...$svParts,',
      ])};',
      'const $svResponse = await ${_cg.callExpression('this.$svMultipartAdapter!', [svAllParts, 'onProgress'])};',
      "const $svResult = JSON.parse($svResponse);",
      "const gl_fullResponse__ = ${_fromJson(svResult, fullResponseTypeName)};",
      _cg.ifStatement(
        condition: 'gl_fullResponse__.errors',
        ifBlockStatements: ['throw gl_fullResponse__.errors;'],
      ),
      if (invalidation.isNotEmpty) invalidation,
      if (observables) ...[
        "subscriber.next(gl_fullResponse__.data!);",
        "subscriber.complete();",
      ] else
        "return gl_fullResponse__.data!;",
    ];
    statements.addAll(innerStatements);

    if (observables) {
      return _cg.createMethod(
        methodName: def.codeName,
        returnType: 'Observable<$returnTypeName>',
        async: false,
        arguments: args.isEmpty ? null : args,
        statements: [
          'return ${_cg.observableExpr(returnTypeName, [_cg.iife(statements)])};',
        ],
      );
    }

    return _cg.createMethod(
      methodName: def.codeName,
      returnType: returnTypeName,
      async: true,
      arguments: args.isEmpty ? null : args,
      statements: statements,
    );
  }

  // ── Subscription method ───────────────────────────────────────────────────

  String subscriptionToMethod(GLQueryDefinition def) {
    final returnTypeName = def.getGeneratedTypeDefinition().tokenInfo.token;
    final queryArgs = _getMethodArgs(def);
    final queryTextSub = _gqlSerializer.serializeQueryDefinition(def);

    final statements = <String>[
      _generateVariables(def),
      "const $svQuery = '${queryTextSub}';",
      'const $svFragmentNames = ${_fragmentNamesExpr(def)};',
      _assembleQuery(),
      'const $svPayload: GraphLinkPayload = ${_cg.block([
        'query: $svFullQuery,',
        "operationName: '${def.tokenInfo}',",
        'variables: $svVariables,',
      ])};',
      'const $svGen = this.$svHandler.handle($svPayload);',
    ];

    if (observables) {
      statements.add('return ${_cg.observableExpr(returnTypeName, [
        _cg.iife([
          _cg.tryCatchFinally(
            tryStatements: [
              _cg.forAwaitLoop(
                variable: svData,
                iterable: svGen,
                statements: ['subscriber.next(${_fromJson(svData, returnTypeName)});'],
              ),
              'subscriber.complete();',
            ],
            catchStatements: ['subscriber.error(e);'],
          ),
        ]),
        _cancelSubscription,
      ])};');

      return _cg.createMethod(
        methodName: def.codeName,
        returnType: 'Observable<$returnTypeName>',
        arguments: queryArgs.isEmpty ? null : queryArgs,
        statements: statements,
      );
    }

    statements.addAll([
      _cg.iife([
        _cg.tryCatchFinally(
          tryStatements: [
            _cg.forAwaitLoop(
              variable: svData,
              iterable: svGen,
              statements: ['onEvent(${_fromJson(svData, returnTypeName)});'],
            ),
          ],
          catchStatements: ['onError?.(e);'],
        ),
      ]),
      _cancelSubscription,
    ]);

    final allArgs = [
      ...queryArgs,
      'onEvent: (data: $returnTypeName) => void',
      'onError?: (error: unknown) => void',
    ];

    return _cg.createMethod(
      methodName: def.codeName,
      returnType: '() => void',
      arguments: allArgs,
      statements: statements,
    );
  }

  // ── Partial query serialization ───────────────────────────────────────────

  String _serializePartialQuery(DividedQuery dq, bool hasFrags) {
    final variables = _cg.block([
      for (final v in dq.variables)
        if (v.startsWith(r'$')) "'${v.substring(1)}': $svVariables['${v.substring(1)}'],",
    ]);
    final fragSet = hasFrags && dq.fragmentNames.isNotEmpty
        ? 'new Set(${_cg.arrayLiteral(dq.fragmentNames.map((n) => "'$n'").toList())})'
        : 'new Set<string>()';
    final args = [
      "'${dq.query}'",
      variables,
      '${dq.cacheTTL}',
      _cg.arrayLiteral(dq.tags.map((t) => "'$t'").toList()),
      "'${dq.operationName}'",
      "'${dq.elementKey}'",
      fragSet,
      _cg.arrayLiteral(dq.argumentDeclarations.map((a) => "'$a'").toList()),
      '${dq.staleIfOffline}',
    ];
    return 'new GraphLinkPartialQuery(\n${args.join(',\n').ident()}\n)';
  }

  // ── Variable generation ────────────────────────────────────────────────────

  String _generateVariables(GLQueryDefinition def, {bool nullifyUploads = false}) {
    final uploadNames = nullifyUploads ? _parser.uploadScalarNames : <String>{};
    final entries = <String>[];
    for (final arg in def.arguments) {
      final wireKey = arg.bareName;
      final codeRef = arg.codeName;
      if (arg.hoistArgsInput != null) {
        // Synthetic hoist arg: spread the <Op>FieldArgs object directly — its
        // properties already are the wire variables. Optional object → fall back
        // to {} when null, leaving those vars absent (document defaults apply).
        final base = 'args.$codeRef';
        entries.add(arg.type.nullable ? '...($base ?? {}),' : '...$base,');
      } else if (uploadNames.contains(arg.type.firstType.token)) {
        entries.add("'$wireKey': ${arg.type.isList ? 'args.$codeRef.map(() => null)' : 'null'},");
      } else if (arg.defaultValue != null) {
        final lit = _serializer.serializeDefaultLiteral(arg.type, arg.defaultValue!.value);
        // The TS param is optional (`?:`) because of the default value, even
        // when the GraphQL type itself is non-null — so `args.$codeRef` can be
        // `undefined` at runtime. Force the toJson call to null-guard too.
        final jsonType = arg.type.nullable ? arg.type : GLType.makeNullable(arg.type);
        final jsonExpr = _serializer.callToJson('args.$codeRef', jsonType);
        entries.add("'$wireKey': ($jsonExpr) ?? $lit,");
      } else {
        entries.add("'$wireKey': ${_serializer.callToJson('args.$codeRef', arg.type)},");
      }
    }
    return 'const $svVariables: Record<string, unknown> = ${_cg.block(entries)};';
  }

  // ── Method arguments ──────────────────────────────────────────────────────

  List<String> _getMethodArgs(GLQueryDefinition def) {
    final result = <String>[];
    if (def.arguments.isNotEmpty) {
      final members = def.arguments.map((arg) {
        final tsType = _resolveArgType(arg);
        final optional =
            (arg.type.nullable || arg.defaultValue != null) ? '?' : '';
        return '${arg.codeName}$optional: $tsType;';
      }).toList();
      result.add('args: ${_cg.block(members)}');
    }
    if (_isUploadMutation(def)) {
      result.add('onProgress?: UploadProgressCallback');
    }
    return result;
  }

  String _resolveArgType(arg) {
    final uploadNames = _parser.uploadScalarNames;
    if (uploadNames.contains(arg.type.firstType.token)) {
      return arg.type.isList ? 'GLUpload[]' : 'GLUpload';
    }
    return _serializer.serializeType(arg.type);
  }

  // ── Invalidation ──────────────────────────────────────────────────────────

  String _serializeInvalidation(GLQueryDefinition def) {
    if (_shouldInvalidateAll(def)) {
      return 'await this.$svStore.invalidateAll();';
    }
    final tags = _getInvalidationTags(def);
    if (tags.isNotEmpty) {
      return '${_cg.callExpression('await this._invalidateByTags', [
        _cg.arrayLiteral(tags.map((t) => "'$t'").toList()),
      ])};';
    }
    return '';
  }
}
