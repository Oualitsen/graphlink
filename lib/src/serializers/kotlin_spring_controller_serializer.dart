import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
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

    var args = method.arguments.map((arg) {
      final argDecorators = serializer.serializeDecorators(arg.getDirectives()).trim();
      final decl = '${arg.token}: ${resolveArgType(arg, context)}';
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

    var serviceArgs = method.arguments.map((arg) => arg.tokenInfo.token).toList();
    if (injectFetchingEnv) {
      serviceArgs.add('dataFetchingEnvironment');
    }
    final serviceCall = '$serviceInstanceName.${method.name}(${serviceArgs.join(", ")})';

    final validationMethodCall = method.getDirectiveByName(glValidate) != null
        ? '$serviceInstanceName.${GLService.getValidationMethodName(method.name.token)}(${serviceArgs.join(", ")})'
        : null;

    final returnType = _serializeReturnType(method.type, type, context);

    if (type == GLQueryType.subscription) {
      final statements = [
        if (validationMethodCall != null) validationMethodCall,
        'return $serviceCall',
      ];
      buffer.writeln(codeGenUtils.method(
          returnType: returnType, methodName: method.name.token, arguments: args, statements: statements));
    } else {
      final statements = _wrapBody(
        [if (validationMethodCall != null) validationMethodCall],
        serviceCall,
        context,
      );
      buffer.writeln(codeGenUtils.suspendFun(
          name: method.name.token, arguments: args, returnType: returnType, statements: statements));
    }

    return buffer.toString();
  }

  String _serializeReturnType(GLType type, GLQueryType queryType, GLToken context) {
    final returnType = getServiceReturnType(type);
    if (queryType == GLQueryType.subscription) {
      context.addImport(KotlinImports.flow);
      return 'Flow<${serializer.serializeType(returnType, false)}>';
    }
    return serializer.serializeType(returnType, false);
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

    final statement = StringBuffer('$serviceInstanceName.${mapping.key}(value');
    for (var arg in mapping.field.arguments) {
      statement.write(', ${arg.tokenInfo}');
    }
    if (injectDataFetching || mapping.field.hasDirective(glReturnsProjection)) {
      statement.write(', dataFetchingEnvironment');
    }
    statement.write(')');
    final statements = _wrapBody([], statement.toString(), context);
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

  String _getMappingArgument(GLSchemaMapping mapping, GLToken context) {
    final argType = serializer.serializeType(getServiceReturnType(GLType(mapping.type.tokenInfo, false)), false);
    if (mapping.isBatch) {
      return 'value: List<$argType>';
    }
    return 'value: $argType';
  }

  @override
  String serializeControllerMethodHeader(GLSchemaMapping mapping, GLToken context) {
    var buffer = StringBuffer();
    buffer.writeln(getAnnotationForMapping(mapping, context));

    final args = [_getMappingArgument(mapping, context)];
    for (var arg in mapping.field.arguments) {
      context.addImport(SpringImports.gqlArgument);
      args.add('@Argument ${arg.tokenInfo}: ${resolveArgType(arg, context)}');
    }
    if (injectDataFetching || mapping.field.hasDirective(glReturnsProjection)) {
      context.addImport(SpringImports.gqlDataFetchingEnvironment);
      args.add('dataFetchingEnvironment: DataFetchingEnvironment');
    }

    buffer.write('suspend fun ${mapping.key}(${args.join(", ")}): ${_getReturnType(mapping, context)}');
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
      return '$prefix ${method.name}($args)';
    }
    return '$prefix ${method.name}($args): ${_serializeReturnType(method.type, type, context)}';
  }

  @override
  String serializeServiceMappingImplMethodHeader(GLSchemaMapping mapping, GLToken context) {
    final args = [_getMappingArgument(mapping, context)];
    for (var arg in mapping.field.arguments) {
      args.add('${arg.tokenInfo}: ${resolveArgType(arg, context)}');
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
    return '${arg.tokenInfo}: ${resolveArgType(arg, context)}';
  }

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
