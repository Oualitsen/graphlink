import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/gl_validation_extension.dart';
import 'package:graphlink/src/kotlin_code_gen_utils.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_controller.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_schema_mapping.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/java_imports.dart';
import 'package:graphlink/src/serializers/jvm_spring_controller_serializer_base.dart';
import 'package:graphlink/src/serializers/kotlin_imports.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';

class KotlinSpringControllerSerializer extends JvmSpringControllerSerializerBase {
  final KotlinSerializer serializer;
  final String packageName;

  /// Whether the `*Service` implementations are blocking (JPA/JDBC). When
  /// `true`, service calls are wrapped in
  /// `withContext(Dispatchers.IO + SecurityCoroutineContext()) { ... }`.
  final bool blockingServices;

  @override
  final KotlinCodeGenUtils codeGenUtils = KotlinCodeGenUtils();

  KotlinSpringControllerSerializer({
    required super.grammar,
    required this.serializer,
    required this.packageName,
    required super.injectDataFetching,
    required super.generateSchema,
    this.blockingServices = true,
  }) : super(
          reactive: false,
          useSpringSecurity: false,
        );

  // ── Map-ification helpers ─────────────────────────────────────────────────

  /// Converts a [GLType] to the map-ified Kotlin return type that controllers
  /// expose. Projectable types → `Map<String, Any?>`, enums → `String`,
  /// scalars stay as-is, and lists recurse.
  String _mapifyType(GLType type) {
    final nullable = type.nullable ? '?' : '';
    if (type is GLListType) {
      return 'List<${_mapifyType(type.inlineType)}>$nullable';
    }
    if (grammar.isEnum(type.token)) return 'String$nullable';
    if (grammar.isProjectableType(type.token)) return 'Map<String, Any?>$nullable';
    return serializer.serializeType(type, false);
  }

  /// Wraps [expression] with `.toJson()` / `?.toJson()` calls at each
  /// projectable nesting level, threading null-safety through
  /// [GLType.nullable].
  String _wrapWithToJson(GLType type, String expression, [int depth = 0]) {
    if (type is GLListType) {
      final innerVar = codeGenUtils.safeLocalVar('e$depth');
      final innerExpr =
          _wrapWithToJson(type.inlineType, innerVar, depth + 1);
      if (innerVar == innerExpr) return expression;
      return KotlinCodeGenUtils.mapCall(
          receiver: expression,
          param: innerVar,
          body: innerExpr,
          nullable: type.nullable);
    }
    if (grammar.isEnum(type.token) || grammar.isProjectableType(type.token)) {
      return KotlinCodeGenUtils.safeCall(expression, 'toJson()', type.nullable);
    }
    return expression;
  }

  /// Returns the output-map–building statements for a batch mapping, given
  /// [svcExpr] (the service Map result in scope) and [typedVar] (the typed list
  /// passed to the service, used for index-based key lookup).
  /// Returns `[tmpDecl, forLoop, tmpVarName]`.
  List<String> _batchOutputMapStatements(
      GLType fieldType, String svcExpr, String typedVar) {
    final valVar = codeGenUtils.safeLocalVar('val');
    final valueExpr = _wrapWithToJson(fieldType, valVar);
    final tmpVar = codeGenUtils.safeLocalVar('tmp');
    final iVar = codeGenUtils.safeLocalVar('i');
    final mapifiedValueType = _mapifyType(fieldType);
    return [
      'val $tmpVar = LinkedHashMap<Map<String, Any?>, $mapifiedValueType>()',
      'for ($iVar in value.indices) { val $valVar = $svcExpr[$typedVar[$iVar]]; $tmpVar[value[$iVar]] = $valueExpr }',
      tmpVar,
    ];
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
    if (ctrl.fields.isNotEmpty &&
        (injectDataFetching ||
            ctrl.fields.any((f) => f.hasDirective(glReturnsProjection)))) {
      ctrl.addImport(SpringImports.gqlDataFetchingEnvironment);
    }
    var decorators = serializer.serializeDecorators(ctrl.getDirectives()).trim();

    var buffer = StringBuffer();
    buffer.writeln(decorators);
    buffer.writeln(codeGenUtils.kotlinClass(
      name: controllerName,
      params: [
        if (grammar.services.containsKey(ctrl.serviceName))
          'private val $serviceInstanceName: ${ctrl.serviceName}',
      ],
      body: [
        ...ctrl.fields.map((field) => serializehandlerMethod(
            ctrl.getTypeByFieldName(field.name.token)!, field, serviceInstanceName, ctrl)),
        '',
        ...ctrl.mappings.map((m) => serializeMappingMethod(m, serviceInstanceName, ctrl))
      ],
    ));

    return buffer.toString();
  }

  @override
  String serializehandlerMethod(GLQueryType type, GLField method, String serviceInstanceName, GLToken context,
      {String? qualifier}) {
    final decorators = serializer.serializeDecorators(method.getDirectives()).trim();
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators);
    }

    final inputConversions = <String>[];
    var args = method.arguments.map((arg) {
      if (grammar.isInput(arg.type.firstType.token)) {
        final rawParamName = '${arg.bareName}AsMap';
        final mapType = _inputArgRawType(arg.type);
        context.addImport(SpringImports.gqlArgument);
        inputConversions.add(
            'val ${arg.codeName} = ${_inputFromJsonConversion(arg.type, rawParamName)}');
        return '@Argument(name = "${arg.bareName}") $rawParamName: $mapType';
      }
      final argDecorators = serializer.serializeDecorators(arg.getDirectives()).trim();
      final decl = '${arg.codeName}: ${resolveArgType(arg, context)}';
      if (argDecorators.isNotEmpty) {
        return '$argDecorators $decl';
      }
      return decl;
    }).toList();

    final injectFetchingEnv = injectDataFetching || method.hasDirective(glReturnsProjection);
    if (injectFetchingEnv) {
      context.addImport(SpringImports.gqlDataFetchingEnvironment);
      args.add('dataFetchingEnvironment: DataFetchingEnvironment');
    }

    var serviceArgs = method.arguments.map((arg) => arg.codeName).toList();
    if (injectFetchingEnv) {
      serviceArgs.add('dataFetchingEnvironment');
    }
    final serviceCall = '$serviceInstanceName.${method.codeName}(${serviceArgs.join(", ")})';

    final validationMethodCall = method.getDirectiveByName(glValidate) != null
        ? '$serviceInstanceName.${GLService.getValidationMethodName(method.name.token)}(${serviceArgs.join(", ")})'
        : null;

    final returnType = _serializeControllerReturnType(method.type, type, context);

    if (type == GLQueryType.subscription) {
      final subscriptionReturnType = getServiceReturnType(method.type);
      final resultVar = codeGenUtils.safeLocalVar('result');
      final toJsonExpr =
          _wrapWithToJson(subscriptionReturnType, resultVar);
      if (toJsonExpr != resultVar) {
        context.addImport(KotlinImports.flowMap);
      }
      final statements = [
        ...inputConversions,
        if (validationMethodCall != null) validationMethodCall,
        'return $serviceCall.map { $resultVar -> $toJsonExpr }',
      ];
      buffer.writeln(codeGenUtils.method(
          returnType: returnType, methodName: method.codeName, arguments: args, statements: statements));
    } else {
      final suspendReturnType = getServiceReturnType(method.type);
      final wrappedCall = _wrapWithToJson(suspendReturnType, serviceCall);
      final statements = [
        ...inputConversions,
        ..._wrapBody(
          [if (validationMethodCall != null) validationMethodCall],
          wrappedCall,
          context,
        ),
      ];
      buffer.writeln(codeGenUtils.suspendFun(
          name: method.codeName, arguments: args, returnType: returnType, statements: statements));
    }

    return buffer.toString();
  }

  /// Returns the raw map type for a controller parameter that receives a
  /// GraphQL input, recursing through list nesting.
  String _inputArgRawType(GLType type) {
    if (type is GLListType) {
      return 'List<${_inputArgRawType(type.inlineType)}>';
    }
    return 'Map<String, Any>';
  }

  /// Builds the fromJson conversion expression for an input arg, recursing
  /// through list nesting with inline map { } chains.
  /// Null guards are emitted wherever the element type is nullable.
  String _inputFromJsonConversion(GLType type, String sourceExpr, [int depth = 0]) {
    if (type is GLListType) {
      final varName = codeGenUtils.safeLocalVar('m$depth');
      final inner = _inputFromJsonConversion(type.inlineType, varName, depth + 1);
      final body = type.inlineType.nullable ? 'if ($varName == null) null else $inner' : inner;
      return KotlinCodeGenUtils.mapCall(receiver: sourceExpr, param: varName, body: body);
    }
    final call = '${type.token}.fromJson($sourceExpr as Map<String, Any>)';
    return type.nullable ? 'if ($sourceExpr == null) null else $call' : call;
  }

  String _serializeReturnType(GLType type, GLQueryType queryType, GLToken context) {
    final returnType = getServiceReturnType(type);
    if (queryType == GLQueryType.subscription) {
      context.addImport(KotlinImports.flow);
      return 'Flow<${serializer.serializeType(returnType, false)}>';
    }
    return serializer.serializeType(returnType, false);
  }

  String _serializeControllerReturnType(GLType type, GLQueryType queryType, GLToken context) {
    final returnType = getServiceReturnType(type);
    final mapifiedType = _mapifyType(returnType);
    if (queryType == GLQueryType.subscription) {
      context.addImport(KotlinImports.flow);
      return 'Flow<$mapifiedType>';
    }
    return mapifiedType;
  }

  /// Builds the body of a `suspend fun` that calls into the service layer.
  ///
  /// When [blockingServices] is `true`, wraps [precedingStatements] and the
  /// final [returnExpr] in `withContext(Dispatchers.IO +
  /// SecurityCoroutineContext()) { ... }` — offloading the blocking call and
  /// propagating `SecurityContextHolder` across the dispatcher switch.
  /// Otherwise emits the statements as-is, trusting the service to be
  /// coroutine-native/non-blocking.
  List<String> _wrapBody(List<String> precedingStatements, String returnExpr, GLToken context) {
    if (!blockingServices) {
      return [...precedingStatements, 'return $returnExpr'];
    }
    context.addImport(KotlinImports.dispatchers);
    context.addImport(KotlinImports.withContext);
    context.addImport(JavaImports.securityContextHolder);
    context.addImport('$packageName.security.SecurityCoroutineContext');
    return [
      'val securityContext = SecurityContextHolder.getContext()',
      'return withContext(Dispatchers.IO + SecurityCoroutineContext(securityContext)) ${codeGenUtils.block([
            ...precedingStatements,
            returnExpr,
          ])}',
    ];
  }

  // ── Mapping methods ────────────────────────────────────────────────────────

  @override
  String serializeMappingMethod(GLSchemaMapping mapping, String serviceInstanceName, GLToken context) {
    if (mapping.forwarded) {
      return serializeForwardedMapping(mapping, context);
    }
    if (mapping.forbid && generateSchema) {
      return "";
    }
    if (mapping.forbid) {
      context.addImport(SpringImports.gqlGraphQLException);
      return '${serializeControllerMethodHeader(mapping, context)} ${codeGenUtils.block([
            '''throw GraphQLException("Access denied to field '${mapping.type.tokenInfo}.${mapping.field.name}'")'''
          ])}';
    }

    if (mapping.identity) {
      return serializeIdentityMapping(mapping, context);
    }

    final List<String> statements;
    if (mapping.isBatch) {
      final parentTypeName = getMapTo(mapping.type.tokenInfo);
      final typedVar = codeGenUtils.safeLocalVar('typed');
      final svcVar = codeGenUtils.safeLocalVar('svc');
      final typedListDecl = 'val $typedVar = value.map { $parentTypeName.fromJson(it) }';

      final svcCallBuf = StringBuffer('$serviceInstanceName.${mapping.key}($typedVar');
      for (var arg in mapping.field.arguments) {
        svcCallBuf.write(', ${arg.codeName}');
      }
      if (injectDataFetching || mapping.field.hasDirective(glReturnsProjection)) {
        svcCallBuf.write(', dataFetchingEnvironment');
      }
      svcCallBuf.write(')');
      final svcCall = svcCallBuf.toString();

      final outputStmts = _batchOutputMapStatements(mapping.field.type, svcVar, typedVar);
      final preceding = [
        typedListDecl,
        'val $svcVar = $svcCall',
        ...outputStmts.sublist(0, outputStmts.length - 1),
      ];
      statements = _wrapBody(preceding, outputStmts.last, context);
    } else {
      final rawCall = StringBuffer('$serviceInstanceName.${mapping.key}(${_fromJsonParentExpr(mapping)}');
      for (var arg in mapping.field.arguments) {
        rawCall.write(', ${arg.codeName}');
      }
      if (injectDataFetching || mapping.field.hasDirective(glReturnsProjection)) {
        rawCall.write(', dataFetchingEnvironment');
      }
      rawCall.write(')');
      final wrappedCall = _wrapWithToJson(mapping.field.type, rawCall.toString());
      statements = _wrapBody([], wrappedCall, context);
    }
    return '${serializeControllerMethodHeader(mapping, context)} ${codeGenUtils.block(statements)}';
  }

  @override
  String serializeIdentityMapping(GLSchemaMapping mapping, GLToken context) {
    var buffer = StringBuffer();
    var annotation = getAnnotationForMapping(mapping, context);
    if (annotation.isNotEmpty) {
      buffer.writeln(annotation);
    }

    final type = serializer.serializeType(mapping.field.type, false);
    final argType = mapping.isBatch ? 'List<$type>' : type;

    buffer.writeln(codeGenUtils.suspendFun(
      name: mapping.key,
      arguments: ['value: $argType'],
      returnType: argType,
      statements: ['return value'],
    ));

    return buffer.toString();
  }

  @override
  String serializeForwardedMapping(GLSchemaMapping mapping, GLToken context) {
    var buffer = StringBuffer();
    buffer.writeln(getAnnotationForMapping(mapping, context));

    final fieldName = mapping.field.name.token;
    final fieldType = serializer.serializeType(mapping.field.type, false);
    final argType = serializer.serializeType(getServiceReturnType(GLType(mapping.type.tokenInfo, false)), false);

    buffer.writeln(codeGenUtils.suspendFun(
      name: mapping.key,
      arguments: ['value: $argType'],
      returnType: fieldType,
      statements: ['return value.$fieldName'],
    ));

    return buffer.toString();
  }

  String _getReturnType(GLSchemaMapping mapping, GLToken context) {
    if (mapping.isBatch) {
      final keyType = serializer.serializeType(getServiceReturnType(GLType(mapping.type.tokenInfo, false)), false);
      final valueType = serializer.serializeType(mapping.field.type, false);
      return 'Map<$keyType, $valueType>';
    }
    return serializer.serializeType(mapping.field.type, false);
  }

  String _getControllerReturnType(GLSchemaMapping mapping, GLToken context) {
    if (mapping.isBatch) {
      return 'Map<Map<String, Any?>, ${_mapifyType(mapping.field.type)}>';
    }
    return _mapifyType(mapping.field.type);
  }

  String _getMappingArgument(GLSchemaMapping mapping, GLToken context) {
    final argType = serializer.serializeType(getServiceReturnType(GLType(mapping.type.tokenInfo, false)), false);
    if (mapping.isBatch) {
      return 'value: List<$argType>';
    }
    return 'value: $argType';
  }

  String _getControllerMappingArgument(GLSchemaMapping mapping) {
    if (mapping.isBatch) {
      return 'value: List<Map<String, Any?>>';
    }
    return 'value: Map<String, Any?>';
  }

  String _fromJsonParentExpr(GLSchemaMapping mapping) {
    final parentTypeName = getMapTo(mapping.type.tokenInfo);
    if (mapping.isBatch) {
      return 'value.map { $parentTypeName.fromJson(it) }';
    }
    return '$parentTypeName.fromJson(value)';
  }

  @override
  String serializeControllerMethodHeader(GLSchemaMapping mapping, GLToken context) {
    var buffer = StringBuffer();
    buffer.writeln(getAnnotationForMapping(mapping, context));

    final args = [_getControllerMappingArgument(mapping)];
    for (var arg in mapping.field.arguments) {
      context.addImport(SpringImports.gqlArgument);
      args.add('${_argumentAnnotation(arg)} ${arg.codeName}: ${resolveArgType(arg, context)}');
    }
    if (injectDataFetching || mapping.field.hasDirective(glReturnsProjection)) {
      context.addImport(SpringImports.gqlDataFetchingEnvironment);
      args.add('dataFetchingEnvironment: DataFetchingEnvironment');
    }

    buffer.write('suspend fun ${mapping.key}(${args.join(", ")}): ${_getControllerReturnType(mapping, context)}');
    return buffer.toString();
  }

  // ── Service declarations ───────────────────────────────────────────────────

  @override
  String serializeMethodDeclaration(GLField method, GLQueryType type, GLToken context, {String? argPrefix}) {
    final isValidation = method.getDirectiveByName(glValidate)?.generated == true;
    var args = serializeArgs(method.arguments, context, argPrefix);

    if (injectDataFetching || method.hasDirective(glReturnsProjection)) {
      context.addImport(SpringImports.gqlDataFetchingEnvironment);
      const inject = 'dataFetchingEnvironment: DataFetchingEnvironment';
      args = args.isEmpty ? inject : '$args, $inject';
    }

    final prefix = type == GLQueryType.subscription ? 'fun' : 'suspend fun';
    if (isValidation) {
      return '$prefix ${method.codeName}($args)';
    }
    return '$prefix ${method.codeName}($args): ${_serializeReturnType(method.type, type, context)}';
  }

  @override
  String serializeServiceMappingImplMethodHeader(GLSchemaMapping mapping, GLToken context) {
    final args = [_getMappingArgument(mapping, context)];
    for (var arg in mapping.field.arguments) {
      args.add('${arg.codeName}: ${resolveArgType(arg, context)}');
    }
    if (injectDataFetching || mapping.field.hasDirective(glReturnsProjection)) {
      context.addImport(SpringImports.gqlDataFetchingEnvironment);
      args.add('dataFetchingEnvironment: DataFetchingEnvironment');
    }
    return 'suspend fun ${mapping.key}(${args.join(", ")}): ${_getReturnType(mapping, context)}';
  }

  // ── Args ────────────────────────────────────────────────────────────────────

  @override
  String serializeArg(GLArgumentDefinition arg, GLToken context) {
    return '${arg.codeName}: ${resolveArgType(arg, context)}';
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
      context.addImport(SpringImports.multipartFile);
      if (arg.type.isList) {
        return 'List<MultipartFile>';
      }
      return 'MultipartFile';
    }
    return serializer.serializeType(arg.type, false);
  }
}
