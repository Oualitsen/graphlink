import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/kotlin_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_rest_controller.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_intercept_extension.dart';
import 'package:graphlink/src/serializers/jvm_spring_rest_controller_serializer_base.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_imports.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_serializer.dart';

class KotlinSpringRestControllerSerializer extends JvmSpringRestControllerSerializerBase {
  @override
  final KotlinSerializer serializer;
  @override
  final KotlinCodeGenUtils codeGenUtils = KotlinCodeGenUtils();
  @override
  final String packageName;
  final bool suspendServices;

  KotlinSpringRestControllerSerializer(super.grammar,
      {required this.serializer, required this.packageName, required this.suspendServices});

  @override
  GLType get jsonMapValueType => GLType('Any'.toToken(), true);

  @override
  String renderParam(String annotation, String name, GLType type) =>
      [annotation, '$name: ${serializer.serializeType(type)}'].where((part) => part.isNotEmpty).join(' ');

  @override
  String exceptionHandlerMethod(String exception, String status, String name) =>
      '@ExceptionHandler($exception::class)\n@ResponseStatus(HttpStatus.$status)\n${codeGenUtils.createMethod(returnType: 'Unit', methodName: name, statements: [])}';

  @override
  String filePartExpression(String part) => throw UnsupportedError('Kotlin Spring has no reactive mode');

  @override
  RawUploadBinding rawUploadBinding(GLToken context) {
    context.addImport('$packageName.rest.GraphLinkRestUpload');
    context.addImport(SpringRestImports.servletRequest);
    return RawUploadBinding([renderParam('', '__gl_request__', GLType('HttpServletRequest'.toToken(), false))],
        'GraphLinkRestUpload.rawFile(__gl_request__)');
  }

  @override
  StructuredParams structuredParams(RestArgRole role, GLToken context) {
    context.addImport('org.springframework.util.MultiValueMap');
    context.addImport(SpringRestImports.requestParam);
    return StructuredParams(
        [renderParam('@RequestParam', '__gl_params__', GLType('MultiValueMap<String, String>'.toToken(), false))], const [], '__gl_params__');
  }

  @override
  String formParameter(GLToken context) => throw UnsupportedError('Kotlin Spring has no reactive mode');

  @override
  List<String> formFieldDeclarations(GLRestArgument restArg, GLToken context,
          {required bool required, String? defaultLiteral}) =>
      throw UnsupportedError('Kotlin Spring binds form fields with @RequestParam');

  @override
  String textPartExpression(GLType type, String text, GLToken context) =>
      throw UnsupportedError('Kotlin Spring binds multipart text parts with @RequestParam');

  @override
  String runBeforeCall(String? tagArg, String operation, List<String> rawArgs, String contextVar) {
    final args = [if (tagArg != null) tagArg, operation.quote(), 'listOf(${rawArgs.join(', ')})', contextVar];
    return 'interceptor.runBefore(${args.join(', ')})';
  }

  @override
  String annotationArray(String element) => '[$element]';

  @override
  String pathAttribute(String quotedPath) => quotedPath;

  @override
  String decodeCall(String expression) => '$restSupportClassName.decode { $expression }';

  @override
  String declareWireMap(String name) => codeGenUtils.constDecl(name, 'mutableMapOf<String, Any?>()');

  @override
  String putIfPresent(String map, String key, String value) => codeGenUtils.ifStatement(
      condition: '$value != null', ifBlockStatements: ['$map[${key.quote()}] = $value']);

  @override
  String mapIsEmpty(String map) => '$map.isEmpty()';

  @override
  String serializeRestController(GLRestController ctrl) {
    final serviceName = ctrl.serviceName;
    final serviceInstanceName = serviceName.firstLow;
    ctrl.addImport(SpringRestImports.restController);
    ctrl.addImport('$packageName.rest.$restSupportClassName');
    final handlers = [
      for (final op in ctrl.operations) serializeHandler(op, ctrl, serviceInstanceName),
      ...multipartErrorHandlers(ctrl),
    ];
    final interceptor = usesInterceptor(ctrl) ? grammar.interfaces[glInterceptorInterfaceName]! : null;
    final body = codeGenUtils.kotlinClass(
        name: ctrl.token,
        params: [
          'private val $serviceInstanceName: $serviceName',
          if (interceptor != null) 'private val interceptor: ${interceptor.codeName}',
        ],
        body: handlers.expand((handler) => [handler, '']).toList());
    return serializer.serializeWithImport(ctrl, '@RestController\n$body');
  }

  @override
  String serializeHandler(GLRestOperation op, GLRestController ctrl, String serviceInstanceName) {
    final plan = this.plan(op, ctrl);
    final serviceCall = serviceCallOf(op, serviceInstanceName, plan.serviceArgs);
    final validation = validationCallOf(op, serviceInstanceName, plan.serviceArgs);
    addReturnDependencies(op, ctrl);
    final result = handlerResult(op, serviceCall, validation, ctrl, interceptCall: plan.interceptCall);
    final annotations = [
      plan.mapping,
      if (result.noContent) ..._noContentAnnotation(ctrl),
    ];
    final method = codeGenUtils.createMethod(
      returnType: result.returnType,
      methodName: op.field.codeName,
      arguments: plan.params,
      statements: [...plan.declarations, ...result.statements],
    );
    return '${annotations.join('\n')}\n${suspendServices || isIntercepted(op) ? 'suspend ' : ''}$method';
  }

  List<String> _noContentAnnotation(GLToken ctrl) {
    ctrl.addImport(SpringRestImports.responseStatus);
    ctrl.addImport(SpringRestImports.httpStatus);
    return ['@ResponseStatus(HttpStatus.NO_CONTENT)'];
  }

  @override
  RestHandlerResult handlerResult(GLRestOperation op, String serviceCall, String? validationCall, GLToken context,
      {String? interceptCall}) {
    final field = op.field;
    final value = _value(!suspendServices && interceptCall != null, [if (validationCall != null) validationCall, serviceCall], context);
    final before = [if (interceptCall != null) interceptCall, ...value.before];
    if (isDownload(op)) {
      context.addImport('$packageName.rest.GraphLinkDownload');
      context.addImport('org.springframework.core.io.Resource');
      context.addImport('org.springframework.http.ResponseEntity');
      return RestHandlerResult(
          returnType: 'ResponseEntity<Resource>', statements: [...before, 'return GraphLinkDownload.toResponse(${value.expression})']);
    }
    if (wrapsResponse(op)) {
      final resultVar = codeGenUtils.safeLocalVar('result');
      return RestHandlerResult(returnType: 'Any?', statements: [
        ...before,
        codeGenUtils.constDecl(resultVar, value.expression),
        'return ${wrapCall(op, serializer.toJsonExpr(field.type, resultVar, context: context))}',
      ]);
    }
    if (returnsVoid(op)) {
      return RestHandlerResult(returnType: 'Unit', statements: [...before, value.expression], noContent: true);
    }
    final jsonString = returnsJsonString(op);
    final returnType = jsonString ? 'Any?' : serializer.serializeType(wireReturnType(field));
    if (!returnsConvertedValue(field) && !jsonString) {
      return RestHandlerResult(returnType: returnType, statements: [...before, 'return ${value.expression}']);
    }
    final resultVar = codeGenUtils.safeLocalVar('result');
    final json = serializer.toJsonExpr(field.type, resultVar, context: context);
    return RestHandlerResult(returnType: returnType, statements: [
      ...before,
      codeGenUtils.constDecl(resultVar, value.expression),
      'return ${jsonString ? '$restSupportClassName.json($json)' : json}',
    ]);
  }

  /// The statements to run before [calls]' last one, which yields the value. A blocking service called from a suspending
  /// handler (an intercepted operation) runs all of them on the IO dispatcher.
  _Value _value(bool onIo, List<String> calls, GLToken context) {
    if (!onIo) return _Value(calls.take(calls.length - 1).toList(), calls.last);
    context.addImport(KotlinImports.withContext);
    context.addImport(KotlinImports.dispatchers);
    context.addImport('$packageName.security.SecurityCoroutineContext');
    return _Value(const [], 'withContext(Dispatchers.IO + SecurityCoroutineContext()) ${codeGenUtils.block(calls)}');
  }
}

class _Value {
  final List<String> before;
  final String expression;

  _Value(this.before, this.expression);
}
