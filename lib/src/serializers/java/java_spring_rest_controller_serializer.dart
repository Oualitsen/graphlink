import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_rest_controller.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_intercept_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_validation_extension.dart';
import 'package:graphlink/src/serializers/java/java_imports.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:graphlink/src/serializers/jvm_spring_rest_controller_serializer_base.dart';

class JavaSpringRestControllerSerializer extends JvmSpringRestControllerSerializerBase {
  @override
  final JavaSerializer serializer;
  @override
  final JavaCodeGenUtils codeGenUtils = JavaCodeGenUtils();
  @override
  final bool reactive;
  @override
  final String packageName;

  JavaSpringRestControllerSerializer(super.grammar,
      {required this.serializer, required this.reactive, required this.packageName});

  @override
  GLType get jsonMapValueType => GLType('Object'.toToken(), false);

  @override
  String renderParam(String annotation, String name, GLType type) =>
      [annotation, serializer.serializeType(type).replaceAll('? extends ', ''), name].where((part) => part.isNotEmpty).join(' ');

  @override
  String exceptionHandlerMethod(String exception, String status, String name) =>
      '@ExceptionHandler($exception.class)\n@ResponseStatus(HttpStatus.$status)\n${codeGenUtils.createMethod(returnType: 'public void', methodName: name, statements: [])}';

  @override
  String filePartExpression(String part) => '$restSupportClassName.filePart($part)';

  @override
  RawUploadBinding rawUploadBinding(GLToken context) {
    context.addImport('$packageName.rest.GraphLinkRestUpload');
    if (!reactive) {
      context.addImport(SpringRestImports.servletRequest);
      return RawUploadBinding([renderParam('', '__gl_request__', GLType('HttpServletRequest'.toToken(), false))],
          'GraphLinkRestUpload.rawFile(__gl_request__)');
    }
    context.addImport(JavaImports.flux);
    context.addImport(SpringRestImports.requestBody);
    context.addImport(SpringRestImports.requestHeader);
    context.addImport('org.springframework.core.io.buffer.DataBuffer');
    context.addImport('org.springframework.http.HttpHeaders');
    return RawUploadBinding([
      '@RequestBody(required = false) Flux<DataBuffer> __gl_body__',
      '@RequestHeader HttpHeaders __gl_headers__',
    ], 'GraphLinkRestUpload.rawFile(__gl_headers__, __gl_body__)');
  }

  @override
  StructuredParams structuredParams(RestArgRole role, GLToken context) {
    context.addImport('org.springframework.util.MultiValueMap');
    if (!reactive) {
      context.addImport(SpringRestImports.requestParam);
      return StructuredParams(['@RequestParam MultiValueMap<String, String> __gl_params__'], const [], '__gl_params__');
    }
    context.addImport('org.springframework.web.server.ServerWebExchange');
    const exchange = 'ServerWebExchange $_exchangeVar';
    if (role == RestArgRole.field) return StructuredParams(const [exchange], const [], _formVar);
    return StructuredParams(const [
      exchange
    ], [
      codeGenUtils.constDecl('__gl_query__', '$_exchangeVar.getRequest().getQueryParams()', type: 'MultiValueMap<String, String>')
    ], '__gl_query__');
  }

  @override
  String formParameter(GLToken context) {
    context.addImport('org.springframework.web.server.ServerWebExchange');
    return 'ServerWebExchange $_exchangeVar';
  }

  @override
  List<String> formFieldDeclarations(GLRestArgument restArg, GLToken context,
      {required bool required, String? defaultLiteral}) {
    final arg = restArg.argument;
    final wire = '${arg.codeName}Wire';
    final name = restArg.wireName!.quote();
    final type = arg.type;
    if (type is GLListType) {
      final element = textPartExpression(GLType(type.inlineType.tokenInfo, false), '__gl_value__', context);
      final converted = '$wire.stream().map(__gl_value__ -> $element).toList()';
      context.addImport(JavaImports.list);
      return [
        codeGenUtils.constDecl(wire, '$restSupportClassName.fields($_formVar, $name, $required)', type: 'List<String>'),
        codeGenUtils.constDecl(arg.codeName,
            decodeCall(type.nullable ? '$wire == null ? null : $converted' : converted)),
      ];
    }
    final read = defaultLiteral == null
        ? '$restSupportClassName.field($_formVar, $name, $required)'
        : '$restSupportClassName.field($_formVar, $name, ${defaultLiteral.quote()})';
    final parsed = textPartExpression(defaultLiteral == null ? type : GLType(type.tokenInfo, false), wire, context);
    return [
      codeGenUtils.constDecl(wire, read, type: 'String'),
      codeGenUtils.constDecl(arg.codeName, decodeCall(parsed)),
    ];
  }

  static const _formVar = '__gl_form__';
  static const _exchangeVar = '__gl_exchange__';

  @override
  String textPartExpression(GLType type, String text, GLToken context) {
    final token = type.token;
    final String parsed;
    if (token == 'Int') {
      parsed = 'Integer.valueOf($text)';
    } else if (token == 'Float') {
      parsed = 'Double.valueOf($text)';
    } else if (token == 'Boolean') {
      parsed = '$restSupportClassName.bool($text)';
    } else if (grammar.isEnum(token)) {
      return serializer.fromJsonExpr(type, text, context: context);
    } else {
      return text;
    }
    return type.nullable ? '$text == null ? null : $parsed' : parsed;
  }

  @override
  String runBeforeCall(String? tagArg, String operation, List<String> rawArgs, String contextVar) {
    final args = [if (tagArg != null) tagArg, operation.quote(), 'Arrays.asList(${rawArgs.join(', ')})', contextVar];
    return 'interceptor.runBefore(${args.join(', ')})';
  }

  @override
  String annotationArray(String element) => element;

  @override
  String pathAttribute(String quotedPath) => 'value = $quotedPath';

  @override
  String decodeCall(String expression) => '$restSupportClassName.decode(() -> $expression)';

  @override
  String declareWireMap(String name) => codeGenUtils.constDecl(name, 'new HashMap<>()', type: 'Map<String, Object>');

  @override
  String putIfPresent(String map, String key, String value) => codeGenUtils.ifStatement(
      condition: '$value != null', ifBlockStatements: ['$map.put(${key.quote()}, $value);']);

  @override
  String mapIsEmpty(String map) => '$map.isEmpty()';

  @override
  String serializeRestController(GLRestController ctrl) {
    final serviceName = ctrl.serviceName;
    final serviceInstanceName = serviceName.firstLow;
    ctrl.addImport(SpringRestImports.restController);
    ctrl.addImport('$packageName.rest.$restSupportClassName');
    addCollectionImports(ctrl);
    ctrl.addImport(JavaImports.hashMap);
    final handlers = [
      for (final op in ctrl.operations) serializeHandler(op, ctrl, serviceInstanceName),
      ...multipartErrorHandlers(ctrl),
    ];
    final interceptor = usesInterceptor(ctrl) ? grammar.interfaces[glInterceptorInterfaceName]! : null;
    final body = codeGenUtils.createClass(className: ctrl.token, statements: [
      'private final $serviceName $serviceInstanceName;',
      if (interceptor != null) 'private final ${interceptor.codeName} interceptor;',
      '',
      serializer.accessors.generateContructor(
          ctrl.token,
          [
            GLField(name: serviceInstanceName.toToken(), type: GLType(serviceName.toToken(), false), arguments: [], directives: []),
            if (interceptor != null)
              GLField(name: 'interceptor'.toToken(), type: GLType(interceptor.tokenInfo, false), arguments: [], directives: []),
          ],
          'public',
          ctrl),
      '',
      ...handlers.expand((handler) => [handler, '']),
    ]);
    return serializer.serializeWithImport(ctrl, '@RestController\n$body');
  }

  @override
  String serializeHandler(GLRestOperation op, GLRestController ctrl, String serviceInstanceName) {
    final plan = this.plan(op, ctrl);
    final serviceCall = serviceCallOf(op, serviceInstanceName, plan.serviceArgs);
    final validation = validationCallOf(op, serviceInstanceName, plan.serviceArgs);
    addReturnDependencies(op, ctrl);
    final result = handlerResult(op, serviceCall, validation, ctrl, interceptCall: plan.interceptCall);
    ctrl.addImport(JavaImports.supplier);
    if (plan.interceptCall != null) ctrl.addImport(JavaImports.arrays);
    final annotations = [
      plan.mapping,
      if (result.noContent) ..._noContentAnnotation(ctrl),
    ];
    final body = [...plan.declarations, ...result.statements];
    final method = codeGenUtils.createMethod(
      returnType: 'public ${result.returnType}',
      methodName: op.field.codeName,
      arguments: plan.params,
      statements: plan.readsForm
          ? ['return $_exchangeVar.getFormData().flatMap($_formVar -> ${codeGenUtils.block(body)});']
          : body,
    );
    return '${annotations.join('\n')}\n$method';
  }

  List<String> _noContentAnnotation(GLToken ctrl) {
    ctrl.addImport(SpringRestImports.responseStatus);
    ctrl.addImport(SpringRestImports.httpStatus);
    return ['@ResponseStatus(HttpStatus.NO_CONTENT)'];
  }

  @override
  RestHandlerResult handlerResult(GLRestOperation op, String serviceCall, String? validationCall, GLToken context,
      {String? interceptCall}) {
    final preCalls = [if (interceptCall != null) interceptCall, if (validationCall != null) validationCall];
    return reactive ? _reactiveResult(op, serviceCall, preCalls, context) : _blockingResult(op, serviceCall, preCalls, context);
  }

  RestHandlerResult _blockingResult(GLRestOperation op, String serviceCall, List<String> preCalls, GLToken context) {
    final field = op.field;
    final validate = [for (final call in preCalls) '$call;'];
    if (isDownload(op)) {
      _importDownload(context);
      return RestHandlerResult(
          returnType: 'ResponseEntity<Resource>', statements: [...validate, 'return GraphLinkDownload.toResponse($serviceCall);']);
    }
    if (returnsVoid(op)) {
      return RestHandlerResult(returnType: 'void', statements: [...validate, '$serviceCall;'], noContent: true);
    }
    if (wrapsResponse(op)) {
      final resultVar = codeGenUtils.safeLocalVar('result');
      return RestHandlerResult(returnType: 'Object', statements: [
        ...validate,
        codeGenUtils.constDecl(resultVar, serviceCall),
        'return ${wrapCall(op, serializer.toJsonExpr(field.type, resultVar, context: context))};',
      ]);
    }
    final jsonString = returnsJsonString(op);
    final returnType = jsonString ? 'Object' : serializer.serializeType(wireReturnType(field));
    if (!returnsConvertedValue(field) && !jsonString) {
      return RestHandlerResult(returnType: returnType, statements: [...validate, 'return $serviceCall;']);
    }
    final resultVar = codeGenUtils.safeLocalVar('result');
    final json = serializer.toJsonExpr(field.type, resultVar, context: context);
    return RestHandlerResult(returnType: returnType, statements: [
      ...validate,
      codeGenUtils.constDecl(resultVar, serviceCall),
      'return ${jsonString ? '$restSupportClassName.json($json)' : json};',
    ]);
  }

  RestHandlerResult _reactiveResult(GLRestOperation op, String serviceCall, List<String> preCalls, GLToken context) {
    final field = op.field;
    context.addImport(JavaImports.mono);
    final chain = _chainPreCalls(preCalls);
    if (isDownload(op)) {
      _importDownload(context);
      return RestHandlerResult(returnType: 'Mono<ResponseEntity<Resource>>', statements: [
        'return ${chain('$serviceCall.map(GraphLinkDownload::toResponse).defaultIfEmpty(GraphLinkDownload.toResponse(null))')};'
      ]);
    }
    if (returnsVoid(op)) {
      return RestHandlerResult(
          returnType: 'Mono<Void>', statements: ['return ${chain('$serviceCall.then()')};'], noContent: true);
    }
    if (wrapsResponse(op)) return _reactiveWrapped(op, serviceCall, chain, context);
    final jsonString = returnsJsonString(op);
    final wire = jsonString ? 'Object' : _withoutWildcards(serializer.serializeType(wireReturnType(field)));
    final resultVar = codeGenUtils.safeLocalVar('result');
    final String body;
    if (field.type.isList) {
      final element = serializer.toJsonExpr(field.type.inlineType, resultVar, context: context);
      body = element == resultVar ? '$serviceCall.collectList()' : '$serviceCall.map($resultVar -> $element).collectList()';
    } else if (jsonString) {
      body = '$serviceCall.map($resultVar -> $restSupportClassName.json(${serializer.toJsonExpr(field.type, resultVar, context: context)}))';
    } else if (returnsConvertedValue(field)) {
      body = '$serviceCall.map($resultVar -> ${serializer.toJsonExpr(field.type, resultVar, context: context)})';
    } else {
      body = serviceCall;
    }
    return RestHandlerResult(returnType: 'Mono<$wire>', statements: ['return ${chain(body)};']);
  }

  RestHandlerResult _reactiveWrapped(GLRestOperation op, String serviceCall, String Function(String) chain, GLToken context) {
    final field = op.field;
    final resultVar = codeGenUtils.safeLocalVar('result');
    final String values;
    if (field.type.isList) {
      final element = serializer.toJsonExpr(field.type.inlineType, resultVar, context: context);
      values = element == resultVar ? '$serviceCall.collectList()' : '$serviceCall.map($resultVar -> $element).collectList()';
    } else {
      values = '$serviceCall.map($resultVar -> ${serializer.toJsonExpr(field.type, resultVar, context: context)})';
    }
    final wrapped = '$values.map($resultVar -> ${wrapCall(op, resultVar)}).defaultIfEmpty(${wrapCall(op, 'null')})';
    return RestHandlerResult(returnType: 'Mono<Object>', statements: ['return ${chain(wrapped)};']);
  }

  void _importDownload(GLToken context) {
    context.addImport('$packageName.rest.GraphLinkDownload');
    context.addImport('org.springframework.core.io.Resource');
    context.addImport('org.springframework.http.ResponseEntity');
  }

  String _withoutWildcards(String type) => type.replaceAll('? extends ', '');

  String Function(String) _chainPreCalls(List<String> preCalls) => (main) {
        var result = main;
        for (final call in preCalls.reversed) {
          result = '$call.then(Mono.defer(() -> $result))';
        }
        return result;
      };
}
