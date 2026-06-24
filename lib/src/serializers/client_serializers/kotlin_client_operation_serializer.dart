import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/capture_errors_utils.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/kotlin_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin_client_context.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/kotlin_imports.dart';

const _clientException = 'GraphLinkException';
const _flow = 'Flow';

class KotlinClientOperationSerializer {
  final KotlinClientContext _ctx;

  KotlinClientOperationSerializer(this._ctx);

  // ── Query (cache-aware) ────────────────────────────────────────────────────

  String queryToMethod(GLQueryDefinition def, GLImportContainer container) {
    final dividedQueries = _ctx.gqlSerializer.divideQueryDefinition(def, _ctx.grammar);
    final directives = _ctx.gqlSerializer
        .serializeDirectiveValueList(def.getDirectives(skipGenerated: true));
    final parseType = def.getFullResponseTypeDefinition(_ctx.grammar).token;
    final isCE = def.isCaptureErrors(_ctx.grammar);

    final statements = <String>[
      'val ${_ctx.svOperationName} = "${def.tokenInfo}"',
      _generateVariables(def, container),
      'val ${_ctx.svPartialQueries} = mutableListOf<GraphLinkPartialQuery>()',
      ...dividedQueries.map(_serializePartialQueryKotlin),
      'val ${_ctx.svResponseMap} = mutableMapOf<String, Any?>()',
      'val ${_ctx.svStaleData} = mutableMapOf<String, Any?>()',
      _cacheReadLoop(),
      'val ${_ctx.svRemaining} = ${_ctx.svPartialQueries}.filter { !${_ctx.svResponseMap}.containsKey(it.elementKey) }.toMutableList()',
      _earlyReturnFromCache(parseType, isCE),
      'val ${_ctx.svPayload} = buildPayload(${_ctx.svRemaining}, ${_ctx.svOperationName}, "$directives")',
      _ctx.codeGenUtils.tryCatchFinally(
        tryStatements: [
          'val ${_ctx.svResponseText} = glCallAdapter(${_ctx.svPayload})',
          'return parseToObjectAndCache(${_ctx.svResponseText}, ${_ctx.svResponseMap}, { $parseType.fromJson(it) }, ${_ctx.svRemaining}, ${isCE ? 'true' : 'false'})${_dataCall(isCE)}',
        ],
        catchVariable: 'exception',
        catchStatements: [
          '${_ctx.svResponseMap}.putAll(${_ctx.svStaleData})',
          'val ${_ctx.svRemainingCount} = ${_ctx.svPartialQueries}.count { !${_ctx.svResponseMap}.containsKey(it.elementKey) }',
          _ctx.codeGenUtils.ifStatement(
            condition: '${_ctx.svRemainingCount} > 0',
            ifBlockStatements: ['throw RuntimeException(exception)'],
          ),
          'val ${_ctx.svWrappedResponse} = mapOf("data" to ${_ctx.svResponseMap})',
          'return $parseType.fromJson(${_ctx.svWrappedResponse})${_dataCall(isCE)}',
        ],
      ),
    ];

    return _ctx.codeGenUtils.suspendFun(
      name: def.tokenInfo.token,
      arguments: getArguments(def),
      returnType: returnTypeByQueryType(def),
      statements: statements,
    );
  }

  String _cacheReadLoop() {
    return _ctx.codeGenUtils.forEachLoop(
      variable: 'partQuery',
      iterable: _ctx.svPartialQueries,
      statements: [
        _ctx.codeGenUtils.ifStatement(
          condition: 'partQuery.ttl > 0',
          ifBlockStatements: [
            _ctx.codeGenUtils.tryCatchFinally(
              tryStatements: [
                'val ${_ctx.svEntry} = getFromCache(partQuery.cacheKey, partQuery.tags, partQuery.staleIfOffline)',
                _ctx.codeGenUtils.ifStatement(
                  condition: '${_ctx.svEntry} != null',
                  ifBlockStatements: [
                    _ctx.codeGenUtils.ifStatement(
                      condition: '${_ctx.svEntry}.stale',
                      ifBlockStatements: [
                        '${_ctx.svStaleData}[partQuery.elementKey] = ${_ctx.svDecoder}.decode(${_ctx.svEntry}.data)["__gl_v__"]',
                      ],
                      elseBlockStatements: [
                        '${_ctx.svResponseMap}[partQuery.elementKey] = ${_ctx.svDecoder}.decode(${_ctx.svEntry}.data)["__gl_v__"]',
                      ],
                    ),
                  ],
                ),
              ],
              catchVariable: 'ignored',
              catchStatements: [],
            ),
          ],
        ),
      ],
    );
  }

  String _earlyReturnFromCache(String parseType, bool isCE) {
    return _ctx.codeGenUtils.ifStatement(
      condition: '${_ctx.svRemaining}.isEmpty()',
      ifBlockStatements: [
        'val ${_ctx.svWrappedResponse} = mapOf("data" to ${_ctx.svResponseMap})',
        'return $parseType.fromJson(${_ctx.svWrappedResponse})${_dataCall(isCE)}',
      ],
    );
  }

  String _dataCall(bool isCE) => isCE ? '' : '.data!!';

  // ── Mutation ───────────────────────────────────────────────────────────────

  String mutationToMethod(GLQueryDefinition def, GLImportContainer container) {
    final methodName = def.tokenInfo.token;

    if (_ctx.grammar.mutationHasUploads(def)) {
      return _uploadMutationMethod(def, container);
    }

    final isCE = def.isCaptureErrors(_ctx.grammar);
    final fullResponseToken = def.getFullResponseTypeDefinition(_ctx.grammar).token;

    final statements = [
      'val ${_ctx.svOperationName} = "$methodName"',
      'val ${_ctx.svQuery} = "${_buildQueryString(def)}"',
      _generateVariables(def, container),
      'val ${_ctx.svPayload} = GraphLinkPayload(query = ${_ctx.svQuery}, operationName = ${_ctx.svOperationName}, variables = ${_ctx.svVariables})',
      'val ${_ctx.svResponseText} = glCallAdapter(${_ctx.svPayload})',
      'val ${_ctx.svDecodedResponse} = $fullResponseToken.fromJson(${_ctx.svDecoder}.decode(${_ctx.svResponseText}))',
      ..._mutationReturnStatements(def, isCE),
    ];

    return _ctx.codeGenUtils.suspendFun(
      name: methodName,
      arguments: getArguments(def),
      returnType: returnTypeByQueryType(def),
      statements: statements,
    );
  }

  List<String> _mutationReturnStatements(GLQueryDefinition def, bool isCE) {
    final invalidation = _serializeInvalidationCall(def);
    if (!isCE) {
      return [
        _ctx.codeGenUtils.ifStatement(
          condition: '${_ctx.svDecodedResponse}.errors != null && ${_ctx.svDecodedResponse}.errors!!.isNotEmpty()',
          ifBlockStatements: ['throw $_clientException(${_ctx.svDecodedResponse}.errors!!)'],
        ),
        if (invalidation.isNotEmpty) invalidation,
        'return ${_ctx.svDecodedResponse}.data!!',
      ];
    }
    return [
      if (def.invalidateCacheTags.isNotEmpty)
        _ctx.codeGenUtils.ifStatement(
          condition: '${_ctx.svDecodedResponse}.errors == null',
          ifBlockStatements: [invalidation],
        ),
      'return ${_ctx.svDecodedResponse}',
    ];
  }

  String _uploadMutationMethod(GLQueryDefinition def, GLImportContainer container) {
    final methodName = def.tokenInfo.token;
    final isCE = def.isCaptureErrors(_ctx.grammar);
    final fullResponseToken = def.getFullResponseTypeDefinition(_ctx.grammar).token;
    final uploadNames = _ctx.grammar.uploadScalarNames;
    final uploadArgs = def.arguments
        .where((a) => uploadNames.contains(a.type.firstType.token))
        .toList();
    final hasListArg = uploadArgs.any((a) => a.type.isList);

    final body = [
      'val ${_ctx.svOperationName} = "$methodName"',
      'val ${_ctx.svQuery} = "${_buildQueryString(def)}"',
      _generateVariablesForUpload(def, container),
      'val ${_ctx.svFiles} = linkedMapOf<String, GLUpload>()',
      'val ${_ctx.svFileMap} = mutableMapOf<String, Any?>()',
      if (hasListArg) 'var _slot = 0',
    ];

    var staticIndex = 0;
    for (final arg in uploadArgs) {
      // `name` is the Kotlin parameter identifier; `wireName` is the GraphQL
      // variable name used as the path into the `variables` JSON.
      final name = arg.codeName;
      final wireName = arg.dartArgumentName;
      if (arg.type.isList) {
        body.addAll([
          _ctx.codeGenUtils.forEachLoop(
            variable: '_i',
            iterable: '0 until $name.size',
            statements: [
              '${_ctx.svFiles}[(_slot + _i).toString()] = $name[_i]',
              '${_ctx.svFileMap}[(_slot + _i).toString()] = listOf("variables.$wireName.\$_i")',
            ],
          ),
          '_slot += $name.size',
        ]);
      } else if (hasListArg) {
        body.addAll([
          '${_ctx.svFiles}[_slot.toString()] = $name',
          '${_ctx.svFileMap}[_slot.toString()] = listOf("variables.$wireName")',
          '_slot++',
        ]);
      } else {
        body.addAll([
          '${_ctx.svFiles}["$staticIndex"] = $name',
          '${_ctx.svFileMap}["$staticIndex"] = listOf("variables.$wireName")',
        ]);
        staticIndex++;
      }
    }

    body.addAll([
      'val ${_ctx.svOperationsMap} = mapOf("query" to ${_ctx.svQuery}, "operationName" to ${_ctx.svOperationName}, "variables" to ${_ctx.svVariables})',
      'val ${_ctx.svOperations} = ${_ctx.svEncoder}.encode(${_ctx.svOperationsMap})',
      'val ${_ctx.svMapJson} = ${_ctx.svEncoder}.encode(${_ctx.svFileMap})',
      'val ${_ctx.svResponseText} = ${_ctx.svMultipartAdapter}.executeMultipart(${_ctx.svOperations}, ${_ctx.svMapJson}, ${_ctx.svFiles}, onProgress)',
      'val ${_ctx.svDecodedResponse} = $fullResponseToken.fromJson(${_ctx.svDecoder}.decode(${_ctx.svResponseText}))',
      ..._mutationReturnStatements(def, isCE),
    ]);

    final argsNoProgress = getArguments(def);
    final argNamesNoProgress = def.arguments.map((e) => e.codeName).join(', ');
    final argsWithProgress = [...argsNoProgress, 'onProgress: UploadProgressCallback?'];

    final noProgressBody = _ctx.codeGenUtils.block([
      'return $methodName($argNamesNoProgress, null)',
    ]);
    final fullBody = _ctx.codeGenUtils.block(body);
    final returnType = returnTypeByQueryType(def);

    return [
      'suspend fun $methodName${_ctx.codeGenUtils.parentheses(argsNoProgress)}: $returnType $noProgressBody',
      'suspend fun $methodName${_ctx.codeGenUtils.parentheses(argsWithProgress)}: $returnType $fullBody',
    ].join('\n\n');
  }

  // ── Subscription ───────────────────────────────────────────────────────────

  String subscriptionToMethod(GLQueryDefinition def, GLImportContainer container) {
    container.imports.add(KotlinImports.flow);
    container.imports.add(KotlinImports.flowMap);
    final typeToken = def.typeDefinition?.token ?? 'Any';
    final statements = [
      'val ${_ctx.svOperationName} = "${def.tokenInfo}"',
      'val ${_ctx.svQuery} = "${_buildQueryString(def)}"',
      _generateVariables(def, container),
      'val ${_ctx.svPayload} = GraphLinkPayload(query = ${_ctx.svQuery}, operationName = ${_ctx.svOperationName}, variables = ${_ctx.svVariables})',
      'return ${KotlinCodeGenUtils.mapCall(receiver: 'handler.handle(${_ctx.svPayload})', body: '$typeToken.fromJson(it)')}',
    ];

    return _ctx.codeGenUtils.createMethod(
      methodName: def.tokenInfo.token,
      arguments: getArguments(def),
      returnType: '$_flow<$typeToken>',
      statements: statements,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _buildQueryString(GLQueryDefinition def) {
    final query = _ctx.gqlSerializer.serializeQueryDefinition(def);
    final frags = def.fragments(_ctx.grammar)
        .map((f) => _ctx.gqlSerializer.serializeFragmentDefinitionBase(f))
        .join(' ');
    final raw = frags.isEmpty ? query : '$query $frags';
    // Escape $ so GraphQL variable references don't trigger Kotlin string interpolation.
    return raw.replaceAll(r'$', r'\$');
  }

  String _generateVariables(GLQueryDefinition def, GLImportContainer container) {
    if (def.arguments.isEmpty) {
      return 'val ${_ctx.svVariables} = emptyMap<String, Any?>()';
    }
    final entries = def.arguments
        .map((e) => '"${e.dartArgumentName}" to ${_serializeArgumentValue(def, e.token, container)}')
        .join(', ');
    return 'val ${_ctx.svVariables} = mapOf($entries)';
  }

  String _generateVariablesForUpload(GLQueryDefinition def, GLImportContainer container) {
    final uploadNames = _ctx.grammar.uploadScalarNames;
    final entries = def.arguments.map((e) {
      if (uploadNames.contains(e.type.firstType.token)) {
        return '"${e.dartArgumentName}" to ${e.type.isList ? 'MutableList(${e.codeName}.size) { null }' : 'null'}';
      }
      return '"${e.dartArgumentName}" to ${_serializeArgumentValue(def, e.token, container)}';
    }).join(', ');
    return 'val ${_ctx.svVariables} = mutableMapOf<String, Any?>($entries)';
  }

  String _serializeArgumentValue(GLQueryDefinition def, String argName, GLImportContainer container) {
    final arg = def.findByName(argName);
    if (_ctx.grammar.uploadScalarNames.contains(arg.type.firstType.token)) {
      return arg.type.isList
          ? 'MutableList(${arg.codeName}.size) { null }'
          : 'null';
    }
    return _callToJson(arg.codeName, arg.type, 0);
  }

  String _callToJson(String variable, GLType type, int depth) {
    if (type.isList) {
      final inner = type.inlineType;
      final varName = 'e$depth';
      final innerExpr = _callToJson(varName, inner, depth + 1);
      if (varName == innerExpr) {
        return KotlinCodeGenUtils.safeCall(variable, 'toList()', type.nullable);
      }
      return KotlinCodeGenUtils.mapCall(receiver: variable, param: varName, body: innerExpr, nullable: type.nullable);
    }
    if (_ctx.grammar.isEnum(type.token) || _ctx.grammar.isInput(type.token)) {
      return KotlinCodeGenUtils.safeCall(variable, 'toJson()', type.nullable);
    }
    return variable;
  }

  String _serializePartialQueryKotlin(DividedQuery e) {
    final tagsStr = e.tags.isEmpty
        ? 'emptyList()'
        : 'listOf(${e.tags.map((t) => '"$t"').join(', ')})';
    final fragNamesStr = e.fragmentNames.isEmpty
        ? 'emptySet()'
        : 'setOf(${e.fragmentNames.map((f) => '"$f"').join(', ')})';
    final argDeclsStr = e.argumentDeclarations.isEmpty
        ? 'emptyList()'
        : 'listOf(${e.argumentDeclarations.map((a) => '"${a.escapeForStringLiteral()}"').join(', ')})';
    final queryStr = e.query.escapeForStringLiteral();

    final varAssignments = e.variables.map((v) {
      final argName = v.substring(1);
      return '${_ctx.svPqVars}["$argName"] = ${_ctx.svVariables}["$argName"]';
    }).toList();

    final addCall = '${_ctx.svPartialQueries}.add(${_ctx.codeGenUtils.constructorCall('GraphLinkPartialQuery', [
      '"$queryStr"',
      _ctx.svPqVars,
      '${e.cacheTTL}',
      tagsStr,
      '"${e.operationName}"',
      '"${e.elementKey}"',
      fragNamesStr,
      argDeclsStr,
      '${e.staleIfOffline}',
      _ctx.svEncoder,
    ])})';

    return _ctx.codeGenUtils.runBlock([
      'val ${_ctx.svPqVars} = mutableMapOf<String, Any?>()',
      ...varAssignments,
      addCall,
    ]);
  }

  String _serializeInvalidationCall(GLQueryDefinition def) {
    for (final e in def.elements) {
      if (e.cacheInvalidateAll) return '${_ctx.svStore}.invalidateAll()';
    }
    final tags = def.elements.expand((e) => e.invalidateCacheTags).toSet();
    if (tags.isNotEmpty) {
      return 'invalidateByTags(listOf(${tags.map((t) => '"$t"').join(', ')}))';
    }
    return '';
  }

  String _resolveArgType(arg) {
    final uploadNames = _ctx.grammar.uploadScalarNames;
    if (uploadNames.contains(arg.type.firstType.token)) {
      return arg.type.isList ? 'List<GLUpload>' : 'GLUpload';
    }
    return _ctx.serializer.serializeType(arg.type, false);
  }

  List<String> getArguments(GLQueryDefinition def) {
    return def.arguments.map((e) {
      final type = _resolveArgType(e);
      final name = e.codeName;
      if (e.defaultValue != null) {
        final lit = _ctx.serializer.serializeDefaultLiteral(e.type, e.defaultValue!.value);
        return '$name: $type = $lit';
      }
      if (e.type.nullable) return '$name: $type = null';
      return '$name: $type';
    }).toList();
  }

  String returnTypeByQueryType(GLQueryDefinition def) {
    if (def.type == GLQueryType.subscription) {
      return '$_flow<${def.typeDefinition?.token ?? 'Any'}>';
    }
    if (def.isCaptureErrors(_ctx.grammar)) {
      return def.getFullResponseTypeDefinition(_ctx.grammar).token;
    }
    return def.getGeneratedTypeDefinition().token;
  }
}
