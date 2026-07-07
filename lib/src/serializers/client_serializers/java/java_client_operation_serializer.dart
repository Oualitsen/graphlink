import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_context.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_vars.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/java_imports.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/capture_errors_utils.dart';

class JavaClientOperationSerializer {
  final JavaClientContext _ctx;

  JavaClientOperationSerializer(this._ctx);

	String queryToMethod(GLQueryDefinition def, GLImportContainer container) {
	    final dividedQueries = _ctx.gqlSerializer.divideQueryDefinition(def, _ctx.grammar);
	    container.imports.addAll([JavaImports.map, JavaImports.hashMap, JavaImports.list, JavaImports.arrayList, JavaImports.collections]);
	    if (dividedQueries.isNotEmpty) {
	      container.imports.addAll([JavaImports.set, JavaImports.hashSet, JavaImports.arrays]);
	    }

	    if (dividedQueries.every((e) => e.cacheTTL == 0)) {
	      return _simpleQueryToMethod(def, container, dividedQueries);
	    }
	    return _cachedQueryToMethod(def, container, dividedQueries);
	  }

	  String _simpleQueryToMethod(GLQueryDefinition def, GLImportContainer container,
	      List<DividedQuery> dividedQueries) {
	    final parseType = def.getFullResponseTypeDefinition(_ctx.grammar).token;
	    final isCE = def.isCaptureErrors(_ctx.grammar);
	    final queryString = _ctx.gqlSerializer.serializeQueryDefinition(def);
	    final fragmentNames = def.fragments(_ctx.grammar)
	        .map((f) => '"${f.tokenInfo.token}"').toSet();

	    return _ctx.codeGenUtils.createMethod(
	        returnType: 'public ${returnTypeByQueryType(def)}',
	        methodName: def.codeName,
	        arguments: getArguments(def),
	        statements: [
	          ..._defaultCoalesces(def),
	          ..._nullChecks(def, container),
	          if (def.arguments.isNotEmpty) generateVariables(def, container),
	          'String ${svQuery} = "${queryString.escapeForJavaStringLiteral()}";',
	          'Set<String> ${svFragmentNames} = ${fragmentNames.isEmpty ? "Collections.emptySet();" : "new HashSet<>(Arrays.asList(${fragmentNames.join(", ")}));"}',
	          if (isCE)
	            'return executeFull(${svQuery}, ${svFragmentNames}, "${def.tokenInfo.token}", ${def.arguments.isEmpty ? "Collections.emptyMap()" : svVariables}, $parseType::fromJson);'
	          else
	            'return executeData(${svQuery}, ${svFragmentNames}, "${def.tokenInfo.token}", ${def.arguments.isEmpty ? "Collections.emptyMap()" : svVariables}, $parseType::fromJson)${_getDataCall(def)};',
	        ]);
	  }

	  String _cachedQueryToMethod(GLQueryDefinition def, GLImportContainer container,
	      List<DividedQuery> dividedQueries) {
	    final directives = _ctx.gqlSerializer
	        .serializeDirectiveValueList(def.getDirectives(skipGenerated: true));
	    final parseType = def.getFullResponseTypeDefinition(_ctx.grammar).token;
	    container.imports.addAll([JavaImports.list, JavaImports.arrayList]);
	    if (dividedQueries.isNotEmpty) {
	      container.imports
	          .addAll([JavaImports.set, JavaImports.hashSet, JavaImports.arrays]);
	    }
	    return _ctx.codeGenUtils.createMethod(
	        returnType: 'public ${returnTypeByQueryType(def)}',
	        methodName: def.codeName,
	        arguments: getArguments(def),
	        statements: [
	          ..._defaultCoalesces(def),
	          ..._nullChecks(def, container),
	          if (def.arguments.isNotEmpty) generateVariables(def, container),
	          'List<GraphLinkPartialQuery> ${svPartialQueries} = new ArrayList<>();',
	          ...dividedQueries.map(serializePartialQueryJava),
	          'return executeCached(${svPartialQueries}, "${def.tokenInfo.token}", "$directives", $parseType::fromJson, ${def.isCaptureErrors(_ctx.grammar) ? 'true' : 'false'})${_getDataCall(def)};',
	        ]);
	  }

  /// Tail appended to an `execute*` call to unwrap the data payload.
  /// captureErrors returns the full response (no unwrap). Blocking calls
  /// `.getData()` directly; reactive maps over the deferred-single since you
  /// can't call `.getData()` on a `Mono<Response>`.
  String _getDataCall(GLQueryDefinition def) {
    if (def.isCaptureErrors(_ctx.grammar)) {
      return '';
    }
    if (_ctx.flavor.isReactive) {
      final parseType = def.getFullResponseTypeDefinition(_ctx.grammar).token;
      return '.map($parseType::getData)';
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
    final queryStr = e.query.escapeForJavaStringLiteral();

    final buffer = StringBuffer();
    buffer.writeln('{');
    buffer.writeln('  Map<String, Object> pqVars = new HashMap<>();');
    for (var v in e.variables) {
      final argName = v.substring(1);
      buffer.writeln('  pqVars.put("$argName", ${svVariables}.get("$argName"));');
    }
    buffer.writeln('  ${svPartialQueries}.add(new GraphLinkPartialQuery(');
    buffer.writeln('    "$queryStr",');
    buffer.writeln('    pqVars,');
    buffer.writeln('    ${e.cacheTTL},');
    buffer.writeln('    $tagsStr,');
    buffer.writeln('    "${e.operationName}",');
    buffer.writeln('    "${e.elementKey}",');
    buffer.writeln('    $fragNamesStr,');
    buffer.writeln('    $argDeclsStr,');
    buffer.writeln('    ${e.staleIfOffline},');
    buffer.writeln('    ${svEncoder}');
    buffer.writeln('  ));');
    buffer.write('}');
    return buffer.toString();
  }


  String mutationToMethod(GLQueryDefinition def, GLImportContainer container) {
    final returnType = 'public ${returnTypeByQueryType(def)}';
    final methodName = def.codeName;
    final queryText = _ctx.gqlSerializer.serializeQueryDefinition(def);
    final fragmentNames = def.fragments(_ctx.grammar)
        .map((f) => '"${f.tokenInfo.token}"').toSet();
    // query + fragment-name declarations. assembleQuery / payload are only needed
    // for the upload path; plain mutations build the payload inside executeData.
    final queryLine = <String>[
      'String ${svQuery} = "${queryText.escapeForJavaStringLiteral()}";',
      if (fragmentNames.isNotEmpty)
        'Set<String> ${svFragmentNames} = new HashSet<>(Arrays.asList(${fragmentNames.join(", ")}));'
      else
        'Set<String> ${svFragmentNames} = Collections.emptySet();',
    ];
    container.imports
        .addAll([JavaImports.map, JavaImports.hashMap, JavaImports.arrays, JavaImports.list, JavaImports.set, JavaImports.hashSet, JavaImports.arrays, JavaImports.collections]);

    if (_ctx.grammar.mutationHasUploads(def)) {
      final argsNoProgress = getArguments(def);
      final argNamesNoProgress =
          def.arguments.map((e) => e.codeName).join(', ');
      final argsWithProgress = [
        ...argsNoProgress,
        'UploadProgressCallback onProgress'
      ];

      final body = _ctx.codeGenUtils.block([
        ...queryLine,
        'String ${svFullQuery} = assembleQuery(${svQuery}, ${svFragmentNames});',
        ..._defaultCoalesces(def),
        ..._nullChecks(def, container),
        if (def.arguments.isNotEmpty) generateVariables(def, container),
        _serializeMultipartAdapterCall(def, container),
      ]);

      // overload without onProgress delegates to the full method with null
      final noProgressBody = _ctx.codeGenUtils.block([
        'return $methodName($argNamesNoProgress, null);',
      ]);
      // Blocking executeMultipart throws IOException; the reactive variant
      // returns a deferred-single carrying any failure, so no checked throws.
      final throwsClause = _ctx.flavor.isReactive ? '' : ' throws IOException';
      if (!_ctx.flavor.isReactive) container.imports.add(JavaImports.ioException);
      return [
        '$returnType $methodName${_ctx.codeGenUtils.parentheses(argsNoProgress)}$throwsClause $noProgressBody',
        '$returnType $methodName${_ctx.codeGenUtils.parentheses(argsWithProgress)}$throwsClause $body',
      ].join('\n\n');
    }

    return _ctx.codeGenUtils.createMethod(
        returnType: returnType,
        methodName: methodName,
        arguments: getArguments(def),
        statements: [
          ...queryLine,
          ..._defaultCoalesces(def),
          ..._nullChecks(def, container),
          if (def.arguments.isNotEmpty) generateVariables(def, container),
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
      'Map<String, GLUpload> ${svFiles} = new LinkedHashMap<>();',
      'Map<String, Object> ${svFileMap} = new HashMap<>();',
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
              '${svFiles}.put(String.valueOf(_slot + _i), $name.get(_i));',
              '${svFileMap}.put(String.valueOf(_slot + _i), Arrays.asList("variables.$wireName." + _i));',
            ],
          ),
        );
        statements.add('_slot += $name.size();');
      } else if (hasListArg) {
        statements.addAll([
          '${svFiles}.put(String.valueOf(_slot), $name);',
          '${svFileMap}.put(String.valueOf(_slot), Arrays.asList("variables.$wireName"));',
          '_slot++;',
        ]);
      } else {
        statements.addAll([
          '${svFiles}.put("$staticIndex", $name);',
          '${svFileMap}.put("$staticIndex", Arrays.asList("variables.$wireName"));',
        ]);
        staticIndex++;
      }
    }

    statements.addAll([
      'Map<String, Object> ${svOperationsMap} = new HashMap<>();',
      '${svOperationsMap}.put("query", ${svFullQuery});',
      '${svOperationsMap}.put("operationName", "${def.tokenInfo.token}");',
      '${svOperationsMap}.put("variables", ${svVariables});',
      'String ${svOperations} = ${svEncoder}.encode(${svOperationsMap});',
      'String ${svMapJson} = ${svEncoder}.encode(${svFileMap});',
    ]);

    // Decode + error-check + invalidation + return, given a decoded String
    // body in `svResponseText`. Returns the bare value/full-response; for the
    // reactive flavors this runs inside the executeMultipart map() lambda.
    final responseHandling = <String>[
      '$returnType ${svDecodedResponse} = $returnType.fromJson(${svDecoder}.decode(${svResponseText}));',
      if (!def.isCaptureErrors(_ctx.grammar)) ...[
        _ctx.codeGenUtils.ifStatement(
          condition: '${svDecodedResponse}.getErrors() != null && !${svDecodedResponse}.getErrors().isEmpty()',
          ifBlockStatements: ['throw ${clientExceptionName}.of(${svDecodedResponse}.getErrors());'],
        ),
        _serializeInvalidationCall(def),
        'return ${svDecodedResponse}.getData();',
      ] else ...[
        if(def.invalidateCacheTags.isNotEmpty)
          _ctx.codeGenUtils.ifStatement(
            condition: '${svDecodedResponse}.getErrors() == null',
            ifBlockStatements: [_serializeInvalidationCall(def)],
          ),
        'return ${svDecodedResponse};',
      ],
    ];

    const call =
        '$svMultipartAdapter.executeMultipart($svOperations, $svMapJson, $svFiles, onProgress)';
    if (!_ctx.flavor.isReactive) {
      statements.add('String ${svResponseText} = $call;');
      statements.addAll(responseHandling);
    } else {
      // executeMultipart returns the deferred-single; compose over it.
      statements.add('return ${_ctx.flavor.mapOpen(call, svResponseText)}');
      statements.addAll(responseHandling.map((s) => '  $s'));
      statements.add('});');
    }

    return statements.join('\n');
  }

  String subscriptionToMethod(
      GLQueryDefinition def, GLImportContainer container) {
        container.imports.addAll([JavaImports.map, JavaImports.hashMap, JavaImports.list, JavaImports.set, JavaImports.hashSet, JavaImports.arrays, JavaImports.collections]);
    final queryText = _ctx.gqlSerializer.serializeQueryDefinition(def);
    final fragmentNames = def.fragments(_ctx.grammar)
        .map((f) => '"${f.tokenInfo.token}"').toSet();
    return _ctx.codeGenUtils.createMethod(
        returnType: 'public ${returnTypeByQueryType(def)}',
        methodName: def.codeName,
        arguments: getArguments(def),
        statements: [
          'String ${svQuery} = "${queryText.escapeForJavaStringLiteral()}";',
          'Set<String> ${svFragmentNames} = ${fragmentNames.isEmpty ? "Collections.emptySet();" : "new HashSet<>(Arrays.asList(${fragmentNames.join(", ")}));"}',
          'String ${svFullQuery} = assembleQuery(${svQuery}, ${svFragmentNames});',
          ..._defaultCoalesces(def),
          ..._nullChecks(def, container),
          if (def.arguments.isNotEmpty) generateVariables(def, container),
          'GraphLinkPayload ${svPayload} = GraphLinkPayload.builder().query(${svFullQuery}).operationName("${def.tokenInfo.token}").variables(${def.arguments.isEmpty ? "Collections.emptyMap()" : svVariables}).build();',
          _serializeSubscriptionAdapterCall(def),
        ]);
  }

  static const _javaPrimitives = {
    'boolean', 'byte', 'short', 'int', 'long', 'float', 'double', 'char',
  };

  List<String> _nullChecks(GLQueryDefinition def, GLImportContainer container) {
    final uploadNames = _ctx.grammar.uploadScalarNames;
    final required = def.arguments.where((e) {
      if (e.type.nullable || e.defaultValue != null) return false;
      if (uploadNames.contains(e.type.firstType.token)) return false;
      return !_javaPrimitives.contains(_ctx.serializer.serializeType(e.type));
    }).toList();
    if (required.isEmpty) return [];
    container.imports.add(JavaImports.objects);
    return required
        .map((e) => 'Objects.requireNonNull(${e.codeName}, "${e.codeName} is required");')
        .toList();
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
    if (def.arguments.isEmpty) return '';
    var buffer =
        StringBuffer("Map<String, Object> ${svVariables} = new HashMap<>();");
    buffer.writeln();
    final guardBlocks = <String>[];
    for (final arg in def.arguments) {
      final input = arg.hoistArgsInput;
      if (input == null) {
        buffer.writeln(
            '${svVariables}.put("${arg.dartArgumentName}", ${_serializeArgumentValue(def, arg.token, container)});');
        continue;
      }
      // Synthetic hoist arg: merge the <Op>FieldArgs object's own toJson() map,
      // which already maps each field to its wire variable. Optional object →
      // guard so an omitted object leaves those vars absent (document defaults
      // apply); required → merge directly.
      final base = arg.codeName;
      final put = '${svVariables}.putAll(${base}.toJson());';
      if (arg.type.nullable) {
        guardBlocks.add(_ctx.codeGenUtils
            .ifStatement(condition: '$base != null', ifBlockStatements: [put]));
      } else {
        buffer.writeln(put);
      }
    }
    for (final block in guardBlocks) {
      buffer.writeln(block);
    }
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
      'String ${svResponseText} = glCallAdapter(${svPayload});',
      '$fullResponseToken ${svDecodedResponse} = $fullResponseToken.fromJson(${svDecoder}.decode(${svResponseText}));',
      if (!isCE)
        _ctx.codeGenUtils.ifStatement(
          condition: '${svDecodedResponse}.getErrors() != null && !${svDecodedResponse}.getErrors().isEmpty()',
          ifBlockStatements: ['throw ${clientExceptionName}.of(${svDecodedResponse}.getErrors());'],
        ),
      if (isCE) 'return ${svDecodedResponse};'
      else 'return ${svDecodedResponse}.getData();',
    ].join('\n');
  }

  String _serializeMutationAdapterCall(GLQueryDefinition def) {
    final fullResponseToken = def.getFullResponseTypeDefinition(_ctx.grammar).token;
    final isCE = def.isCaptureErrors(_ctx.grammar);
    final invalidation = _serializeInvalidationCall(def);
    final varsArg =
        def.arguments.isEmpty ? "Collections.emptyMap()" : svVariables;

    // Reactive: invalidation runs as a side-effect inside map() over the
    // deferred-single, since there is no materialised response to act on first.
    if (_ctx.flavor.isReactive) {
      if (!isCE) {
        return [
          'return ${_ctx.flavor.mapOpen('executeData(${svQuery}, ${svFragmentNames}, "${def.tokenInfo.token}", $varsArg, $fullResponseToken::fromJson)', svDecodedResponse)}',
          '  $invalidation',
          '  return ${svDecodedResponse}.getData();',
          '});',
        ].join('\n');
      }
      return [
        'return ${_ctx.flavor.mapOpen('executeFull(${svQuery}, ${svFragmentNames}, "${def.tokenInfo.token}", $varsArg, $fullResponseToken::fromJson)', svDecodedResponse)}',
        if (def.invalidateCacheTags.isNotEmpty) ...[
          '  if (${svDecodedResponse}.getErrors() == null) {',
          '    $invalidation',
          '  }',
        ],
        '  return ${svDecodedResponse};',
        '});',
      ].join('\n');
    }

    if (!isCE) {
      return [
        '$fullResponseToken ${svDecodedResponse} = executeData(${svQuery}, ${svFragmentNames}, "${def.tokenInfo.token}", $varsArg, $fullResponseToken::fromJson);',
        invalidation,
        'return ${svDecodedResponse}.getData();',
      ].join('\n');
    }
    return [
      '$fullResponseToken ${svDecodedResponse} = executeFull(${svQuery}, ${svFragmentNames}, "${def.tokenInfo.token}", $varsArg, $fullResponseToken::fromJson);',
      if (def.invalidateCacheTags.isNotEmpty)
        _ctx.codeGenUtils.ifStatement(
          condition: '${svDecodedResponse}.getErrors() == null',
          ifBlockStatements: [invalidation],
        ),
      'return ${svDecodedResponse};',
    ].join('\n');
  }

  String _serializeInvalidationCall(GLQueryDefinition def) {
    for (var e in def.elements) {
      if (e.cacheInvalidateAll) {
        return '${svStore}.invalidateAll();';
      }
    }
    final tags = def.elements.expand((e) => e.invalidateCacheTags).toSet();
    if (tags.isNotEmpty) {
      return 'invalidateByTags(Arrays.asList(${tags.map((e) => '"$e"').join(', ')}));';
    }
    return '// no tag to invalidate';
  }

  String _serializeSubscriptionAdapterCall(GLQueryDefinition def) {
    // Reactive: bridge the push-based handler into the flavor's many-type
    // stream. The raw listener forwards onto the emitter instead of a
    // user-supplied callback.
    if (_ctx.flavor.isReactive) {
      final rawListener = _ctx.codeGenUtils.createMethod(
          methodName:
              '${subscriptionListenerRef}<Map<String, Object>> ${svRawListener} = new ${subscriptionListenerRef}<Map<String, Object>>',
          statements: [
            '@Override',
            _ctx.codeGenUtils.createMethod(
              returnType: 'public void',
              methodName: 'onMessage',
              arguments: ['Map<String, Object> response'],
              statements: [
                _ctx.flavor.emitNext(
                    'emitter', '${def.typeDefinition?.token}.fromJson(response)')
              ],
            ),
            '@Override',
            _ctx.codeGenUtils.createMethod(
              returnType: 'public void',
              methodName: 'onComplete',
              arguments: [],
              statements: [_ctx.flavor.emitComplete('emitter')],
            ),
            '@Override',
            _ctx.codeGenUtils.createMethod(
              returnType: 'public void',
              methodName: 'onError',
              arguments: ['${clientExceptionNameRef} error'],
              statements: [_ctx.flavor.emitError('emitter', 'error')],
            )
          ]);
      final body = [
        '$rawListener;',
        '${svHandler}.handlePayload(${svPayload}, ${svRawListener});',
      ].join('\n');
      return 'return ${_ctx.flavor.createMany('emitter', body)};';
    }

    var method = _ctx.codeGenUtils.createMethod(
        methodName:
            '${subscriptionListenerRef}<Map<String, Object>> ${svRawListener} = new ${subscriptionListenerRef}<Map<String, Object>>',
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
    return ['${method};', '${svHandler}.handlePayload(${svPayload}, ${svRawListener});']
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
    return _ctx.serializer.serializeType(arg.type);
  }

  List<String> getArguments(GLQueryDefinition def) {
    final result = def.arguments
        .map((e) => '${_resolveArgType(e)} ${e.codeName}')
        .toList();
    // Reactive subscriptions return the many-type stream, so no callback
    // listener argument is taken; blocking subscriptions keep the listener.
    if (def.type == GLQueryType.subscription && !_ctx.flavor.isReactive) {
      result.add(
          '${subscriptionListenerRef}<${def.typeDefinition?.token}> listener');
    }
    return result;
  }

  String returnTypeByQueryType(GLQueryDefinition def) {
    if (def.type == GLQueryType.subscription) {
      if (_ctx.flavor.isReactive) {
        return JavaCodeGenUtils.manyOf(
            _ctx.grammar, def.getGeneratedTypeDefinition().token, _ctx.flavor);
      }
      return "void";
    }
    final token = def.isCaptureErrors(_ctx.grammar)
        ? def.getFullResponseTypeDefinition(_ctx.grammar).token
        : def.getGeneratedTypeDefinition().token;
    return JavaCodeGenUtils.singleOf(_ctx.grammar, token, _ctx.flavor);
  }

  String serializeSubscriptions() {
    return "";
  }
}
