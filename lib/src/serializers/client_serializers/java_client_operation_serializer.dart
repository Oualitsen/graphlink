import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/java_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/java_client_context.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/java_imports.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/capture_errors_utils.dart';

class JavaClientOperationSerializer {
  final JavaClientContext _ctx;

  JavaClientOperationSerializer(this._ctx);

String queryToMethod(GLQueryDefinition def, GLImportContainer container) {
    final dividedQueries = _ctx.gqlSerializer.divideQueryDefinition(def, _ctx.grammar);
    final directives = _ctx.gqlSerializer
        .serializeDirectiveValueList(def.getDirectives(skipGenerated: true));
    final parseType = def.getFullResponseTypeDefinition(_ctx.grammar).token;
    container.imports.addAll([
      JavaImports.map,
      JavaImports.hashMap,
      JavaImports.list,
      JavaImports.arrayList
    ]);
    if (dividedQueries.isNotEmpty) {
      container.imports
          .addAll([JavaImports.set, JavaImports.hashSet, JavaImports.arrays]);
    }
    return _ctx.codeGenUtils.createMethod(
        returnType: 'public ${returnTypeByQueryType(def)}',
        methodName: def.tokenInfo.token,
        arguments: getArguments(def),
        statements: [
          'String ${_ctx.svOperationName} = "${def.tokenInfo}";',
          ..._defaultCoalesces(def),
          generateVariables(def, container),
          'List<GraphLinkPartialQuery> ${_ctx.svPartialQueries} = new ArrayList<>();',
          ...dividedQueries.map(serializePartialQueryJava),
          'Map<String, Object> ${_ctx.svResponseMap} = new HashMap<>();',
          'Map<String, Object> ${_ctx.svStaleData} = new HashMap<>();',
          _ctx.codeGenUtils.forEachLoop(
              variable: 'partQuery',
              iterable: '${_ctx.svPartialQueries}',
              statements: [
                _ctx.codeGenUtils.ifStatement(
                    condition: 'partQuery.ttl > 0',
                    ifBlockStatements: [
                      _ctx.codeGenUtils.tryCatchFinally(
                        tryStatements: [
                          'GraphLinkCacheEntry entry = getFromCache(partQuery.cacheKey, partQuery.tags, partQuery.staleIfOffline);',
                          _ctx.codeGenUtils.ifStatement(
                              condition: 'entry != null',
                              ifBlockStatements: [
                                _ctx.codeGenUtils.ifStatement(
                                  condition: 'entry.stale',
                                  ifBlockStatements: [
                                    '${_ctx.svStaleData}.put(partQuery.elementKey, ${_ctx.svDecoder}.decode(entry.data).get("__gl_v__"));'
                                  ],
                                  elseBlockStatements: [
                                    '${_ctx.svResponseMap}.put(partQuery.elementKey, ${_ctx.svDecoder}.decode(entry.data).get("__gl_v__"));'
                                  ],
                                ),
                              ]),
                        ],
                        catchStatements: [],
                        catchVariable: 'ignored',
                      ),
                    ]),
              ]),
          'List<GraphLinkPartialQuery> ${_ctx.svRemaining} = new ArrayList<>();',
          _ctx.codeGenUtils.forEachLoop(
              variable: 'partQuery',
              iterable: '${_ctx.svPartialQueries}',
              statements: [
                _ctx.codeGenUtils.ifStatement(
                    condition: '!${_ctx.svResponseMap}.containsKey(partQuery.elementKey)',
                    ifBlockStatements: [
                      '${_ctx.svRemaining}.add(partQuery);',
                    ]),
              ]),
          _ctx.codeGenUtils.ifStatement(
              condition: '${_ctx.svRemaining}.isEmpty()',
              ifBlockStatements: [
                'Map<String, Object> __gl_wrappedResponse__ = new HashMap<>();',
                '__gl_wrappedResponse__.put("data", ${_ctx.svResponseMap});',
                'return $parseType.fromJson(__gl_wrappedResponse__)${_getDataCall(def)};',
              ]),
          'GraphLinkPayload ${_ctx.svPayload} = buildPayload(${_ctx.svRemaining}, ${_ctx.svOperationName}, "$directives");',
          _ctx.codeGenUtils.tryCatchFinally(
            tryStatements: [
              'String ${_ctx.svResponseText} = glCallAdapter(${_ctx.svPayload});',
              'return parseToObjectAndCache(${_ctx.svResponseText}, ${_ctx.svResponseMap}, $parseType::fromJson, ${_ctx.svRemaining}, ${def.isCaptureErrors(_ctx.grammar) ? 'true': 'false'})${_getDataCall(def)};',
            ],
            catchStatements: [
              '${_ctx.svResponseMap}.putAll(${_ctx.svStaleData});',
              'long remainingCount = ${_ctx.svPartialQueries}.stream().filter(e -> !${_ctx.svResponseMap}.containsKey(e.elementKey)).count();',
              _ctx.codeGenUtils.ifStatement(
                  condition: 'remainingCount > 0',
                  ifBlockStatements: [
                    'throw new RuntimeException(exception);',
                  ]),
              'Map<String, Object> __gl_wrappedResponse__ = new HashMap<>();',
              '__gl_wrappedResponse__.put("data", ${_ctx.svResponseMap});',
              'return $parseType.fromJson(__gl_wrappedResponse__)${_getDataCall(def)};',
            ],
            catchVariable: 'exception',
          ),
        ]);
  }

  String _getDataCall(GLQueryDefinition def) {
    if(def.isCaptureErrors(_ctx.grammar)) {
      return '';
    }
    return '.getData()';
  }

  String serializePartialQueryJava(DividedQuery e) {
    final tagsStr = e.tags.isEmpty
        ? 'new ArrayList<>()'
        : 'Arrays.asList(${e.tags.map((t) => '"$t"').join(', ')})';
    final fragNamesStr = e.fragmentNames.isEmpty
        ? 'new HashSet<>()'
        : 'new HashSet<>(Arrays.asList(${e.fragmentNames.map((f) => '"$f"').join(', ')}))';
    final argDeclsStr = e.argumentDeclarations.isEmpty
        ? 'new ArrayList<>()'
        : 'Arrays.asList(${e.argumentDeclarations.map((a) => '"$a"').join(', ')})';
    final queryStr = e.query.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

    final buffer = StringBuffer();
    buffer.writeln('{');
    buffer.writeln('  Map<String, Object> pqVars = new HashMap<>();');
    for (var v in e.variables) {
      final argName = v.substring(1);
      buffer.writeln('  pqVars.put("$argName", ${_ctx.svVariables}.get("$argName"));');
    }
    buffer.writeln('  ${_ctx.svPartialQueries}.add(new GraphLinkPartialQuery(');
    buffer.writeln('    "$queryStr",');
    buffer.writeln('    pqVars,');
    buffer.writeln('    ${e.cacheTTL},');
    buffer.writeln('    $tagsStr,');
    buffer.writeln('    "${e.operationName}",');
    buffer.writeln('    "${e.elementKey}",');
    buffer.writeln('    $fragNamesStr,');
    buffer.writeln('    $argDeclsStr,');
    buffer.writeln('    ${e.staleIfOffline},');
    buffer.writeln('    ${_ctx.svEncoder}');
    buffer.writeln('  ));');
    buffer.write('}');
    return buffer.toString();
  }

  String _buildQueryString(GLQueryDefinition def) {
    final query = _ctx.gqlSerializer.serializeQueryDefinition(def);
    final frags = def.fragments(_ctx.grammar)
        .map((f) => _ctx.gqlSerializer.serializeFragmentDefinitionBase(f))
        .join(' ');
    return frags.isEmpty ? query : '$query $frags';
  }

  String mutationToMethod(GLQueryDefinition def, GLImportContainer container) {
    final returnType = 'public ${returnTypeByQueryType(def)}';
    final methodName = def.tokenInfo.token;
    final queryLine = ['String ${_ctx.svQuery} = "${_buildQueryString(def)}";'];
    container.imports
        .addAll([JavaImports.map, JavaImports.hashMap, JavaImports.arrays, JavaImports.list]);

    if (_ctx.grammar.mutationHasUploads(def)) {
      final argsNoProgress = getArguments(def);
      final argNamesNoProgress =
          def.arguments.map((e) => e.codeName).join(', ');
      final argsWithProgress = [
        ...argsNoProgress,
        'UploadProgressCallback onProgress'
      ];

      final body = _ctx.codeGenUtils.block([
        'String ${_ctx.svOperationName} = "$methodName";',
        ...queryLine,
        ..._defaultCoalesces(def),
        generateVariables(def, container),
        _serializeMultipartAdapterCall(def, container),
      ]);

      // overload without onProgress delegates to the full method with null
      final noProgressBody = _ctx.codeGenUtils.block([
        'return $methodName($argNamesNoProgress, null);',
      ]);
      container.imports.add(JavaImports.ioException);
      return [
        '$returnType $methodName${_ctx.codeGenUtils.parentheses(argsNoProgress)} throws IOException $noProgressBody',
        '$returnType $methodName${_ctx.codeGenUtils.parentheses(argsWithProgress)} throws IOException $body',
      ].join('\n\n');
    }

    return _ctx.codeGenUtils.createMethod(
        returnType: returnType,
        methodName: methodName,
        arguments: getArguments(def),
        statements: [
          'String ${_ctx.svOperationName} = "$methodName";',
          ...queryLine,
          ..._defaultCoalesces(def),
          generateVariables(def, container),
          'GraphLinkPayload ${_ctx.svPayload} = GraphLinkPayload.builder().query(${_ctx.svQuery}).operationName(${_ctx.svOperationName}).variables(${_ctx.svVariables}).build();',
          _serializeAdapterCall(def),
        ]);
  }

  String _serializeMultipartAdapterCall(
      GLQueryDefinition def, GLImportContainer container) {
    final uploadNames = _ctx.grammar.uploadScalarNames;
    final uploadArgs = def.arguments
        .where((a) => uploadNames.contains(a.type.firstType.token))
        .toList();
    final returnType = def.getFullResponseTypeDefinition(_ctx.grammar).token;
    final hasListArg = uploadArgs.any((a) => a.type.isList);
    container.imports.addAll(
        [JavaImports.linkedHashMap, JavaImports.hashMap, JavaImports.arrays]);
    final statements = <String>[
      'Map<String, GLUpload> ${_ctx.svFiles} = new LinkedHashMap<>();',
      'Map<String, Object> ${_ctx.svFileMap} = new HashMap<>();',
      if (hasListArg) 'int _slot = 0;',
    ];

    var staticIndex = 0;
    for (final arg in uploadArgs) {
      // `name` is the Java parameter identifier; `wireName` is the GraphQL
      // variable name used as the path into the `variables` JSON.
      final name = arg.codeName;
      final wireName = arg.dartArgumentName;
      if (arg.type.isList) {
        statements.add(
          _ctx.codeGenUtils.forLoop(
            init: 'int _i = 0',
            condition: '_i < $name.size()',
            increment: '_i++',
            statements: [
              '${_ctx.svFiles}.put(String.valueOf(_slot + _i), $name.get(_i));',
              '${_ctx.svFileMap}.put(String.valueOf(_slot + _i), Arrays.asList("variables.$wireName." + _i));',
            ],
          ),
        );
        statements.add('_slot += $name.size();');
      } else if (hasListArg) {
        statements.addAll([
          '${_ctx.svFiles}.put(String.valueOf(_slot), $name);',
          '${_ctx.svFileMap}.put(String.valueOf(_slot), Arrays.asList("variables.$wireName"));',
          '_slot++;',
        ]);
      } else {
        statements.addAll([
          '${_ctx.svFiles}.put("$staticIndex", $name);',
          '${_ctx.svFileMap}.put("$staticIndex", Arrays.asList("variables.$wireName"));',
        ]);
        staticIndex++;
      }
    }

    statements.addAll([
      'Map<String, Object> ${_ctx.svOperationsMap} = new HashMap<>();',
      '${_ctx.svOperationsMap}.put("query", ${_ctx.svQuery});',
      '${_ctx.svOperationsMap}.put("operationName", ${_ctx.svOperationName});',
      '${_ctx.svOperationsMap}.put("variables", ${_ctx.svVariables});',
      'String ${_ctx.svOperations} = ${_ctx.svEncoder}.encode(${_ctx.svOperationsMap});',
      'String ${_ctx.svMapJson} = ${_ctx.svEncoder}.encode(${_ctx.svFileMap});',
      'String ${_ctx.svResponseText} = ${_ctx.svMultipartAdapter}.executeMultipart(${_ctx.svOperations}, ${_ctx.svMapJson}, ${_ctx.svFiles}, onProgress);',
      '$returnType ${_ctx.svDecodedResponse} = $returnType.fromJson(${_ctx.svDecoder}.decode(${_ctx.svResponseText}));',
      if (!def.isCaptureErrors(_ctx.grammar)) ...[
        _ctx.codeGenUtils.ifStatement(
          condition: '${_ctx.svDecodedResponse}.getErrors() != null && !${_ctx.svDecodedResponse}.getErrors().isEmpty()',
          ifBlockStatements: ['throw ${clientExceptionName}.of(${_ctx.svDecodedResponse}.getErrors());'],
        ),
        _serializeInvalidationCall(def),
        'return ${_ctx.svDecodedResponse}.getData();',
      ] else ...[
        if(def.invalidateCacheTags.isNotEmpty)
          _ctx.codeGenUtils.ifStatement(
            condition: '${_ctx.svDecodedResponse}.getErrors() == null',
            ifBlockStatements: [_serializeInvalidationCall(def)],
          ),
        'return ${_ctx.svDecodedResponse};',
      ],
    ]);

    return statements.join('\n');
  }

  String subscriptionToMethod(
      GLQueryDefinition def, GLImportContainer container) {
        container.imports.addAll([JavaImports.map, JavaImports.hashMap, JavaImports.list]);
    return _ctx.codeGenUtils.createMethod(
        returnType: 'public ${returnTypeByQueryType(def)}',
        methodName: def.tokenInfo.token,
        arguments: getArguments(def),
        statements: [
          'String ${_ctx.svOperationName} = "${def.tokenInfo}";',
          'String ${_ctx.svQuery} = "${_buildQueryString(def)}";',
          ..._defaultCoalesces(def),
          generateVariables(def, container),
          "GraphLinkPayload ${_ctx.svPayload} = GraphLinkPayload.builder().query(${_ctx.svQuery}).operationName(${_ctx.svOperationName}).variables(${_ctx.svVariables}).build();",
          _serializeSubscriptionAdapterCall(def),
        ]);
  }

  List<String> _defaultCoalesces(GLQueryDefinition def) {
    return def.arguments
        .where((e) => e.defaultValue != null)
        .map((e) {
          final lit = _ctx.serializer.serializeDefaultLiteral(e.type, e.defaultValue!.value);
          return _ctx.codeGenUtils.ifStatement(
            condition: '${e.codeName} == null',
            ifBlockStatements: ['${e.codeName} = $lit;'],
          );
        })
        .toList();
  }

  String generateVariables(GLQueryDefinition def, GLImportContainer container) {
    var buffer =
        StringBuffer("Map<String, Object> ${_ctx.svVariables} = new HashMap<>();");
    buffer.writeln();
    def.arguments
        .map((e) =>
            '${_ctx.svVariables}.put("${e.dartArgumentName}", ${_serializeArgumentValue(def, e.token, container)});')
        .forEach(buffer.writeln);

    return buffer.toString();
  }

  String _serializeAdapterCall(GLQueryDefinition def) {
    switch (def.type) {
      case GLQueryType.query:
        return _serializeQueryAdapterCall(def);
      case GLQueryType.mutation:
        return _serializeMutationAdapterCall(def);
      case GLQueryType.subscription:
        return _serializeSubscriptionAdapterCall(def);
    }
  }

  String _serializeQueryAdapterCall(GLQueryDefinition def) {
    final fullResponseToken = def.getFullResponseTypeDefinition(_ctx.grammar).token;
    final isCE = def.isCaptureErrors(_ctx.grammar);
    return [
      'String ${_ctx.svResponseText} = glCallAdapter(${_ctx.svPayload});',
      '$fullResponseToken ${_ctx.svDecodedResponse} = $fullResponseToken.fromJson(${_ctx.svDecoder}.decode(${_ctx.svResponseText}));',
      if (!isCE)
        _ctx.codeGenUtils.ifStatement(
          condition: '${_ctx.svDecodedResponse}.getErrors() != null && !${_ctx.svDecodedResponse}.getErrors().isEmpty()',
          ifBlockStatements: ['throw ${clientExceptionName}.of(${_ctx.svDecodedResponse}.getErrors());'],
        ),
      if (isCE) 'return ${_ctx.svDecodedResponse};'
      else 'return ${_ctx.svDecodedResponse}.getData();',
    ].join('\n');
  }

  String _serializeMutationAdapterCall(GLQueryDefinition def) {
    final fullResponseToken = def.getFullResponseTypeDefinition(_ctx.grammar).token;
    final isCE = def.isCaptureErrors(_ctx.grammar);
    final invalidation = _serializeInvalidationCall(def);
    return [
      'String ${_ctx.svResponseText} = glCallAdapter(${_ctx.svPayload});',
      '$fullResponseToken ${_ctx.svDecodedResponse} = $fullResponseToken.fromJson(${_ctx.svDecoder}.decode(${_ctx.svResponseText}));',
      if (!isCE) ...[
        _ctx.codeGenUtils.ifStatement(
          condition: '${_ctx.svDecodedResponse}.getErrors() != null && !${_ctx.svDecodedResponse}.getErrors().isEmpty()',
          ifBlockStatements: ['throw ${clientExceptionName}.of(${_ctx.svDecodedResponse}.getErrors());'],
        ),
        invalidation,
        'return ${_ctx.svDecodedResponse}.getData();',
      ] else ...[
        if(def.invalidateCacheTags.isNotEmpty)
          _ctx.codeGenUtils.ifStatement(
            condition: '${_ctx.svDecodedResponse}.getErrors() == null',
            ifBlockStatements: [invalidation],
          ),
        'return ${_ctx.svDecodedResponse};',
      ],
    ].join('\n');
  }

  String _serializeInvalidationCall(GLQueryDefinition def) {
    for (var e in def.elements) {
      if (e.cacheInvalidateAll) {
        return '${_ctx.svStore}.invalidateAll();';
      }
    }
    final tags = def.elements.expand((e) => e.invalidateCacheTags).toSet();
    if (tags.isNotEmpty) {
      return 'invalidateByTags(Arrays.asList(${tags.map((e) => '"$e"').join(', ')}));';
    }
    return '// no tag to invalidate';
  }

  String _serializeSubscriptionAdapterCall(GLQueryDefinition def) {
    var method = _ctx.codeGenUtils.createMethod(
        methodName:
            '${subscriptionListenerRef}<Map<String, Object>> ${_ctx.svRawListener} = new ${subscriptionListenerRef}<Map<String, Object>>',
        statements: [
          '@Override',
          _ctx.codeGenUtils.createMethod(
            returnType: 'public void',
            methodName: 'onMessage',
            arguments: ['Map<String, Object> response'],
            statements: [
              'listener.onMessage(${def.typeDefinition?.token}.fromJson(response));'
            ],
          ),
          '@Override',
          _ctx.codeGenUtils.createMethod(
            returnType: 'public void',
            methodName: 'onComplete',
            arguments: [],
            statements: ['listener.onComplete();'],
          ),
          '@Override',
          _ctx.codeGenUtils.createMethod(
            returnType: 'public void',
            methodName: 'onError',
            arguments: ['${clientExceptionNameRef} error'],
            statements: ['listener.onError(error);'],
          )
        ]);
    return ['${method};', '${_ctx.svHandler}.handlePayload(${_ctx.svPayload}, ${_ctx.svRawListener});']
        .join('\n');
  }

  String _serializeArgumentValue(
      GLQueryDefinition def, String argName, GLImportContainer container) {
    var arg = def.findByName(argName);
    if (_ctx.grammar.uploadScalarNames.contains(arg.type.firstType.token)) {
      if (arg.type.isList) {
        container.imports
            .addAll([JavaImports.arrayList, JavaImports.collections]);
        return 'new ArrayList<>(Collections.nCopies(${arg.codeName}.size(), null))';
      } else {
        return 'null';
      }
    }
    return _callToJson(arg.codeName, arg.type, 0, container);
  }

  String _callToJson(String variableName, GLType type, int index,
      GLImportContainer container) {
    if (type.isList) {
      var inlineType = type.inlineType;
      String varName = "e${index}";
      var inlineCallToJson =
          _callToJson(varName, inlineType, index + 1, container);
      container.imports.add(JavaImports.collectors);
      if (varName == inlineCallToJson) {
        return JavaCodeGenUtils.streamMapCollect(receiver: variableName, nullable: type.nullable);
      }
      return JavaCodeGenUtils.streamMapCollect(
          receiver: variableName, param: varName, body: inlineCallToJson, nullable: type.nullable);
    } else if (_ctx.grammar.isEnum(type.token) || _ctx.grammar.isInput(type.token)) {
      return JavaCodeGenUtils.safeCall(variableName, "toJson()", type.nullable);
    } else {
      return variableName;
    }
  }

  String _resolveArgType(arg) {
    final uploadNames = _ctx.grammar.uploadScalarNames;
    if (uploadNames.contains(arg.type.firstType.token)) {
      return arg.type.isList ? 'List<GLUpload>' : 'GLUpload';
    }
    return _ctx.serializer.serializeType(arg.type, false);
  }

  List<String> getArguments(GLQueryDefinition def) {
    final result = def.arguments
        .map((e) => '${_resolveArgType(e)} ${e.codeName}')
        .toList();
    if (def.type == GLQueryType.subscription) {
      result.add(
          '${subscriptionListenerRef}<${def.typeDefinition?.token}> listener');
    }
    return result;
  }

  String returnTypeByQueryType(GLQueryDefinition def) {
    if (def.type == GLQueryType.subscription) {
      return "void";
    }
    if (def.isCaptureErrors(_ctx.grammar)) {
      return def.getFullResponseTypeDefinition(_ctx.grammar).token;
    }
    return def.getGeneratedTypeDefinition().token;
  }

  String serializeSubscriptions() {
    return "";
  }
}
