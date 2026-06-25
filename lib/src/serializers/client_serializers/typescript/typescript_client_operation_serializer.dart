import 'package:graphlink/src/capture_errors_utils.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_vars.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/typescript_code_gen_utils.dart';

class TypeScriptClientOperationSerializer {
  final GLParser _parser;
  final TypeScriptCodeGenUtils _cg;
  final GLGraphqlSerializer _gqlSerializer;
  final GLSerializer _serializer;
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
    final fragmentNames = def.fragments(_parser).map((f) => "'${f.tokenInfo.token}'").toSet();

    final innerStatements = [
      _generateVariables(def),
      "const $svQuery = '${queryText}';",
      "const $svFragmentNames = ${fragmentNames.isEmpty ? '[] as string[]' : '[${fragmentNames.join(", ")}]'};",
      "const $svFullQuery = this.assembleQuery($svQuery, $svFragmentNames);",
      "const $svPayload: GraphLinkPayload = { query: $svFullQuery, operationName: '${def.tokenInfo}', variables: $svVariables };",
      "const $svResponse = await this._glCallAdapter($svPayload);",
      "const $svResult = JSON.parse($svResponse) as $fullResponseTypeName;",
      if (isCE)
        _cg.ifStatement(
          condition: "!($svResult as any)['errors']",
          ifBlockStatements: ["($svResult as any)['errors'] = null;"],
        ),
      if (!isCE) _errorCheckStatement(),
      if (observables) ...[
        isCE
            ? 'subscriber.next($svResult);'
            : "subscriber.next($svResult['data'] as $returnTypeName);",
        'subscriber.complete();',
      ] else
        isCE
            ? 'return $svResult;'
            : "return $svResult['data'] as $returnTypeName;",
    ];

    if (observables) {
      return _cg.createMethod(
        methodName: def.tokenInfo.token,
        returnType: 'Observable<$returnTypeName>',
        async: false,
        arguments: args.isEmpty ? null : args,
        statements: [
          'return ${_cg.observableExpr(returnTypeName, [_cg.iife(innerStatements)])};',
        ],
      );
    }

    return _cg.createMethod(
      methodName: def.tokenInfo.token,
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
    final cacheHitValue =
        isCE ? '{ data: $svResponseMap, errors: null }' : '$svResponseMap';
    final parseAndCacheCall = isCE
        ? 'this._parseAndCache($svResponseText, $svResponseMap, $svRemaining, true)'
        : 'this._parseAndCache($svResponseText, $svResponseMap, $svRemaining)';

    final args = _getMethodArgs(def);
    final hasFrags = def.fragments(_parser).isNotEmpty;
    final directives = _gqlSerializer
        .serializeDirectiveValueList(def.getDirectives(skipGenerated: true));

    final innerStatements = [
      _generateVariables(def),
      'const $svPartialQueries = [',
      ...dividedQueries.map((dq) => '  ${_serializePartialQuery(dq, hasFrags)},'),
      '];',
      'const $svResponseMap: Record<string, unknown> = {};',
      'const $svStaleData: Record<string, unknown> = {};',
      'const $svCacheFutures = $svPartialQueries',
      '  .filter(pq => pq.ttl > 0)',
      '  .map(pq => this._getFromCache(pq.cacheKey!, pq.tags, pq.staleIfOffline).then(entry => {',
      '    if (!entry) return;',
      '    if (entry.stale) $svStaleData[pq.elementKey] = JSON.parse(entry.data);',
      '    else $svResponseMap[pq.elementKey] = JSON.parse(entry.data);',
      '  }).catch(() => {}));',
      'await Promise.all($svCacheFutures);',
      'const $svRemaining = $svPartialQueries.filter(pq => !(pq.elementKey in $svResponseMap));',
      _cg.ifStatement(
        condition: '$svRemaining.length === 0',
        ifBlockStatements: [
          '${observables ? 'subscriber.next' : 'return'}($cacheHitValue as unknown as $returnTypeName);',
          if (observables) 'subscriber.complete(); return;',
        ],
      ),
      "const $svPayload = this._buildPayload($svRemaining, '${def.tokenInfo}', ${directives.isEmpty ? "''" : "'${directives}'"}); ",
      _cg.tryCatchFinally(
        tryStatements: [
          'const $svResponseText = await this._glCallAdapter($svPayload);',
          'const $svResult = $parseAndCacheCall as unknown as $fullResponseTypeName;',
          if (observables) ...[
            isCE
                ? 'subscriber.next($svResult);'
                : "subscriber.next($svResult['data'] as $returnTypeName);",
            'subscriber.complete();',
          ] else
            isCE
                ? 'return $svResult;'
                : "return $svResult['data'] as $returnTypeName;",
        ],
        catchVariable: 'e',
        catchStatements: [
          'Object.assign($svResponseMap, $svStaleData);',
          'const $svRemainingCount = $svPartialQueries.filter(pq => !(pq.elementKey in $svResponseMap)).length;',
          _cg.ifStatement(
            condition: '$svRemainingCount > 0',
            ifBlockStatements: [
              observables ? 'subscriber.error(e); return;' : 'throw e;',
            ],
          ),
          if (observables) ...[
            'subscriber.next($cacheHitValue as unknown as $returnTypeName);',
            'subscriber.complete();',
          ] else
            'return $cacheHitValue as unknown as $returnTypeName;',
        ],
      ),
    ];

    if (observables) {
      return _cg.createMethod(
        methodName: def.tokenInfo.token,
        returnType: 'Observable<$returnTypeName>',
        async: false,
        arguments: args.isEmpty ? null : args,
        statements: [
          'return ${_cg.observableExpr(returnTypeName, [_cg.iife(innerStatements)])};',
        ],
      );
    }

    return _cg.createMethod(
      methodName: def.tokenInfo.token,
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
    final fragmentNames = def.fragments(_parser)
        .map((f) => "'${f.tokenInfo.token}'")
        .toSet();

    final statements = <String>[
      _generateVariables(def),
      "const $svQuery = '${queryText}';",
      "const $svFragmentNames = ${fragmentNames.isEmpty ? '[] as string[]' : '[${fragmentNames.join(", ")}]'};",
      "const $svFullQuery = this.assembleQuery($svQuery, $svFragmentNames);",
    ];

    statements.addAll([
      "const $svPayload: GraphLinkPayload = { query: $svFullQuery, operationName: '${def.tokenInfo}', variables: $svVariables };",
      "const $svResponse = await this._glCallAdapter($svPayload);",
      "const $svResult = JSON.parse($svResponse) as $fullResponseTypeName;",
      if (isCaptureErrors)
        _cg.ifStatement(
          condition: "!($svResult as any)['errors']",
          ifBlockStatements: ["($svResult as any)['errors'] = null;"],
        ),
      if (!isCaptureErrors) _errorCheckStatement(),
      if (invalidation.isNotEmpty)
        isCaptureErrors
            ? _cg.ifStatement(
                condition: "!($svResult as any)['errors']",
                ifBlockStatements: [invalidation],
              )
            : invalidation,
      if (observables) ...[
        isCaptureErrors
            ? "subscriber.next($svResult);"
            : "subscriber.next($svResult['data'] as $returnTypeName);",
        "subscriber.complete();",
      ] else
        isCaptureErrors
            ? "return $svResult;"
            : "return $svResult['data'] as $returnTypeName;",
    ]);

    if (observables) {
      return _cg.createMethod(
        methodName: def.tokenInfo.token,
        returnType: 'Observable<$returnTypeName>',
        async: false,
        arguments: args.isEmpty ? null : args,
        statements: [
          'return ${_cg.observableExpr(returnTypeName, [_cg.iife(statements)])};',
        ],
      );
    }

    return _cg.createMethod(
      methodName: def.tokenInfo.token,
      returnType: returnTypeName,
      async: true,
      arguments: args.isEmpty ? null : args,
      statements: statements,
    );
  }

  // ── Multipart mutation method ─────────────────────────────────────────────

  String uploadMutationToMethod(GLQueryDefinition def) {
    final returnTypeName = def.getGeneratedTypeDefinition().tokenInfo.token;
    final args = _getMethodArgs(def);
    final invalidation = _serializeInvalidation(def);
    final uploadNames = _parser.uploadScalarNames;
    final uploadArgs = def.arguments
        .where((a) => uploadNames.contains(a.type.firstType.token))
        .toList();
    final queryTextUp = _gqlSerializer.serializeQueryDefinition(def);
    final fragmentNamesUp = def.fragments(_parser)
        .map((f) => "'${f.tokenInfo.token}'")
        .toSet();
    final fragListUp = fragmentNamesUp.isEmpty ? '[] as string[]' : '[${fragmentNamesUp.join(", ")}]';

    final statements = <String>[
      _generateVariables(def, nullifyUploads: true),
      "const $svQuery = '${queryTextUp}';",
      "const $svFragmentNames = $fragListUp;",
      "const $svFullQuery = this.assembleQuery($svQuery, $svFragmentNames);",
    ];

    statements.addAll([
      "const $svMap: Record<string, string[]> = {};",
      "const $svParts: Record<string, unknown> = {};",
      "let $svSlot = 0;",
    ]);

    for (final arg in uploadArgs) {
      final name = arg.dartArgumentName;
      if (arg.type.isList) {
        statements.addAll([
          _cg.forLoop(
            init: 'let _i = 0',
            condition: '_i < args.$name.length',
            increment: '_i++',
            statements: [
              "$svMap[String($svSlot + _i)] = ['variables.$name.' + _i];",
              "$svParts[String($svSlot + _i)] = args.$name[_i];",
            ],
          ),
          "$svSlot += args.$name.length;",
        ]);
      } else {
        statements.addAll([
          "$svMap[String($svSlot)] = ['variables.$name'];",
          "$svParts[String($svSlot)] = args.$name;",
          "$svSlot++;",
        ]);
      }
    }

    final innerStatements = [
      "const $svAllParts: Record<string, unknown> = {",
      "  'operations': JSON.stringify({ query: $svFullQuery, operationName: '${def.tokenInfo}', variables: $svVariables }),",
      "  'map': JSON.stringify($svMap),",
      "  ...$svParts,",
      "};",
      "const $svResponse = await this.$svMultipartAdapter!($svAllParts, onProgress);",
      "const $svResult = JSON.parse($svResponse);",
      _errorCheckStatement(),
      if (invalidation.isNotEmpty) invalidation,
      if (observables) ...[
        "subscriber.next($svResult['data'] as $returnTypeName);",
        "subscriber.complete();",
      ] else
        "return $svResult['data'] as $returnTypeName;",
    ];
    statements.addAll(innerStatements);

    if (observables) {
      return _cg.createMethod(
        methodName: def.tokenInfo.token,
        returnType: 'Observable<$returnTypeName>',
        async: false,
        arguments: args.isEmpty ? null : args,
        statements: [
          'return ${_cg.observableExpr(returnTypeName, [_cg.iife(statements)])};',
        ],
      );
    }

    return _cg.createMethod(
      methodName: def.tokenInfo.token,
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
    final fragmentNamesSub = def.fragments(_parser)
        .map((f) => "'${f.tokenInfo.token}'")
        .toSet();

    final fragListSub = fragmentNamesSub.isEmpty ? '[] as string[]' : '[${fragmentNamesSub.join(", ")}]';
    final statements = <String>[_generateVariables(def)];
    statements.add("const $svQuery = '${queryTextSub}';");
    statements.add("const $svFragmentNames = $fragListSub;");
    statements.add("const $svFullQuery = this.assembleQuery($svQuery, $svFragmentNames);");

    statements.addAll([
      "const $svPayload: GraphLinkPayload = {",
      "  query: $svFullQuery,",
      "  operationName: '${def.tokenInfo}',",
      "  variables: $svVariables,",
      "};",
      "const $svGen = this.$svHandler.handle($svPayload);",
    ]);

    if (observables) {
      statements.add('return ${_cg.observableExpr(returnTypeName, [
        _cg.iife([
          _cg.tryCatchFinally(
            tryStatements: [
              _cg.forAwaitLoop(
                variable: svData,
                iterable: svGen,
                statements: ['subscriber.next($svData as unknown as $returnTypeName);'],
              ),
              'subscriber.complete();',
            ],
            catchStatements: ['subscriber.error(e);'],
          ),
        ]),
        'return () => { void $svGen.return(undefined); };',
      ])};');

      return _cg.createMethod(
        methodName: def.tokenInfo.token,
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
              statements: ['onEvent($svData as unknown as $returnTypeName);'],
            ),
          ],
          catchStatements: ['onError?.(e);'],
        ),
      ]),
      'return () => { void $svGen.return(undefined); };',
    ]);

    final allArgs = [
      ...queryArgs,
      'onEvent: (data: $returnTypeName) => void',
      'onError?: (error: unknown) => void',
    ];

    return _cg.createMethod(
      methodName: def.tokenInfo.token,
      returnType: '() => void',
      arguments: allArgs,
      statements: statements,
    );
  }

  // ── Partial query serialization ───────────────────────────────────────────

  String _serializePartialQuery(DividedQuery dq, bool hasFrags) {
    final varBuffer = StringBuffer('{');
    for (final v in dq.variables) {
      if (!v.startsWith(r'$')) continue;
      final argName = v.substring(1);
      varBuffer.write(" '$argName': $svVariables['$argName'],");
    }
    varBuffer.write(' }');

    final fragSet = hasFrags && dq.fragmentNames.isNotEmpty
        ? 'new Set([${dq.fragmentNames.map((n) => "'$n'").join(', ')}])'
        : 'new Set<string>()';

    return '''new GraphLinkPartialQuery(
    '${dq.query}',
    $varBuffer,
    ${dq.cacheTTL},
    [${dq.tags.map((t) => "'$t'").join(', ')}],
    '${dq.operationName}',
    '${dq.elementKey}',
    $fragSet,
    [${dq.argumentDeclarations.map((a) => "'${a}'").join(', ')}],
    ${dq.staleIfOffline},
  )''';
  }

  // ── Variable generation ────────────────────────────────────────────────────

  String _generateVariables(GLQueryDefinition def, {bool nullifyUploads = false}) {
    if (def.arguments.isEmpty) {
      return 'const $svVariables: Record<string, unknown> = {};';
    }
    final uploadNames = nullifyUploads ? _parser.uploadScalarNames : <String>{};
    final buffer = StringBuffer('const $svVariables: Record<string, unknown> = {\n');
    for (final arg in def.arguments) {
      final name = arg.dartArgumentName;
      final isUpload = uploadNames.contains(arg.type.firstType.token);
      if (isUpload) {
        buffer.writeln(
            "  '$name': ${arg.type.isList ? 'args.$name.map(() => null)' : 'null'},");
      } else if (arg.defaultValue != null) {
        final lit =
            _serializer.serializeDefaultLiteral(arg.type, arg.defaultValue!.value);
        buffer.writeln("  '$name': args.$name ?? $lit,");
      } else {
        buffer.writeln("  '$name': args.$name,");
      }
    }
    buffer.write('};');
    return buffer.toString();
  }

  // ── Method arguments ──────────────────────────────────────────────────────

  List<String> _getMethodArgs(GLQueryDefinition def) {
    final result = <String>[];
    if (def.arguments.isNotEmpty) {
      final fields = def.arguments.map((arg) {
        final tsType = _resolveArgType(arg);
        final optional =
            (arg.type.nullable || arg.defaultValue != null) ? '?' : '';
        return '${arg.dartArgumentName}$optional: $tsType';
      }).join('; ');
      result.add('args: { $fields }');
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
    return _serializer.serializeType(arg.type, false);
  }

  // ── Invalidation ──────────────────────────────────────────────────────────

  String _serializeInvalidation(GLQueryDefinition def) {
    if (_shouldInvalidateAll(def)) {
      return 'await this.$svStore.invalidateAll();';
    }
    final tags = _getInvalidationTags(def);
    if (tags.isNotEmpty) {
      return 'await this._invalidateByTags([${tags.map((t) => "'$t'").join(', ')}]);';
    }
    return '';
  }

  String _errorCheckStatement() {
    return _cg.ifStatement(
      condition: "$svResult['errors']",
      ifBlockStatements: observables
          ? ["subscriber.error($svResult['errors']);", 'return;']
          : ["throw $svResult['errors'] as GraphLinkError[];"],
    );
  }
}
