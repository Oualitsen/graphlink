import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/capture_errors_utils.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/kotlin_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_context.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_vars.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_imports.dart';

const _clientException = 'GraphLinkException';
const _flow = 'Flow';

class KotlinClientOperationSerializer {
  final KotlinClientContext _ctx;

  KotlinClientOperationSerializer(this._ctx);

  // ── Query (cache-aware) ────────────────────────────────────────────────────

  String queryToMethod(GLQueryDefinition def, GLImportContainer container) {
    final dividedQueries = _ctx.gqlSerializer.divideQueryDefinition(def, _ctx.grammar);
    if (dividedQueries.every((e) => e.cacheTTL == 0)) {
      return _simpleQueryToMethod(def, container, dividedQueries);
    }
    return _cachedQueryToMethod(def, container, dividedQueries);
  }

  String _simpleQueryToMethod(GLQueryDefinition def, GLImportContainer container,
      List<DividedQuery> dividedQueries) {
    final parseType = def.getFullResponseTypeDefinition(_ctx.grammar).token;
    final isCE = def.isCaptureErrors(_ctx.grammar);
    final queryString = _ctx.gqlSerializer.serializeQueryDefinition(def).escapeForStringLiteral();
    final fragmentNames = def.fragments(_ctx.grammar)
        .map((f) => '"${f.tokenInfo.token}"').toSet();

    final statements = <String>[
      _generateVariables(def, container),
      _ctx.codeGenUtils.constDecl(svQuery, '"$queryString"'),
      _ctx.codeGenUtils.constDecl(svFragmentNames, '${fragmentNames.isEmpty ? "emptySet<String>()" : "setOf(${fragmentNames.join(", ")})"}'),
      if (isCE)
        'return ${_ctx.codeGenUtils.callExpression('executeFull', ['${svQuery}', '${svFragmentNames}', '"${def.tokenInfo}"', '${_variablesExpr(def)}', '{ $parseType.fromJson(it) }'])}'
      else
        'return executeData(${svQuery}, ${svFragmentNames}, "${def.tokenInfo}", ${_variablesExpr(def)}, { $parseType.fromJson(it) }).data!!',
    ];

    return _ctx.codeGenUtils.suspendFun(
      name: def.codeName,
      arguments: getArguments(def),
      returnType: returnTypeByQueryType(def),
      statements: statements,
    );
  }

  String _cachedQueryToMethod(GLQueryDefinition def, GLImportContainer container,
      List<DividedQuery> dividedQueries) {
    final directives = _ctx.gqlSerializer
        .serializeDirectiveValueList(def.getDirectives(skipGenerated: true));
    final parseType = def.getFullResponseTypeDefinition(_ctx.grammar).token;
    final isCE = def.isCaptureErrors(_ctx.grammar);

    final statements = <String>[
      _generateVariables(def, container),
      _ctx.codeGenUtils.constDecl(svPartialQueries, 'mutableListOf<GraphLinkPartialQuery>()'),
      ...dividedQueries.map(_serializePartialQueryKotlin),
      'return executeCached(${svPartialQueries}, "${def.tokenInfo}", "$directives", { $parseType.fromJson(it) }, ${isCE ? 'true' : 'false'})${_dataCall(isCE)}',
    ];

    return _ctx.codeGenUtils.suspendFun(
      name: def.codeName,
      arguments: getArguments(def),
      returnType: returnTypeByQueryType(def),
      statements: statements,
    );
  }

  String _dataCall(bool isCE) => isCE ? '' : '.data!!';

  // ── Mutation ───────────────────────────────────────────────────────────────

  String mutationToMethod(GLQueryDefinition def, GLImportContainer container) {
    final methodName = def.codeName;
    final wireName = def.tokenInfo.token;

    if (_ctx.grammar.mutationHasUploads(def)) {
      return _uploadMutationMethod(def, container);
    }

    final isCE = def.isCaptureErrors(_ctx.grammar);
    final fullResponseToken = def.getFullResponseTypeDefinition(_ctx.grammar).token;
    final queryText = _ctx.gqlSerializer.serializeQueryDefinition(def).escapeForStringLiteral();
    final fragmentNames = def.fragments(_ctx.grammar)
        .map((f) => '"${f.tokenInfo.token}"')
        .toSet();

    final invalidation = _serializeInvalidationCall(def);
    final statements = [
      _ctx.codeGenUtils.constDecl(svQuery, '"${queryText}"'),
      _ctx.codeGenUtils.constDecl(svFragmentNames, '${fragmentNames.isEmpty ? "emptySet<String>()" : "setOf(${fragmentNames.join(", ")})"}'),
      _generateVariables(def, container),
      // plain mutations build the payload inside executeData/executeFull
      if (!isCE) ...[
        _ctx.codeGenUtils.constDecl(svDecodedResponse, _ctx.codeGenUtils.callExpression('executeData', ['${svQuery}', '${svFragmentNames}', '"$wireName"', '${_variablesExpr(def)}', '{ $fullResponseToken.fromJson(it) }'])),
        if (invalidation.isNotEmpty) invalidation,
        'return ${svDecodedResponse}.data!!',
      ] else ...[
        _ctx.codeGenUtils.constDecl(svDecodedResponse, _ctx.codeGenUtils.callExpression('executeFull', ['${svQuery}', '${svFragmentNames}', '"$wireName"', '${_variablesExpr(def)}', '{ $fullResponseToken.fromJson(it) }'])),
        if (def.invalidateCacheTags.isNotEmpty)
          _ctx.codeGenUtils.ifStatement(
            condition: '${svDecodedResponse}.errors == null',
            ifBlockStatements: [invalidation],
          ),
        'return ${svDecodedResponse}',
      ],
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
          condition: '${svDecodedResponse}.errors != null && ${svDecodedResponse}.errors.isNotEmpty()',
          ifBlockStatements: ['throw $_clientException(${svDecodedResponse}.errors)'],
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
    final methodName = def.codeName;
    final opWireName = def.tokenInfo.token;
    final isCE = def.isCaptureErrors(_ctx.grammar);
    final fullResponseToken = def.getFullResponseTypeDefinition(_ctx.grammar).token;
    final uploadNames = _ctx.grammar.uploadScalarNames;
    final uploadArgs = def.arguments
        .where((a) => uploadNames.contains(a.type.firstType.token))
        .toList();
    final hasListArg = uploadArgs.any((a) => a.type.isList);

    final queryTextUp = _ctx.gqlSerializer.serializeQueryDefinition(def).escapeForStringLiteral();
    final fragmentNamesUp = def.fragments(_ctx.grammar)
        .map((f) => '"${f.tokenInfo.token}"')
        .toSet();

    final body = [
      _ctx.codeGenUtils.constDecl(svQuery, '"${queryTextUp}"'),
      _ctx.codeGenUtils.constDecl(svFragmentNames, '${fragmentNamesUp.isEmpty ? "emptySet<String>()" : "setOf(${fragmentNamesUp.join(", ")})"}'),
      _ctx.codeGenUtils.constDecl(svFullQuery, 'assembleQuery(${svQuery}, ${svFragmentNames})'),
      _generateVariablesForUpload(def, container),
      _ctx.codeGenUtils.constDecl(svFiles, 'linkedMapOf<String, GLUpload>()'),
      _ctx.codeGenUtils.constDecl(svFileMap, 'mutableMapOf<String, Any?>()'),
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
      _ctx.codeGenUtils.constDecl(svOperationsMap, _ctx.codeGenUtils.callExpression('mapOf', ['"query" to ${svFullQuery}', '"operationName" to "$opWireName"', '"variables" to ${svVariables}'])),
      _ctx.codeGenUtils.constDecl(svOperations, '${svEncoder}.encode(${svOperationsMap})'),
      _ctx.codeGenUtils.constDecl(svMapJson, '${svEncoder}.encode(${svFileMap})'),
      _ctx.codeGenUtils.constDecl(svResponseText, _ctx.codeGenUtils.callExpression('${svMultipartAdapter}.executeMultipart', ['${svOperations}', '${svMapJson}', '${svFiles}', 'onProgress'])),
      _ctx.codeGenUtils.constDecl(svDecodedResponse, '$fullResponseToken.fromJson(${svDecoder}.decode(${svResponseText}))'),
      ..._mutationReturnStatements(def, isCE),
    ]);

    final argsNoProgress = getArguments(def);
    final argNamesNoProgress = def.arguments.map((e) => e.codeName).join(', ');
    final argsWithProgress = [...argsNoProgress, 'onProgress: UploadProgressCallback?'];

    final returnType = returnTypeByQueryType(def);

    return [
      _ctx.codeGenUtils.suspendFun(
        name: methodName,
        arguments: argsNoProgress,
        returnType: returnType,
        statements: ['return $methodName($argNamesNoProgress, null)'],
      ),
      _ctx.codeGenUtils.suspendFun(
        name: methodName,
        arguments: argsWithProgress,
        returnType: returnType,
        statements: body,
      ),
    ].join('\n\n');
  }

  // ── Subscription ───────────────────────────────────────────────────────────

  String subscriptionToMethod(GLQueryDefinition def, GLImportContainer container) {
    container.imports.add(KotlinImports.flow);
    container.imports.add(KotlinImports.flowMap);
    final typeToken = def.typeDefinition?.token ?? 'Any';
    final queryTextSub = _ctx.gqlSerializer.serializeQueryDefinition(def).escapeForStringLiteral();
    final fragmentNamesSub = def.fragments(_ctx.grammar)
        .map((f) => '"${f.tokenInfo.token}"')
        .toSet();

    final statements = [
      _ctx.codeGenUtils.constDecl(svQuery, '"${queryTextSub}"'),
      _ctx.codeGenUtils.constDecl(svFragmentNames, '${fragmentNamesSub.isEmpty ? "emptySet<String>()" : "setOf(${fragmentNamesSub.join(", ")})"}'),
      _ctx.codeGenUtils.constDecl(svFullQuery, 'assembleQuery(${svQuery}, ${svFragmentNames})'),
      _generateVariables(def, container),
      _ctx.codeGenUtils.constDecl(svPayload, _ctx.codeGenUtils.callExpression('GraphLinkPayload', ['query = ${svFullQuery}', 'operationName = "${def.tokenInfo}"', 'variables = ${_variablesExpr(def)}'])),
      'return ${KotlinCodeGenUtils.mapCall(receiver: 'handler.handle(${svPayload})', body: '$typeToken.fromJson(it)')}',
    ];

    return _ctx.codeGenUtils.createMethod(
      methodName: def.codeName,
      arguments: getArguments(def),
      returnType: '$_flow<$typeToken>',
      statements: statements,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _generateVariables(GLQueryDefinition def, GLImportContainer container) {
    if (def.arguments.isEmpty) return '';
    // Declared args build the base map; a synthetic hoist arg merges in the
    // <Op>FieldArgs object's own toJson() map (keyed by wire variable) via `+`.
    // An optional object falls back to emptyMap() when null, leaving those vars
    // absent (document defaults apply).
    final pairs = <String>[];
    final merges = <String>[];
    for (final arg in def.arguments) {
      final input = arg.hoistArgsInput;
      if (input == null) {
        pairs.add(
            '"${arg.dartArgumentName}" to ${_serializeArgumentValue(def, arg.token, container)}');
        continue;
      }
      final base = arg.codeName;
      merges.add(arg.type.nullable
          ? ' + (${base}?.toJson() ?: emptyMap())'
          : ' + ${base}.toJson()');
    }
    return _ctx.codeGenUtils.constDecl(svVariables, 'mapOf<String, Any?>(${pairs.join(', ')})${merges.join('')}');
  }

  String _variablesExpr(GLQueryDefinition def) =>
      def.arguments.isNotEmpty ? svVariables : 'emptyMap()';

  String _generateVariablesForUpload(GLQueryDefinition def, GLImportContainer container) {
    final uploadNames = _ctx.grammar.uploadScalarNames;
    final entries = def.arguments.map((e) {
      if (uploadNames.contains(e.type.firstType.token)) {
        return '"${e.dartArgumentName}" to ${e.type.isList ? 'MutableList(${e.codeName}.size) { null }' : 'null'}';
      }
      return '"${e.dartArgumentName}" to ${_serializeArgumentValue(def, e.token, container)}';
    }).join(', ');
    return _ctx.codeGenUtils.constDecl(svVariables, 'mutableMapOf<String, Any?>($entries)');
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
      _ctx.codeGenUtils.constDecl(svPqVars, 'mutableMapOf<String, Any?>()'),
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
    return _ctx.serializer.serializeType(arg.type);
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
