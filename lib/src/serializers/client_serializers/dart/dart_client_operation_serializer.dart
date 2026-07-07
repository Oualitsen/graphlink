import 'package:graphlink/src/capture_errors_utils.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_fragment.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_vars.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';

class DartClientOperationSerializer {
  final GLParser _grammar;
  final DartCodeGenUtils _cg;
  final GLGraphqlSerializer _gqlSerializer;
  final GLSerializer _serializer;

  DartClientOperationSerializer(
      this._grammar, this._cg, this._gqlSerializer, this._serializer);

  // ── Schema-level helpers ───────────────────────────────────────────────────

  bool _shouldInvalidateAll(GLQueryDefinition def) =>
      def.elements.any((e) => e.cacheInvalidateAll);

  Set<String> _getInvalidationTags(GLQueryDefinition def) =>
      def.elements.expand((e) => e.invalidateCacheTags).toSet();

  bool _isUploadMutation(GLQueryDefinition def) =>
      _grammar.mutationHasUploads(def);

  Set<GLFragmentDefinitionBase> _getFragmentsForDef(GLQueryDefinition def) =>
      def.fragments(_grammar);

 

  List<DividedQuery> _divideQuery(GLQueryDefinition def) =>
      _gqlSerializer.divideQueryDefinition(def, _grammar);

  // ── Public entry points ────────────────────────────────────────────────────

  String queryToMethod(GLQueryDefinition def) {
    if (_divideQuery(def).every((e) => e.cacheTTL == 0)) {
      return _simpleQueryMethodBody(def);
    }
    return _cachedQueryMethodBody(def);
  }

  String _simpleQueryMethodBody(GLQueryDefinition def) {
    final fullResponseToken =
        def.getFullResponseTypeDefinition(_grammar).tokenInfo;
    final isCaptureErrors = def.isCaptureErrors(_grammar);
    final queryString = _gqlSerializer.serializeQueryDefinition(def);
    final fragmentNames = _getFragmentsForDef(def)
        .map((f) => "'${f.tokenInfo.token}'")
        .toSet();

    return _cg.createMethod(
        returnType: returnTypeByQueryType(def),
        methodName: def.codeName,
        arguments: getArguments(def),
        async: true,
        statements: [
          "const $svQuery = '''$queryString''';",
          'const $svFragmentNames = ${fragmentNames.isEmpty ? "<String>{};" : "<String>{${fragmentNames.join(", ")}};"}',
          generateVariables(def),
          if (isCaptureErrors)
            "return executeFull($svQuery, $svFragmentNames, '${def.tokenInfo}', ${_variablesExpr(def)}, $fullResponseToken.fromJson);"
          else
            "return (await executeData($svQuery, $svFragmentNames, '${def.tokenInfo}', ${_variablesExpr(def)}, $fullResponseToken.fromJson)).data!;",
        ]);
  }

  String _cachedQueryMethodBody(GLQueryDefinition def) {
    final dividedQueries = _divideQuery(def);
    final fullResponseToken =
        def.getFullResponseTypeDefinition(_grammar).tokenInfo;
    final isCaptureErrors = def.isCaptureErrors(_grammar);
    final directives = _gqlSerializer
        .serializeDirectiveValueList(def.getDirectives(skipGenerated: true));

    final executeCachedCall =
        "executeCached($svPartialQueries, '${def.tokenInfo}', '$directives', $fullResponseToken.fromJson, ${isCaptureErrors ? 'true' : 'false'})";

    return _cg.createMethod(
        returnType: returnTypeByQueryType(def),
        methodName: def.codeName,
        arguments: getArguments(def),
        async: true,
        statements: [
          generateVariables(def),
          'final $svPartialQueries = ${dividedQueries.map((e) => _serializePartialQuery(e)).toList()};',
          if (isCaptureErrors)
            "return $executeCachedCall;"
          else
            "return (await $executeCachedCall).data!;",
        ]);
  }

  String mutationToMethod(GLQueryDefinition def) {
    final queryText = _gqlSerializer.serializeQueryDefinition(def);
    final fragmentNames = _getFragmentsForDef(def)
        .map((f) => "'${f.tokenInfo.token}'")
        .toSet();

    final isSubscription = def.type == GLQueryType.subscription;
    final isUpload = _isUploadMutation(def);

    return _cg.createMethod(
        returnType: returnTypeByQueryType(def),
        methodName: def.codeName,
        arguments: getArguments(def),
        async: !isSubscription,
        statements: [
          "const $svQuery = '''$queryText''';",
          'const $svFragmentNames = ${fragmentNames.isEmpty ? "<String>{};" : "<String>{${fragmentNames.join(", ")}};"}',
          // assembleQuery/payload are only needed for the subscription and upload
          // paths; plain mutations build the payload inside executeData/executeFull.
          if (isSubscription || isUpload)
            'final $svFullQuery = assembleQuery($svQuery, $svFragmentNames);',
          generateVariables(def),
          if (isSubscription)
            "final $svPayload = GraphLinkPayload(query: $svFullQuery, operationName: '${def.tokenInfo}', variables: ${_variablesExpr(def)});",
          _serializeAdapterCall(def),
        ]);
  }

  // ── Variable generation ────────────────────────────────────────────────────

  String generateVariables(GLQueryDefinition def) {
    if (def.arguments.isEmpty) return '';
    final buffer = StringBuffer("final $svVariables = <String, dynamic>{");
    buffer.writeln();
    for (final arg in def.arguments) {
      final input = arg.hoistArgsInput;
      if (input == null) {
        buffer.writeln(
            "'${arg.dartArgumentName}': ${_serializeArgumentValue(def, arg.token)},"
                .ident());
        continue;
      }
      // Synthetic hoist arg: spread the <Op>FieldArgs object's own toJson(),
      // which already maps each field to its wire variable. `...?` drops it when
      // the (optional) object is null, leaving those vars absent (document
      // defaults apply); a required object is spread directly.
      final base = arg.codeName;
      buffer.writeln(
          (arg.type.nullable ? "...?$base?.toJson()," : "...$base.toJson(),")
              .ident());
    }
    buffer.writeln("};");
    return buffer.toString();
  }

  String _variablesExpr(GLQueryDefinition def) =>
      def.arguments.isNotEmpty ? svVariables : 'const <String, dynamic>{}';

  // ── Argument helpers ───────────────────────────────────────────────────────

  List<String> getArguments(GLQueryDefinition def) {
    final args = def.arguments.map((e) {
      final type = _resolveArgType(e);
      final name = e.codeName;
      if (e.defaultValue != null) {
        final lit = _serializer.serializeDefaultLiteral(
            e.type, e.defaultValue!.value,
            needsConst: true);
        return '$type $name = $lit';
      }
      if (e.type.nullable) return '$type $name';
      return 'required $type $name';
    }).toList();
    if (_isUploadMutation(def)) {
      args.add('UploadProgressCallback? onProgress');
    }
    if (args.isEmpty) return [];
    return args;
  }

  String _resolveArgType(GLArgumentDefinition arg) {
    final uploadNames = _grammar.uploadScalarNames;
    if (uploadNames.contains(arg.type.firstType.token)) {
      return arg.type.isList ? 'List<GLUpload>' : 'GLUpload';
    }
    return _serializer.serializeType(arg.type);
  }

  String returnTypeByQueryType(GLQueryDefinition def) {
    if (def.type == GLQueryType.subscription) {
      return "Stream<${def.getGeneratedTypeDefinition().tokenInfo.token}>";
    }
    if (def.isCaptureErrors(_grammar)) {
      return "Future<${def.getFullResponseTypeDefinition(_grammar).tokenInfo.token}>";
    }
    return "Future<${def.getGeneratedTypeDefinition().tokenInfo.token}>";
  }

  // ── Partial query serialization ────────────────────────────────────────────

  String _serializePartialQuery(DividedQuery e) {
    final varBuffer = StringBuffer('{');
    for (var v in e.variables) {
      varBuffer.writeln();
      final dartArgName = v.substring(1);
      varBuffer.writeln("'${dartArgName}': $svVariables['${dartArgName}'],");
    }
    varBuffer.write("}");
    return '''
GraphLinkPartialQuery(
  query: '${e.query}',
  operationName: "${e.operationName}",
  tags: ${e.tags.map((e) => e.quote()).toList()},
  ttl: ${e.cacheTTL},
  elementKey: '${e.elementKey}',
  fragmentNames: ${e.fragmentNames.map((e) => '"${e}"').toSet()},
  argumentDeclarations: ${e.argumentDeclarations.map((e) => '"${e.dolarEscape()}"').toList()},
  variables: ${varBuffer},
  staleIfOffline: ${e.staleIfOffline}
)
''';
  }

  // ── Adapter call ───────────────────────────────────────────────────────────

  String _serializeAdapterCall(GLQueryDefinition def) {
    if (def.type == GLQueryType.subscription) {
      return """
return $svHandler.handle($svPayload)
.map((e) {
  return ${def.getGeneratedTypeDefinition().tokenInfo.token}.fromJson(e);
});
    """
          .trim()
          .ident();
    }
    if (_isUploadMutation(def)) {
      return _serializeMultipartAdapterCall(def);
    }
    final fullResponseToken =
        def.getFullResponseTypeDefinition(_grammar).tokenInfo;
    final varsExpr = _variablesExpr(def);
    if (def.isCaptureErrors(_grammar)) {
      return """
final $svResult = await executeFull($svQuery, $svFragmentNames, '${def.tokenInfo}', $varsExpr, $fullResponseToken.fromJson);
if ($svResult.errors == null) {
  ${_serializeInvalidationCall(def)}
}
return $svResult;
""";
    }
    return """
final $svResult = await executeData($svQuery, $svFragmentNames, '${def.tokenInfo}', $varsExpr, $fullResponseToken.fromJson);
${_serializeInvalidationCall(def)}
return $svResult.data!;
""";
  }

  String _serializeMultipartAdapterCall(GLQueryDefinition def) {
    final uploadArgs = def.arguments
        .where((a) =>
            _grammar.uploadScalarNames.contains(a.type.firstType.token))
        .toList();

    final statements = <String>[
      'final $svMultipartMap = <String, Object>{};',
      'final $svFileParts = <String, Object>{};',
      'int $svSlot = 0;',
    ];

    for (final arg in uploadArgs) {
      final name = arg.codeName;
      final wireName = arg.dartArgumentName;
      if (arg.type.isList) {
        statements.add(_cg.forEachLoop(
          variable: '_i',
          iterable: 'Iterable.generate($name.length)',
          statements: [
            "$svMultipartMap['\${$svSlot + _i}'] = ['variables.$wireName.\$_i'];",
            "$svFileParts['\${$svSlot + _i}'] = $svUploadConverter($name[_i]);",
          ],
        ));
        statements.add('$svSlot += $name.length;');
      } else {
        statements.addAll([
          "$svMultipartMap['\$$svSlot'] = ['variables.$wireName'];",
          "$svFileParts['\$$svSlot'] = $svUploadConverter($name);",
          '$svSlot++;',
        ]);
      }
    }

    final fullResponseToken = def.getFullResponseTypeDefinition(_grammar).tokenInfo;
    final isCaptureErrors = def.isCaptureErrors(_grammar);

    statements.addAll([
      "final $svParts = <String, Object>{"
          "\n  'operations': jsonEncode({'query': $svFullQuery, 'variables': $svVariables}),"
          "\n  'map': jsonEncode($svMultipartMap),"
          "\n  ...$svFileParts,"
          "\n};",
      'final $svResponse = await $svUploadAdapter!($svParts, onProgress);',
      'final $svResult = $fullResponseToken.fromJson(jsonDecode($svResponse));',
      if (isCaptureErrors) ...[
        _cg.ifStatement(
          condition: '$svResult.errors == null',
          ifBlockStatements: [_serializeInvalidationCall(def)],
        ),
        'return $svResult;',
      ] else ...[
        _cg.ifStatement(
          condition: '$svResult.errors != null',
          ifBlockStatements: ['throw $svResult.errors!;'],
        ),
        _serializeInvalidationCall(def),
        'return $svResult.data!;',
      ],
    ]);

    return statements.join('\n');
  }

  String _serializeInvalidationCall(GLQueryDefinition def) {
    if (_shouldInvalidateAll(def)) {
      return 'await $svStore.invalidateAll();';
    }
    final tags = _getInvalidationTags(def);
    if (tags.isNotEmpty) {
      return 'await invalidateByTags(${tags.map((e) => e.quote()).toList()});';
    }
    return '// no tag to invalidate';
  }

  // ── JSON helpers ───────────────────────────────────────────────────────────

  String _serializeArgumentValue(GLQueryDefinition def, String argName) {
    final arg = def.findByName(argName);
    if (_grammar.uploadScalarNames.contains(arg.type.firstType.token)) {
      if (arg.type.isList) {
        return '${arg.codeName}.map((e) => null).toList()';
      } else {
        return 'null';
      }
    }
    return _callToJson(arg.codeName, arg.type);
  }

  String _callToJson(String argName, GLType type) {
    if (_grammar.inputTypeRequiresProjection(type) || _grammar.isEnum(type.token)) {
      if (type.isList) {
        return DartCodeGenUtils.mapToList(
            receiver: argName,
            param: 'e',
            body: _callToJson("e", type.inlineType),
            nullable: type.nullable);
      } else {
        return "$argName${type.nullable ? '?' : ''}.toJson()";
      }
    }
    return argName;
  }
}
