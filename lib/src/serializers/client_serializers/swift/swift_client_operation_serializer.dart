import 'package:graphlink/src/capture_errors_utils.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/swift/swift_client_vars.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/swift_code_gen_utils.dart';

const _clientException = 'GraphLinkException';

/// Mirrors `KotlinClientOperationSerializer`: builds the method-body string
/// for one query/mutation/subscription. Kotlin's `suspend fun` becomes
/// Swift's `func ... async throws`; `Flow<T>` becomes
/// `AsyncThrowingStream<T, Error>`; `Map<String, Any?>` becomes
/// `[String: Any?]`. No `GLImportContainer` threading is needed the way
/// Kotlin needs it — `SwiftSerializer.serializeImportToken` always returns
/// `''` (single-module output), so there's nothing for operation rendering to
/// add imports to.
class SwiftClientOperationSerializer {
  final GLParser grammar;
  final GLGraphqlSerializer gqlSerializer;
  final GLSerializer serializer;
  final SwiftCodeGenUtils codeGenUtils;

  SwiftClientOperationSerializer(this.grammar, this.gqlSerializer, this.serializer, this.codeGenUtils);

  // ── Query (cache-aware) ────────────────────────────────────────────────────

  String queryToMethod(GLQueryDefinition def) {
    final dividedQueries = gqlSerializer.divideQueryDefinition(def, grammar);
    if (dividedQueries.every((e) => e.cacheTTL == 0)) {
      return _simpleQueryToMethod(def);
    }
    return _cachedQueryToMethod(def, dividedQueries);
  }

  String _simpleQueryToMethod(GLQueryDefinition def) {
    final parseType = def.getFullResponseTypeDefinition(grammar).token;
    final isCE = def.isCaptureErrors(grammar);
    final queryString = gqlSerializer.serializeQueryDefinition(def).escapeForSwiftStringLiteral();
    final fragmentNames = def.fragments(grammar).map((f) => '"${f.tokenInfo.token}"').toSet();

    final statements = <String>[
      _generateVariables(def),
      'let $svQuery = "$queryString"',
      'let $svFragmentNames: Set<String> = ${fragmentNames.isEmpty ? '[]' : '[${fragmentNames.join(', ')}]'}',
      if (isCE)
        'return try await executeFull(query: $svQuery, fragmentNames: $svFragmentNames, operationName: "${def.tokenInfo}", variables: ${_variablesExpr(def)}, fromJson: $parseType.fromJson)'
      else
        'return try await executeData(query: $svQuery, fragmentNames: $svFragmentNames, operationName: "${def.tokenInfo}", variables: ${_variablesExpr(def)}, fromJson: $parseType.fromJson).data!',
    ];

    return 'public func ${def.codeName}${codeGenUtils.parentheses(getArguments(def))} async throws -> ${returnTypeByQueryType(def)} ${codeGenUtils.block(statements)}';
  }

  String _cachedQueryToMethod(GLQueryDefinition def, List<DividedQuery> dividedQueries) {
    final directives = gqlSerializer.serializeDirectiveValueList(def.getDirectives(skipGenerated: true));
    final parseType = def.getFullResponseTypeDefinition(grammar).token;
    final isCE = def.isCaptureErrors(grammar);

    final statements = <String>[
      _generateVariables(def),
      'var $svPartialQueries: [GraphLinkPartialQuery] = []',
      ...dividedQueries.map((e) => '$svPartialQueries.append(${_serializePartialQuery(e)})'),
      'return try await executeCached(partialQueries: $svPartialQueries, operationName: "${def.tokenInfo}", directives: "$directives", fromJson: $parseType.fromJson, captureErrors: ${isCE ? 'true' : 'false'})${isCE ? '' : '.data!'}',
    ];

    return 'public func ${def.codeName}${codeGenUtils.parentheses(getArguments(def))} async throws -> ${returnTypeByQueryType(def)} ${codeGenUtils.block(statements)}';
  }

  // ── Mutation ───────────────────────────────────────────────────────────────

  String mutationToMethod(GLQueryDefinition def) {
    if (grammar.mutationHasUploads(def)) {
      return _uploadMutationMethod(def);
    }

    final isCE = def.isCaptureErrors(grammar);
    final wireName = def.tokenInfo.token;
    final fullResponseToken = def.getFullResponseTypeDefinition(grammar).token;
    final queryText = gqlSerializer.serializeQueryDefinition(def).escapeForSwiftStringLiteral();
    final fragmentNames = def.fragments(grammar).map((f) => '"${f.tokenInfo.token}"').toSet();
    final invalidation = _serializeInvalidationCall(def);

    final statements = <String>[
      'let $svQuery = "$queryText"',
      'let $svFragmentNames: Set<String> = ${fragmentNames.isEmpty ? '[]' : '[${fragmentNames.join(', ')}]'}',
      _generateVariables(def),
      if (!isCE) ...[
        'let $svDecodedResponse = try await executeData(query: $svQuery, fragmentNames: $svFragmentNames, operationName: "$wireName", variables: ${_variablesExpr(def)}, fromJson: $fullResponseToken.fromJson)',
        if (invalidation.isNotEmpty) invalidation,
        'return $svDecodedResponse.data!',
      ] else ...[
        'let $svDecodedResponse = try await executeFull(query: $svQuery, fragmentNames: $svFragmentNames, operationName: "$wireName", variables: ${_variablesExpr(def)}, fromJson: $fullResponseToken.fromJson)',
        if (def.invalidateCacheTags.isNotEmpty)
          codeGenUtils.ifStatement(
            condition: '$svDecodedResponse.errors == nil',
            ifBlockStatements: [invalidation],
          ),
        'return $svDecodedResponse',
      ],
    ];

    return 'public func ${def.codeName}${codeGenUtils.parentheses(getArguments(def))} async throws -> ${returnTypeByQueryType(def)} ${codeGenUtils.block(statements)}';
  }

  List<String> _mutationReturnStatements(GLQueryDefinition def, bool isCE) {
    final invalidation = _serializeInvalidationCall(def);
    if (!isCE) {
      return [
        codeGenUtils.ifStatement(
          condition: 'let errors = $svDecodedResponse.errors, !errors.isEmpty',
          ifBlockStatements: ['throw $_clientException(errors: errors)'],
        ),
        if (invalidation.isNotEmpty) invalidation,
        'return $svDecodedResponse.data!',
      ];
    }
    return [
      if (def.invalidateCacheTags.isNotEmpty)
        codeGenUtils.ifStatement(
          condition: '$svDecodedResponse.errors == nil',
          ifBlockStatements: [invalidation],
        ),
      'return $svDecodedResponse',
    ];
  }

  String _uploadMutationMethod(GLQueryDefinition def) {
    final methodName = def.codeName;
    final opWireName = def.tokenInfo.token;
    final isCE = def.isCaptureErrors(grammar);
    final fullResponseToken = def.getFullResponseTypeDefinition(grammar).token;
    final uploadNames = grammar.uploadScalarNames;
    final uploadArgs = def.arguments.where((a) => uploadNames.contains(a.type.firstType.token)).toList();
    final hasListArg = uploadArgs.any((a) => a.type.isList);

    final queryTextUp = gqlSerializer.serializeQueryDefinition(def).escapeForSwiftStringLiteral();
    final fragmentNamesUp = def.fragments(grammar).map((f) => '"${f.tokenInfo.token}"').toSet();

    final body = <String>[
      'let $svQuery = "$queryTextUp"',
      'let $svFragmentNames: Set<String> = ${fragmentNamesUp.isEmpty ? '[]' : '[${fragmentNamesUp.join(', ')}]'}',
      'let $svFullQuery = assembleQuery($svQuery, fragmentNames: $svFragmentNames)',
      _generateVariablesForUpload(def),
      'var $svFiles: [String: GLUpload] = [:]',
      'var $svFileMap: [String: Any?] = [:]',
      if (hasListArg) 'var _slot = 0',
    ];

    var staticIndex = 0;
    for (final arg in uploadArgs) {
      final name = arg.codeName;
      final wireName = arg.dartArgumentName;
      if (arg.type.isList) {
        body.addAll([
          codeGenUtils.forEachLoop(
            variable: '_i',
            iterable: '0..<$name.count',
            statements: [
              '$svFiles[String(_slot + _i)] = $name[_i]',
              '$svFileMap[String(_slot + _i)] = ["variables.$wireName.\\(_i)"]',
            ],
          ),
          '_slot += $name.count',
        ]);
      } else if (hasListArg) {
        body.addAll([
          '$svFiles[String(_slot)] = $name',
          '$svFileMap[String(_slot)] = ["variables.$wireName"]',
          '_slot += 1',
        ]);
      } else {
        body.addAll([
          '$svFiles["$staticIndex"] = $name',
          '$svFileMap["$staticIndex"] = ["variables.$wireName"]',
        ]);
        staticIndex++;
      }
    }

    body.addAll([
      'let $svOperationsMap: [String: Any?] = ["query": $svFullQuery, "operationName": "$opWireName", "variables": $svVariables]',
      'let $svOperations = try GraphLinkJson.encode($svOperationsMap)',
      'let $svMapJson = try GraphLinkJson.encode($svFileMap)',
      'let $svResponseData = try await multipartAdapter($svOperations, $svMapJson, $svFiles, onProgress)',
      'let $svDecodedResponse = $fullResponseToken.fromJson(try GraphLinkJson.decode($svResponseData))',
      ..._mutationReturnStatements(def, isCE),
    ]);

    final argsNoProgress = getArguments(def);
    final argNamesNoProgress = def.arguments.map((e) => '${e.codeName}: ${e.codeName}').join(', ');
    final argsWithProgress = [...argsNoProgress, 'onProgress: UploadProgressCallback? = nil'];

    final returnType = returnTypeByQueryType(def);

    return [
      'public func $methodName${codeGenUtils.parentheses(argsNoProgress)} async throws -> $returnType ${codeGenUtils.block([
            'return try await $methodName($argNamesNoProgress, onProgress: nil)',
          ])}',
      'public func $methodName${codeGenUtils.parentheses(argsWithProgress)} async throws -> $returnType ${codeGenUtils.block(body)}',
    ].join('\n\n');
  }

  // ── Subscription ───────────────────────────────────────────────────────────

  String subscriptionToMethod(GLQueryDefinition def) {
    final rawToken = def.typeDefinition?.token;
    final typeToken = rawToken == null ? 'Any' : serializer.resolveCodeName(rawToken);
    // Interfaces don't carry their own `fromJson` — dispatch goes through
    // the paired `<Interface>Json.fromJson` namespace (same reasoning as
    // SwiftSerializer._fromJsonExpr's interface branch).
    final isInterface = rawToken != null && (grammar.interfaces.containsKey(rawToken) || grammar.projectedInterfaces.containsKey(rawToken));
    final fromJsonTarget = isInterface ? '${typeToken}Json' : typeToken;
    final queryTextSub = gqlSerializer.serializeQueryDefinition(def).escapeForSwiftStringLiteral();
    final fragmentNamesSub = def.fragments(grammar).map((f) => '"${f.tokenInfo.token}"').toSet();

    final statements = <String>[
      'let $svQuery = "$queryTextSub"',
      'let $svFragmentNames: Set<String> = ${fragmentNamesSub.isEmpty ? '[]' : '[${fragmentNamesSub.join(', ')}]'}',
      'let $svFullQuery = assembleQuery($svQuery, fragmentNames: $svFragmentNames)',
      _generateVariables(def),
      'let $svPayload = GraphLinkPayload(query: $svFullQuery, operationName: "${def.tokenInfo}", variables: ${_variablesExpr(def)})',
      'let stream = handler.handle($svPayload)',
      _serializeSubscriptionStream(fromJsonTarget),
    ];

    return 'public func ${def.codeName}${codeGenUtils.parentheses(getArguments(def))} -> ${returnTypeByQueryType(def)} ${codeGenUtils.block(statements)}';
  }

  /// `AsyncThrowingStream { continuation in ... }` — bridges [handler]'s
  /// `AsyncThrowingStream<Data, Error>` into a decoded-element stream. The
  /// `continuation in` closure header isn't representable by
  /// [SwiftCodeGenUtils.block] (which always emits a bare `{`), so this
  /// composes [SwiftCodeGenUtils.tryCatchFinally]/[SwiftCodeGenUtils.block]
  /// for the nested pieces and splices them under that one manual header.
  String _serializeSubscriptionStream(String fromJsonTarget) {
    final doCatch = codeGenUtils.tryCatchFinally(
      tryStatements: [
        'for try await msg in stream { continuation.yield($fromJsonTarget.fromJson(msg)) }',
        'continuation.finish()',
      ],
      catchStatements: ['continuation.finish(throwing: error)'],
    );
    final streamBody = [
      'let task = Task ${codeGenUtils.block([doCatch])}',
      'continuation.onTermination = { _ in task.cancel() }',
    ].join('\n').ident();

    return 'return AsyncThrowingStream { continuation in\n$streamBody\n}';
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _generateVariables(GLQueryDefinition def) {
    if (def.arguments.isEmpty) return '';
    // Declared args build the base dict; a synthetic hoist arg merges in the
    // <Op>FieldArgs input's own toJson() map (keyed by wire variable name).
    // An optional object falls back to [:] when nil, leaving those vars
    // absent (document defaults apply).
    final pairs = <String>[];
    final mergeStatements = <String>[];
    for (final arg in def.arguments) {
      final input = arg.hoistArgsInput;
      if (input == null) {
        pairs.add('"${arg.dartArgumentName}": ${_serializeArgumentValue(def, arg.token)}');
        continue;
      }
      final base = arg.codeName;
      final expr = arg.type.nullable ? '($base?.toJson() ?? [:])' : '$base.toJson()';
      mergeStatements.add('$svVariables.merge($expr) { _, new in new }');
    }
    final dict = pairs.isEmpty ? '[:]' : '[${pairs.join(', ')}]';
    if (mergeStatements.isEmpty) {
      return 'let $svVariables: [String: Any?] = $dict';
    }
    return ['var $svVariables: [String: Any?] = $dict', ...mergeStatements].join('\n');
  }

  String _variablesExpr(GLQueryDefinition def) => def.arguments.isNotEmpty ? svVariables : '[:]';

  String _generateVariablesForUpload(GLQueryDefinition def) {
    final uploadNames = grammar.uploadScalarNames;
    final entries = def.arguments.map((e) {
      if (uploadNames.contains(e.type.firstType.token)) {
        return '"${e.dartArgumentName}": ${e.type.isList ? '[Any?](repeating: nil, count: ${e.codeName}.count)' : 'nil'}';
      }
      return '"${e.dartArgumentName}": ${_serializeArgumentValue(def, e.token)}';
    }).join(', ');
    return 'var $svVariables: [String: Any?] = [$entries]';
  }

  String _serializeArgumentValue(GLQueryDefinition def, String argName) {
    final arg = def.findByName(argName);
    if (grammar.uploadScalarNames.contains(arg.type.firstType.token)) {
      return arg.type.isList ? '[Any?](repeating: nil, count: ${arg.codeName}.count)' : 'nil';
    }
    return _callToJson(arg.codeName, arg.type, 0);
  }

  String _callToJson(String variable, GLType type, int depth) {
    if (type.isList) {
      final inner = type.inlineType;
      final varName = 'e$depth';
      final innerExpr = _callToJson(varName, inner, depth + 1);
      if (varName == innerExpr) {
        // `.map { $0 as Any? }` (not a plain identity map) so the result is
        // always `[Any?]` regardless of the source element type — matching
        // what GraphLinkJson.normalize's `as? [Any?]` cast expects.
        return SwiftCodeGenUtils.safeCall(variable, 'map { \$0 as Any? }', type.nullable);
      }
      return SwiftCodeGenUtils.mapCall(
        receiver: variable,
        param: varName,
        body: innerExpr,
        chainThroughOptional: type.nullable,
      );
    }
    if (grammar.isEnum(type.token) || grammar.isInput(type.token)) {
      return SwiftCodeGenUtils.safeCall(variable, 'toJson()', type.nullable);
    }
    return variable;
  }

  String _serializePartialQuery(DividedQuery e) {
    final tagsStr = e.tags.isEmpty ? '[]' : '[${e.tags.map((t) => '"$t"').join(', ')}]';
    final fragNamesStr = e.fragmentNames.isEmpty ? '[]' : '[${e.fragmentNames.map((f) => '"$f"').join(', ')}]';
    final argDeclsStr =
        e.argumentDeclarations.isEmpty ? '[]' : '[${e.argumentDeclarations.map((a) => '"${a.escapeForSwiftStringLiteral()}"').join(', ')}]';
    final queryStr = e.query.escapeForSwiftStringLiteral();

    final varAssignments =
        e.variables.map((v) => '$svPqVars["${v.substring(1)}"] = $svVariables["${v.substring(1)}"]').toList();

    final partialQueryArgs = [
      'query: "$queryStr"',
      'variables: $svPqVars',
      'ttl: ${e.cacheTTL}',
      'tags: $tagsStr',
      'operationName: "${e.operationName}"',
      'elementKey: "${e.elementKey}"',
      'fragmentNames: Set($fragNamesStr)',
      'argumentDeclarations: $argDeclsStr',
      'staleIfOffline: ${e.staleIfOffline}',
    ].join(',\n').ident();

    final closureBody = [
      'var $svPqVars: [String: Any?] = [:]',
      ...varAssignments,
      'return GraphLinkPartialQuery(\n$partialQueryArgs\n)',
    ].join('\n').ident();

    return '{ () -> GraphLinkPartialQuery in\n$closureBody\n}()';
  }

  /// Returns a complete statement (with `try`/`await` already applied as
  /// needed), not a bare call expression — `store.invalidateAll()` is
  /// non-throwing (`GraphLinkCacheStore.invalidateAll() async`), while
  /// `invalidateByTags(...)` is `GraphLinkResolverBase`'s own `async throws`
  /// method, so the two need different prefixes at the call site.
  String _serializeInvalidationCall(GLQueryDefinition def) {
    for (final e in def.elements) {
      if (e.cacheInvalidateAll) return 'await $svStore.invalidateAll()';
    }
    final tags = def.elements.expand((e) => e.invalidateCacheTags).toSet();
    if (tags.isNotEmpty) {
      return 'try await invalidateByTags([${tags.map((t) => '"$t"').join(', ')}])';
    }
    return '';
  }

  String _resolveArgType(dynamic arg) {
    final uploadNames = grammar.uploadScalarNames;
    if (uploadNames.contains(arg.type.firstType.token)) {
      return arg.type.isList ? '[GLUpload]' : 'GLUpload';
    }
    return serializer.serializeType(arg.type);
  }

  List<String> getArguments(GLQueryDefinition def) {
    return def.arguments.map((e) {
      final type = _resolveArgType(e);
      final name = e.codeName;
      if (e.defaultValue != null) {
        final lit = serializer.serializeDefaultLiteral(e.type, e.defaultValue!.value);
        return '$name: $type = $lit';
      }
      if (e.type.nullable) return '$name: $type = nil';
      return '$name: $type';
    }).toList();
  }

  String returnTypeByQueryType(GLQueryDefinition def) {
    if (def.type == GLQueryType.subscription) {
      final rawToken = def.typeDefinition?.token;
      var elementType = rawToken == null ? 'Any' : serializer.resolveCodeName(rawToken);
      // A protocol used as a generic type parameter needs the explicit `any`
      // existential keyword in modern Swift.
      if (rawToken != null && (grammar.interfaces.containsKey(rawToken) || grammar.projectedInterfaces.containsKey(rawToken))) {
        elementType = 'any $elementType';
      }
      return 'AsyncThrowingStream<$elementType, Error>';
    }
    if (def.isCaptureErrors(grammar)) {
      return def.getFullResponseTypeDefinition(grammar).token;
    }
    return def.getGeneratedTypeDefinition().token;
  }
}
