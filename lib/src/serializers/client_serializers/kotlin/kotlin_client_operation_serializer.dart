import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/capture_errors_utils.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/kotlin_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_context.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_vars.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/kotlin_imports.dart';

const _clientException = 'GraphLinkException';
const _flow = 'Flow';

class KotlinClientOperationSerializer {
  final KotlinClientContext _ctx;

  KotlinClientOperationSerializer(this._ctx);

  // ── Query (cache-aware) ────────────────────────────────────────────────────

  String queryToMethod(GLQueryDefinition def, GLImportContainer container) {
    if (_ctx.gqlSerializer.divideQueryDefinition(def, _ctx.grammar).every((e) => e.cacheTTL == 0)) {
      return _simpleQueryToMethod(def, container);
    }
    return _cachedQueryToMethod(def, container);
  }

  String _simpleQueryToMethod(GLQueryDefinition def, GLImportContainer container) {
    final parseType = def.getFullResponseTypeDefinition(_ctx.grammar).token;
    final isCE = def.isCaptureErrors(_ctx.grammar);
    final queryString = _buildQueryString(def);

    final statements = <String>[
      'val ${svOperationName} = "${def.tokenInfo}"',
      _generateVariables(def, container),
      'val ${svQuery} = "$queryString"',
      'val ${svPayload} = GraphLinkPayload.builder().query(${svQuery}).operationName(${svOperationName}).variables(${svVariables}).build()',
      'val ${svResponseText} = glCallAdapter(${svPayload})',
      if (isCE)
        'return $parseType.fromJson(${svDecoder}.decode(${svResponseText}))'
      else ...[
        'val ${svDecodedResponse} = $parseType.fromJson(${svDecoder}.decode(${svResponseText}))',
        _ctx.codeGenUtils.ifStatement(
          condition: '${svDecodedResponse}.getErrors() != null && !${svDecodedResponse}.getErrors().isEmpty()',
          ifBlockStatements: ['throw ${_clientException}.of(${svDecodedResponse}.getErrors())'],
        ),
        'return ${svDecodedResponse}.getData()',
      ],
    ];

    return _ctx.codeGenUtils.suspendFun(
      name: def.tokenInfo.token,
      arguments: getArguments(def),
      returnType: returnTypeByQueryType(def),
      statements: statements,
    );
  }

  String _cachedQueryToMethod(GLQueryDefinition def, GLImportContainer container) {
    final dividedQueries = _ctx.gqlSerializer.divideQueryDefinition(def, _ctx.grammar);
    final directives = _ctx.gqlSerializer
        .serializeDirectiveValueList(def.getDirectives(skipGenerated: true));
    final parseType = def.getFullResponseTypeDefinition(_ctx.grammar).token;
    final isCE = def.isCaptureErrors(_ctx.grammar);

    final statements = <String>[
      'val ${svOperationName} = "${def.tokenInfo}"',
      _generateVariables(def, container),
      'val ${svPartialQueries} = mutableListOf<GraphLinkPartialQuery>()',
      ...dividedQueries.map(_serializePartialQueryKotlin),
      'val ${svResponseMap} = mutableMapOf<String, Any?>()',
      'val ${svStaleData} = mutableMapOf<String, Any?>()',
      _cacheReadLoop(),
      'val ${svRemaining} = ${svPartialQueries}.filter { !${svResponseMap}.containsKey(it.elementKey) }.toMutableList()',
      _earlyReturnFromCache(parseType, isCE),
      'val ${svPayload} = buildPayload(${svRemaining}, ${svOperationName}, "$directives")',
      _ctx.codeGenUtils.tryCatchFinally(
        tryStatements: [
          'val ${svResponseText} = glCallAdapter(${svPayload})',
          'return parseToObjectAndCache(${svResponseText}, ${svResponseMap}, { $parseType.fromJson(it) }, ${svRemaining}, ${isCE ? 'true' : 'false'})${_dataCall(isCE)}',
        ],
        catchVariable: 'exception',
        catchStatements: [
          '${svResponseMap}.putAll(${svStaleData})',
          'val ${svRemainingCount} = ${svPartialQueries}.count { !${svResponseMap}.containsKey(it.elementKey) }',
          _ctx.codeGenUtils.ifStatement(
            condition: '${svRemainingCount} > 0',
            ifBlockStatements: ['throw RuntimeException(exception)'],
          ),
          'val ${svWrappedResponse} = mapOf("data" to ${svResponseMap})',
          'return $parseType.fromJson(${svWrappedResponse})${_dataCall(isCE)}',
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
      iterable: svPartialQueries,
      statements: [
        _ctx.codeGenUtils.ifStatement(
          condition: 'partQuery.ttl > 0',
          ifBlockStatements: [
            _ctx.codeGenUtils.tryCatchFinally(
              tryStatements: [
                'val ${svEntry} = getFromCache(partQuery.cacheKey, partQuery.tags, partQuery.staleIfOffline)',
                _ctx.codeGenUtils.ifStatement(
                  condition: '${svEntry} != null',
                  ifBlockStatements: [
                    _ctx.codeGenUtils.ifStatement(
                      condition: '${svEntry}.stale',
                      ifBlockStatements: [
                        '${svStaleData}[partQuery.elementKey] = ${svDecoder}.decode(${svEntry}.data)["__gl_v__"]',
                      ],
                      elseBlockStatements: [
                        '${svResponseMap}[partQuery.elementKey] = ${svDecoder}.decode(${svEntry}.data)["__gl_v__"]',
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
      condition: '${svRemaining}.isEmpty()',
      ifBlockStatements: [
        'val ${svWrappedResponse} = mapOf("data" to ${svResponseMap})',
        'return $parseType.fromJson(${svWrappedResponse})${_dataCall(isCE)}',
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
      'val ${svOperationName} = "$methodName"',
      'val ${svQuery} = "${_buildQueryString(def)}"',
      _generateVariables(def, container),
      'val ${svPayload} = GraphLinkPayload(query = ${svQuery}, operationName = ${svOperationName}, variables = ${svVariables})',
      'val ${svResponseText} = glCallAdapter(${svPayload})',
      'val ${svDecodedResponse} = $fullResponseToken.fromJson(${svDecoder}.decode(${svResponseText}))',
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
          condition: '${svDecodedResponse}.errors != null && ${svDecodedResponse}.errors!!.isNotEmpty()',
          ifBlockStatements: ['throw $_clientException(${svDecodedResponse}.errors!!)'],
        ),
        if (invalidation.isNotEmpty) invalidation,
        'return ${svDecodedResponse}.data!!',
      ];
    }
    return [
      if (def.invalidateCacheTags.isNotEmpty)
        _ctx.codeGenUtils.ifStatement(
          condition: '${svDecodedResponse}.errors == null',
          ifBlockStatements: [invalidation],
        ),
      'return ${svDecodedResponse}',
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
      'val ${svOperationName} = "$methodName"',
      'val ${svQuery} = "${_buildQueryString(def)}"',
      _generateVariablesForUpload(def, container),
      'val ${svFiles} = linkedMapOf<String, GLUpload>()',
      'val ${svFileMap} = mutableMapOf<String, Any?>()',
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
              '${svFiles}[(_slot + _i).toString()] = $name[_i]',
              '${svFileMap}[(_slot + _i).toString()] = listOf("variables.$wireName.\$_i")',
            ],
          ),
          '_slot += $name.size',
        ]);
      } else if (hasListArg) {
        body.addAll([
          '${svFiles}[_slot.toString()] = $name',
          '${svFileMap}[_slot.toString()] = listOf("variables.$wireName")',
          '_slot++',
        ]);
      } else {
        body.addAll([
          '${svFiles}["$staticIndex"] = $name',
          '${svFileMap}["$staticIndex"] = listOf("variables.$wireName")',
        ]);
        staticIndex++;
      }
    }

    body.addAll([
      'val ${svOperationsMap} = mapOf("query" to ${svQuery}, "operationName" to ${svOperationName}, "variables" to ${svVariables})',
      'val ${svOperations} = ${svEncoder}.encode(${svOperationsMap})',
      'val ${svMapJson} = ${svEncoder}.encode(${svFileMap})',
      'val ${svResponseText} = ${svMultipartAdapter}.executeMultipart(${svOperations}, ${svMapJson}, ${svFiles}, onProgress)',
      'val ${svDecodedResponse} = $fullResponseToken.fromJson(${svDecoder}.decode(${svResponseText}))',
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
      'val ${svOperationName} = "${def.tokenInfo}"',
      'val ${svQuery} = "${_buildQueryString(def)}"',
      _generateVariables(def, container),
      'val ${svPayload} = GraphLinkPayload(query = ${svQuery}, operationName = ${svOperationName}, variables = ${svVariables})',
      'return ${KotlinCodeGenUtils.mapCall(receiver: 'handler.handle(${svPayload})', body: '$typeToken.fromJson(it)')}',
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
      return 'val ${svVariables} = emptyMap<String, Any?>()';
    }
    final entries = def.arguments
        .map((e) => '"${e.dartArgumentName}" to ${_serializeArgumentValue(def, e.token, container)}')
        .join(', ');
    return 'val ${svVariables} = mapOf($entries)';
  }

  String _generateVariablesForUpload(GLQueryDefinition def, GLImportContainer container) {
    final uploadNames = _ctx.grammar.uploadScalarNames;
    final entries = def.arguments.map((e) {
      if (uploadNames.contains(e.type.firstType.token)) {
        return '"${e.dartArgumentName}" to ${e.type.isList ? 'MutableList(${e.codeName}.size) { null }' : 'null'}';
      }
      return '"${e.dartArgumentName}" to ${_serializeArgumentValue(def, e.token, container)}';
    }).join(', ');
    return 'val ${svVariables} = mutableMapOf<String, Any?>($entries)';
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
      return '${svPqVars}["$argName"] = ${svVariables}["$argName"]';
    }).toList();

    final addCall = '${svPartialQueries}.add(${_ctx.codeGenUtils.constructorCall('GraphLinkPartialQuery', [
      '"$queryStr"',
      svPqVars,
      '${e.cacheTTL}',
      tagsStr,
      '"${e.operationName}"',
      '"${e.elementKey}"',
      fragNamesStr,
      argDeclsStr,
      '${e.staleIfOffline}',
      svEncoder,
    ])})';

    return _ctx.codeGenUtils.runBlock([
      'val ${svPqVars} = mutableMapOf<String, Any?>()',
      ...varAssignments,
      addCall,
    ]);
  }

  String _serializeInvalidationCall(GLQueryDefinition def) {
    for (final e in def.elements) {
      if (e.cacheInvalidateAll) return '${svStore}.invalidateAll()';
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
