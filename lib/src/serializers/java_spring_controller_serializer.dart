import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_controller.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_schema_mapping.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/java_imports.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/jvm_spring_controller_serializer_base.dart';
import 'package:graphlink/src/utils.dart';

class JavaSpringControllerSerializer extends JvmSpringControllerSerializerBase {
  final JavaSerializer serializer;
  @override
  final JavaCodeGenUtils codeGenUtils = JavaCodeGenUtils();

  JavaSpringControllerSerializer({
    required GLParser grammar,
    required this.serializer,
    required bool reactive,
    required bool injectDataFetching,
    required bool useSpringSecurity,
    required bool generateSchema,
  }) : super(
          grammar: grammar,
          reactive: reactive,
          injectDataFetching: injectDataFetching,
          useSpringSecurity: useSpringSecurity,
          generateSchema: generateSchema,
        );

  // ── Map-ification helpers ─────────────────────────────────────────────────

  /// Converts a [GLType] to the map-ified Java return type that controllers
  /// expose. Projectable types → `Map<String, Object>`, enums → `String`,
  /// scalars stay as-is, and lists recurse.
  String _mapifyType(GLType type, GLToken context) {
    if (type is GLListType) {
      context.addImport(importList);
      return 'List<${_mapifyType(type.inlineType, context)}>';
    }
    if (grammar.isEnum(type.token)) return 'String';
    if (grammar.isProjectableType(type.token)) {
      context.addImport(JavaImports.map);
      return 'Map<String, Object>';
    }
    return serializer.serializeType(type, false);
  }

  /// Returns body statements that convert the values of a batch-mapping
  /// `Map<K,V>` to their map-ified forms using a plain for-each loop.
  /// Handles null values and is Java 8 compatible.
  ///
  /// Convention (same as [_wrapInCompletableFuture]): all statements except
  /// the last carry their own semicolons; the last is a bare expression.
  /// Scalars: single-element list containing the raw service call expression.
  List<String> _wrapBatchBodyStatements(
      GLType fieldType, String expression, String keyType, GLToken context) {
    final kVar = codeGenUtils.safeLocalVar('key');
    final valVar = codeGenUtils.safeLocalVar('val');
    final valueExpr = _wrapWithToJson(fieldType, valVar, context);
    if (valueExpr == valVar) return [expression];
    final tmpVar = codeGenUtils.safeLocalVar('tmp');
    final mapifiedValueType = _mapifyType(fieldType, context);
    context.addImport(JavaImports.hashMap);
    context.addImport(JavaImports.map);
    return [
      'final Map<$keyType, $mapifiedValueType> $tmpVar = new HashMap<>();',
      '$expression.forEach(($kVar, $valVar) -> { $tmpVar.put($kVar, $valueExpr); });',
      tmpVar,
    ];
  }

  /// Wraps [expression] with `.toJson()` calls at each projectable nesting
  /// level, threading null-safety through [GLType.nullable] so that every
  /// nullable layer produces a null-guard (`== null ? null : …`).
  String _wrapWithToJson(GLType type, String expression, GLToken context,
      [int depth = 0]) {
    if (type is GLListType) {
      final innerVar = codeGenUtils.safeLocalVar('e$depth');
      final innerExpr =
          _wrapWithToJson(type.inlineType, innerVar, context, depth + 1);
      context.addImport(JavaImports.collectors);
      if (innerVar == innerExpr) {
        return JavaCodeGenUtils.streamMapCollect(
            receiver: expression, nullable: type.nullable);
      }
      return JavaCodeGenUtils.streamMapCollect(
          receiver: expression,
          param: innerVar,
          body: innerExpr,
          nullable: type.nullable);
    }
    if (grammar.isEnum(type.token) || grammar.isProjectableType(type.token)) {
      return JavaCodeGenUtils.safeCall(expression, 'toJson()', type.nullable);
    }
    return expression;
  }

  // ── Controller ─────────────────────────────────────────────────────────────

  @override
  String serializeController(GLController ctrl) {
    var body = _serializeControllerBody(ctrl);
    return serializer.serializeWithImport(ctrl, body);
  }

  String _serializeControllerBody(GLController ctrl) {
    final controllerName = ctrl.token;
    final serviceInstanceName = ctrl.serviceName.firstLow;
    if (!reactive) {
      ctrl.addImport(JavaImports.completableFuture);
    }
    if (ctrl.fields.isNotEmpty &&
        (injectDataFetching ||
            ctrl.fields.any((f) => f.hasDirective(glReturnsProjection)))) {
      ctrl.addImport(SpringImports.gqlDataFetchingEnvironment);
    }
    var decorators = serializer.serializeDecorators(ctrl.getDirectives()).trim();

    var buffer = StringBuffer();
    buffer.writeln(decorators);
    buffer.writeln(codeGenUtils.createClass(className: controllerName, statements: [
      if (grammar.services.containsKey(ctrl.serviceName))
        'private final ${ctrl.serviceName} $serviceInstanceName;',
      '',
      serializer.generateContructor(
          controllerName,
          [
            if (grammar.services.containsKey(ctrl.serviceName))
              GLField(
                  name: serviceInstanceName.toToken(),
                  type: GLType(ctrl.serviceName.toToken(), false),
                  arguments: [],
                  directives: [])
          ],
          "public",
          ctrl),
      '',
      ...ctrl.fields.map((field) => serializehandlerMethod(
          ctrl.getTypeByFieldName(field.name.token)!,
          field,
          serviceInstanceName,
          ctrl,
          qualifier: "public")),
      '',
      ...ctrl.mappings.map((m) => serializeMappingMethod(m, serviceInstanceName, ctrl))
    ]));

    return buffer.toString();
  }

  @override
  String serializehandlerMethod(GLQueryType type, GLField method,
      String serviceInstanceName, GLToken context,
      {String? qualifier}) {
    final decorators =
        serializer.serializeDecorators(method.getDirectives()).trim();
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators);
    }

    final inputConversions = <String>[];
    var args = method.arguments.map((arg) {
      if (grammar.isInput(arg.type.firstType.token)) {
        final rawParamName = '${arg.bareName}AsMap';
        final mapType = _inputArgRawType(arg.type, context);
        context.addImport(SpringImports.gqlArgument);
        inputConversions.add(
            'final ${resolveArgType(arg, context)} ${arg.codeName} = ${_inputFromJsonConversion(arg.type, rawParamName, context)};');
        return '@Argument(name = "${arg.bareName}") $mapType $rawParamName';
      }
      final argType = resolveArgType(arg, context);
      var argDecorators =
          serializer.serializeDecorators(arg.getDirectives()).trim();
      if (argDecorators.isNotEmpty) {
        return "$argDecorators $argType ${arg.codeName}";
      }
      return "$argType ${arg.codeName}";
    }).toList();

    final injectFetchingEnv =
        injectDataFetching || method.hasDirective(glReturnsProjection);
    if (injectFetchingEnv) {
      args.add("DataFetchingEnvironment dataFetchingEnvironment");
    }
    var serviceArgs =
        method.arguments.map((arg) => arg.codeName).toList();
    if (injectFetchingEnv) {
      serviceArgs.add('dataFetchingEnvironment');
    }
    final serviceCall =
        '$serviceInstanceName.${method.codeName}(${serviceArgs.join(", ")})';
    final String returnType;
    final List<String> statements;

    final validationMethodCall = method.getDirectiveByName(glValidate) != null
        ? '$serviceInstanceName.${GLService.getValidationMethodName(method.name.token)}(${serviceArgs.join(", ")})'
        : null;
    final validationCall =
        validationMethodCall != null ? '$validationMethodCall;' : null;

    if (type == GLQueryType.subscription) {
      final subscriptionReturnType = getServiceReturnType(method.type);
      final mapifiedInner = _mapifyType(subscriptionReturnType, context);
      context.addImport(JavaImports.flux);
      returnType = 'Flux<$mapifiedInner>';
      final resultVar = codeGenUtils.safeLocalVar('result');
      final toJsonExpr =
          _wrapWithToJson(subscriptionReturnType, resultVar, context);
      final returnExpr = toJsonExpr == resultVar
          ? serviceCall
          : '$serviceCall.map($resultVar -> $toJsonExpr)';
      statements = [
        ...inputConversions,
        if (validationCall != null) validationCall,
        'return $returnExpr;',
      ];
    } else if (reactive) {
      final monoReturnType = getServiceReturnType(method.type);
      if (monoReturnType is GLListType) {
        // Flux: each element is emitted individually
        final mapifiedInner = _mapifyType(monoReturnType.inlineType, context);
        context.addImport(JavaImports.flux);
        returnType = 'Flux<$mapifiedInner>';
      } else {
        final mapifiedType = _mapifyType(monoReturnType, context);
        context.addImport(JavaImports.mono);
        returnType = 'Mono<$mapifiedType>';
      }
      final resultVar = codeGenUtils.safeLocalVar('result');
      final innerType = monoReturnType is GLListType
          ? monoReturnType.inlineType
          : monoReturnType;
      final toJsonExpr = _wrapWithToJson(innerType, resultVar, context);
      final mapsNeeded = toJsonExpr != resultVar;
      statements = [
        ...inputConversions,
        if (validationMethodCall != null)
          'return $validationMethodCall.then($serviceCall${mapsNeeded ? '.map($resultVar -> $toJsonExpr)' : ''});'
        else if (mapsNeeded)
          'return $serviceCall.map($resultVar -> $toJsonExpr);'
        else
          'return $serviceCall;',
      ];
    } else {
      context.addImport(JavaImports.completableFuture);
      final cfReturnType = getServiceReturnType(method.type);
      final baseReturnType = serializer.serializeTypeReactive(
          context: context, glType: cfReturnType, reactive: false);
      final returnTypeIsVoid = baseReturnType == 'void';
      final mapifiedType = _mapifyType(cfReturnType, context);
      returnType = returnTypeIsVoid
          ? 'CompletableFuture<Void>'
          : 'CompletableFuture<${convertPrimitiveToBoxed(mapifiedType)}>';

      final innerStatements = <String>[
        if (validationCall != null) validationCall,
      ];
      if (returnTypeIsVoid) {
        innerStatements.add(serviceCall);
      } else {
        final needsToJson = cfReturnType is GLListType ||
            grammar.isEnum(cfReturnType.firstType.token) ||
            grammar.isProjectableType(cfReturnType.firstType.token);
        if (cfReturnType.nullable && needsToJson) {
          // Use a temp variable to avoid double-evaluating the service call
          // inside the null-safe ternary produced by _wrapWithToJson.
          final tempVar = codeGenUtils.safeLocalVar('tmp');
          innerStatements.add(
              '$baseReturnType $tempVar = $serviceCall;');
          innerStatements
              .add(_wrapWithToJson(cfReturnType, tempVar, context));
        } else {
          innerStatements
              .add(_wrapWithToJson(cfReturnType, serviceCall, context));
        }
      }
      statements = [
        ...inputConversions,
        ..._wrapInCompletableFuture(
            innerStatements, returnTypeIsVoid, context),
      ];
    }

    final fullReturnType =
        qualifier != null ? "$qualifier $returnType" : returnType;

    buffer.writeln(codeGenUtils.createMethod(
        returnType: fullReturnType,
        methodName: method.codeName,
        arguments: args,
        statements: statements));

    return buffer.toString();
  }

  /// Returns the raw map type for a controller parameter that receives a
  /// GraphQL input, recursing through list nesting.
  /// Input → Map<String, Object>
  /// [Input] → List<Map<String, Object>>
  /// [[Input]] → List<List<Map<String, Object>>>
  String _inputArgRawType(GLType type, GLToken context) {
    if (type is GLListType) {
      context.addImport(JavaImports.list);
      return 'List<${_inputArgRawType(type.inlineType, context)}>';
    }
    context.addImport(JavaImports.map);
    return 'Map<String, Object>';
  }

  /// Builds the fromJson conversion expression for an input arg, recursing
  /// through list nesting with inline stream chains.
  /// Null guards are emitted wherever the element type is nullable.
  String _inputFromJsonConversion(GLType type, String sourceExpr, GLToken context, [int depth = 0]) {
    if (type is GLListType) {
      context.addImport(JavaImports.collectors);
      final varName = codeGenUtils.safeLocalVar('m$depth');
      final inner = _inputFromJsonConversion(type.inlineType, varName, context, depth + 1);
      final body = JavaCodeGenUtils.nullSafeExpr(varName, inner, type.inlineType.nullable);
      return JavaCodeGenUtils.streamMapCollect(receiver: sourceExpr, param: varName, body: body);
    }
    final call = '${type.token}.fromJson((Map<String, Object>) $sourceExpr)';
    return JavaCodeGenUtils.nullSafeExpr(sourceExpr, call, type.nullable);
  }

  List<String> _wrapInCompletableFuture(
      List<String> innerStatements, bool returnVoid, GLToken context) {
    final method = returnVoid ? 'runAsync' : 'supplyAsync';
    final preceding = innerStatements.sublist(0, innerStatements.length - 1);
    final last = innerStatements.last;
    final bodyStatements = [
      ...preceding,
      returnVoid ? "$last;" : "return $last;",
    ];

    if (!useSpringSecurity) {
      final lambdaBody = bodyStatements.length == 1
          ? innerStatements.first
          : codeGenUtils.block(bodyStatements);
      return ["return CompletableFuture.$method(() -> $lambdaBody);"];
    }

    context.addImport(JavaImports.securityContext);
    context.addImport(JavaImports.securityContextHolder);
    final lambdaBody = codeGenUtils.block([
      "SecurityContextHolder.setContext(securityContext);",
      codeGenUtils.tryCatchFinally(
        tryStatements: bodyStatements,
        finallyStatements: ["SecurityContextHolder.clearContext();"],
      ),
    ]);
    return [
      "SecurityContext securityContext = SecurityContextHolder.getContext();",
      "return CompletableFuture.$method(() -> $lambdaBody);",
    ];
  }

  // ── Mapping methods ────────────────────────────────────────────────────────

  @override
  String serializeMappingMethod(
      GLSchemaMapping mapping, String serviceInstanceName, GLToken context) {
    if (mapping.forwarded) {
      return serializeForwardedMapping(mapping, context);
    }
    if (mapping.forbid && generateSchema) {
      return "";
    }
    if (mapping.forbid) {
      context.addImport(SpringImports.gqlGraphQLException);
      return '${serializeControllerMethodHeader(mapping, context)} ${codeGenUtils.block([
            '''throw new GraphQLException("Access denied to field '${mapping.type.tokenInfo}.${mapping.field.name}'");'''
          ])}';
    }

    if (mapping.identity) {
      return serializeIdentityMapping(mapping, context);
    }

    final rawCall = StringBuffer('$serviceInstanceName.${mapping.key}(value');
    for (var arg in mapping.field.arguments) {
      rawCall.write(', ${arg.codeName}');
    }
    if (injectDataFetching || mapping.field.hasDirective(glReturnsProjection)) {
      rawCall.write(', dataFetchingEnvironment');
    }
    rawCall.write(')');
    final fieldType = mapping.field.type;

    final List<String> bodyStatements;
    if (mapping.isBatch) {
      final keyType = serializer.serializeType(
          getServiceReturnType(GLType(mapping.type.tokenInfo, false)), false);
      final stmts = _wrapBatchBodyStatements(
          fieldType, rawCall.toString(), keyType, context);
      if (reactive) {
        context.addImport(JavaImports.mono);
        if (stmts.length == 1) {
          // scalar — no transformation needed, wrap bare map in Mono
          bodyStatements = ['return Mono.just(${stmts.first});'];
        } else {
          // projectable — service returns Mono<Map<K,V>>; unwrap via .map()
          final srcVar = codeGenUtils.safeLocalVar('src');
          final innerStmts = _wrapBatchBodyStatements(fieldType, srcVar, keyType, context);
          final lambdaBody = codeGenUtils.block([
            ...innerStmts.sublist(0, innerStmts.length - 1),
            'return ${innerStmts.last};',
          ]);
          bodyStatements = ['return ${rawCall.toString()}.map($srcVar -> $lambdaBody);'];
        }
      } else {
        bodyStatements = _wrapInCompletableFuture(stmts, false, context);
      }
    } else {
      final needsToJson = fieldType is GLListType ||
          grammar.isEnum(fieldType.firstType.token) ||
          grammar.isProjectableType(fieldType.firstType.token);
      if (reactive) {
        // In reactive mode the service returns Mono<T> — use .map() to
        // transform the emitted value rather than calling toJson directly.
        if (!needsToJson) {
          bodyStatements = ['return ${rawCall.toString()};'];
        } else {
          final resultVar = codeGenUtils.safeLocalVar('result');
          final toJsonExpr = _wrapWithToJson(fieldType, resultVar, context);
          bodyStatements = ['return ${rawCall.toString()}.map($resultVar -> $toJsonExpr);'];
        }
      } else if (fieldType.nullable && needsToJson) {
        // Use a temp variable to avoid double-evaluating the service call
        // inside the null-safe ternary produced by _wrapWithToJson.
        final tempVar = codeGenUtils.safeLocalVar('tmp');
        final originalType = serializer.serializeTypeReactive(
            context: context, glType: fieldType, reactive: false);
        final decl = '$originalType $tempVar = ${rawCall};';
        final toJsonExpr = _wrapWithToJson(fieldType, tempVar, context);
        bodyStatements =
              _wrapInCompletableFuture([decl, toJsonExpr], false, context);
      } else {
        final toJsonExpr =
            _wrapWithToJson(fieldType, rawCall.toString(), context);
        bodyStatements =
            _wrapInCompletableFuture([toJsonExpr], false, context);
      }
    }
    return '${serializeControllerMethodHeader(mapping, context)} ${codeGenUtils.block(bodyStatements)}';
  }

  @override
  String serializeIdentityMapping(GLSchemaMapping mapping, GLToken context) {
    var buffer = StringBuffer();
    var annotation = getAnnotationForMapping(mapping, context);
    if (annotation.isNotEmpty) {
      buffer.writeln(annotation);
    }
    final type = serializer.serializeTypeReactive(
        context: context, glType: mapping.field.type, reactive: false);
    final boxedType = convertPrimitiveToBoxed(type);

    final String returnType;
    final String statement;
    if (reactive) {
      if (mapping.isBatch) {
        context.addImport(JavaImports.flux);
        returnType = JavaCodeGenUtils.fluxOf(grammar, type);
        statement = "return Flux.fromIterable(value);";
      } else {
        context.addImport(JavaImports.mono);
        returnType = JavaCodeGenUtils.monoOf(grammar, type);
        statement = "return Mono.just(value);";
      }
    } else {
      if (mapping.isBatch) {
        returnType = JavaCodeGenUtils.listOf(grammar, type);
      } else {
        returnType = type;
      }
      statement = "return value;";
    }

    buffer.writeln(
      codeGenUtils.createMethod(
          returnType: 'public $returnType',
          methodName: mapping.key,
          arguments: [
            mapping.isBatch ? 'List<$boxedType> value' : '$boxedType value'
          ],
          statements: [statement]),
    );

    return buffer.toString();
  }

  String _getterMethodName(String fieldName, String fieldType) {
    if (serializer.typesAsRecords) return fieldName;
    final prefix = fieldType == 'boolean' ? 'is' : 'get';
    return '$prefix${fieldName.firstUp}';
  }

  @override
  String serializeForwardedMapping(GLSchemaMapping mapping, GLToken context) {
    var buffer = StringBuffer();
    buffer.writeln(getAnnotationForMapping(mapping, context));

    final fieldName = mapping.field.name.token;
    final fieldType = serializer.serializeTypeReactive(
        context: context, glType: mapping.field.type, reactive: false);
    final argType = serializer.serializeType(
        getServiceReturnType(GLType(mapping.type.tokenInfo, false)), false);

    final getterCall = 'value.${_getterMethodName(fieldName, fieldType)}()';

    final String returnType;
    final String statement;
    if (reactive) {
      context.addImport(JavaImports.mono);
      returnType = JavaCodeGenUtils.monoOf(grammar, fieldType);
      statement = 'return Mono.just($getterCall);';
    } else {
      returnType = fieldType;
      statement = 'return $getterCall;';
    }

    buffer.writeln(codeGenUtils.createMethod(
      returnType: 'public $returnType',
      methodName: mapping.key,
      arguments: ['$argType value'],
      statements: [statement],
    ));

    return buffer.toString();
  }

  String _getReturnType(GLSchemaMapping mapping, GLToken context) {
    if (mapping.isBatch) {
      var keyType = serializer.serializeType(
          getServiceReturnType(GLType(mapping.type.tokenInfo, false)), false);
      if (keyType == "Object") {
        keyType = "?";
      }
      context.addImport(JavaImports.map);
      return JavaCodeGenUtils.mapOf(
        grammar,
        keyType,
        serializer.serializeType(mapping.field.type, false),
      );
    } else {
      return serializer.serializeTypeReactive(
          context: context, glType: mapping.field.type, reactive: false);
    }
  }

  String _getControllerReturnType(GLSchemaMapping mapping, GLToken context) {
    if (mapping.isBatch) {
      var keyType = serializer.serializeType(
          getServiceReturnType(GLType(mapping.type.tokenInfo, false)), false);
      if (keyType == "Object") {
        keyType = "?";
      }
      context.addImport(JavaImports.map);
      return JavaCodeGenUtils.mapOf(
        grammar,
        keyType,
        _mapifyType(mapping.field.type, context),
      );
    } else {
      return _mapifyType(mapping.field.type, context);
    }
  }

  String _getMappingArgument(GLSchemaMapping mapping, GLToken context) {
    var argType = serializer.serializeType(
        getServiceReturnType(GLType(mapping.type.tokenInfo, false)), false);
    if (mapping.isBatch) {
      context.addImport(importList);
      return "${JavaCodeGenUtils.listOf(grammar, argType)} value";
    } else {
      return "${argType} value";
    }
  }

  @override
  String serializeControllerMethodHeader(
      GLSchemaMapping mapping, GLToken context) {
    var buffer = StringBuffer();
    buffer.writeln(getAnnotationForMapping(mapping, context));
    buffer.write("public ");

    final returnType = _getControllerReturnType(mapping, context);
    if (reactive) {
      context.addImport(JavaImports.mono);
      buffer.write(
          "${JavaCodeGenUtils.monoOf(grammar, returnType)} ${mapping.key}(${_getMappingArgument(mapping, context)}");
    } else {
      context.addImport(JavaImports.completableFuture);
      buffer.write(
          "CompletableFuture<${convertPrimitiveToBoxed(returnType)}> ${mapping.key}(${_getMappingArgument(mapping, context)}");
    }
    for (var arg in mapping.field.arguments) {
      final argType = resolveArgType(arg, context);
      context.addImport(SpringImports.gqlArgument);
      buffer.write(', ${_argumentAnnotation(arg)} $argType ${arg.codeName}');
    }
    if (injectDataFetching || mapping.field.hasDirective(glReturnsProjection)) {
      context.addImport(SpringImports.gqlDataFetchingEnvironment);
      buffer.write(', DataFetchingEnvironment dataFetchingEnvironment)');
    } else {
      buffer.write(')');
    }
    return buffer.toString();
  }

  // ── Service declarations ───────────────────────────────────────────────────

  @override
  String serializeMethodDeclaration(
      GLField method, GLQueryType type, GLToken context,
      {String? argPrefix}) {
    GLType returnType;
    if (method.getDirectiveByName(glValidate)?.generated == true) {
      returnType = GLType('void'.toToken(), false);
    } else {
      returnType = getServiceReturnType(method.type);
    }
    var result =
        "${serializer.serializeTypeReactive(context: context, glType: createListTypeOnSubscription(returnType, type), reactive: reactive || type == GLQueryType.subscription)} ${method.codeName}(${serializeArgs(method.arguments, context, argPrefix)}";
    if (injectDataFetching || method.hasDirective(glReturnsProjection)) {
      var inject = "DataFetchingEnvironment dataFetchingEnvironment";
      context.addImport(SpringImports.gqlDataFetchingEnvironment);
      if (method.arguments.isNotEmpty) {
        result = "$result, $inject";
      } else {
        result = "$result$inject";
      }
    }
    return "${result})";
  }

  @override
  String serializeServiceMappingImplMethodHeader(
      GLSchemaMapping mapping, GLToken context) {
    var buffer = StringBuffer();

    final returnType = _getReturnType(mapping, context);
    if (reactive) {
      context.addImport(JavaImports.mono);
      buffer.write(
          "${JavaCodeGenUtils.monoOf(grammar, returnType)} ${mapping.key}(${_getMappingArgument(mapping, context)}");
    } else {
      buffer.write(
          "$returnType ${mapping.key}(${_getMappingArgument(mapping, context)}");
    }
    for (var arg in mapping.field.arguments) {
      final argType = resolveArgType(arg, context);
      buffer.write(', $argType ${arg.codeName}');
    }
    if (injectDataFetching || mapping.field.hasDirective(glReturnsProjection)) {
      context.addImport(SpringImports.gqlDataFetchingEnvironment);
      buffer.write(', DataFetchingEnvironment dataFetchingEnvironment)');
    } else {
      buffer.write(')');
    }
    return buffer.toString();
  }

  /// `@Argument`, pinned to the wire name when the param was sanitized for a
  /// keyword so Spring still binds the correct GraphQL argument.
  String _argumentAnnotation(GLArgumentDefinition arg) =>
      arg.codeName != arg.bareName
          ? '@Argument(name = "${arg.bareName}")'
          : '@Argument';

  // ── Arg type resolution ────────────────────────────────────────────────────

  @override
  String resolveArgType(GLArgumentDefinition arg, GLToken context) {
    final uploadNames = grammar.uploadScalarNames;
    if (uploadNames.contains(arg.type.firstType.token)) {
      if (reactive) {
        context.addImport(SpringImports.filePart);
        if (arg.type.isList) {
          context.addImport(JavaImports.list);
          return 'List<FilePart>';
        }
        return 'FilePart';
      } else {
        context.addImport(SpringImports.multipartFile);
        if (arg.type.isList) {
          context.addImport(JavaImports.list);
          return 'List<MultipartFile>';
        }
        return 'MultipartFile';
      }
    }
    return serializer.serializeType(arg.type, false);
  }
}
