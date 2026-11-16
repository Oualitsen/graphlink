import 'package:graphlink/src/code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_intercept_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_server_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_rest_controller.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/java/java_imports.dart';

const restSupportClassName = 'GraphLinkRest';

/// The Spring annotation imports every REST controller needs, identical for Java and Kotlin.
class SpringRestImports {
  static const restController = 'org.springframework.web.bind.annotation.RestController';
  static const getMapping = 'org.springframework.web.bind.annotation.GetMapping';
  static const postMapping = 'org.springframework.web.bind.annotation.PostMapping';
  static const putMapping = 'org.springframework.web.bind.annotation.PutMapping';
  static const patchMapping = 'org.springframework.web.bind.annotation.PatchMapping';
  static const deleteMapping = 'org.springframework.web.bind.annotation.DeleteMapping';
  static const pathVariable = 'org.springframework.web.bind.annotation.PathVariable';
  static const requestParam = 'org.springframework.web.bind.annotation.RequestParam';
  static const requestHeader = 'org.springframework.web.bind.annotation.RequestHeader';
  static const requestBody = 'org.springframework.web.bind.annotation.RequestBody';
  static const responseStatus = 'org.springframework.web.bind.annotation.ResponseStatus';
  static const httpStatus = 'org.springframework.http.HttpStatus';
  static const mediaType = 'org.springframework.http.MediaType';
  static const requestPart = 'org.springframework.web.bind.annotation.RequestPart';
  static const servletRequest = 'jakarta.servlet.http.HttpServletRequest';
  static const exceptionHandler = 'org.springframework.web.bind.annotation.ExceptionHandler';
  static const multipartException = 'org.springframework.web.multipart.MultipartException';
  static const maxUploadSizeExceeded = 'org.springframework.web.multipart.MaxUploadSizeExceededException';
}

const _mappingAnnotation = {
  RestMethod.get: 'GetMapping',
  RestMethod.post: 'PostMapping',
  RestMethod.put: 'PutMapping',
  RestMethod.patch: 'PatchMapping',
  RestMethod.delete: 'DeleteMapping',
};

const _mappingImport = {
  RestMethod.get: SpringRestImports.getMapping,
  RestMethod.post: SpringRestImports.postMapping,
  RestMethod.put: SpringRestImports.putMapping,
  RestMethod.patch: SpringRestImports.patchMapping,
  RestMethod.delete: SpringRestImports.deleteMapping,
};

class _Binding {
  final String annotation;
  final String import;

  const _Binding(this.annotation, this.import);
}

const _bindings = {
  RestArgRole.path: _Binding('PathVariable', SpringRestImports.pathVariable),
  RestArgRole.query: _Binding('RequestParam', SpringRestImports.requestParam),
  RestArgRole.header: _Binding('RequestHeader', SpringRestImports.requestHeader),
};

/// Where the request parameters of a role live in a handler: the parameters and statements giving access to them.
class StructuredParams {
  final List<String> params;
  final List<String> declarations;
  final String variable;

  StructuredParams(this.params, this.declarations, this.variable);
}

class RawUploadBinding {
  final List<String> params;
  final String expression;

  RawUploadBinding(this.params, this.expression);
}

class RestHandlerPlan {
  final String mapping;
  final List<String> params;
  final List<String> declarations;
  final List<String> serviceArgs;

  /// The `interceptor.runBefore(...)` call of an intercepted operation.
  final String? interceptCall;

  /// True when the handler reads the form body off the exchange (WebFlux), which is asynchronous.
  final bool readsForm;

  RestHandlerPlan(
      {required this.mapping,
      required this.params,
      required this.declarations,
      required this.serviceArgs,
      this.interceptCall,
      this.readsForm = false});
}

/// The result of a REST handler once the service call is expressed: what the method returns and the statements producing it.
class RestHandlerResult {
  final String returnType;
  final List<String> statements;
  final bool noContent;

  RestHandlerResult({required this.returnType, required this.statements, this.noContent = false});
}

/// Language-agnostic planning of a Spring REST controller: which parameter binds which request part, and how every
/// wire value (number, string, map) becomes the domain value the service interface expects.
abstract class JvmSpringRestControllerSerializerBase {
  final GLParser grammar;

  JvmSpringRestControllerSerializerBase(this.grammar);

  GLSerializer get serializer;
  CodeGenUtilsBase get codeGenUtils;
  String get packageName;

  /// Spring WebFlux: uploads are `FilePart`s, there is no servlet request to stream a raw body from.
  bool get reactive => false;


  /// The value type of the wire map a model travels as (`Object` for Java, `Any?` for Kotlin).
  GLType get jsonMapValueType;

  String renderParam(String annotation, String name, GLType type);

  /// An annotation attribute holding an array, written with one element.
  String annotationArray(String element);

  /// The path of a mapping annotation: a bare first argument where the language allows it next to named ones.
  String pathAttribute(String quotedPath);

  String decodeCall(String expression);

  String declareWireMap(String name);

  String putIfPresent(String map, String key, String value);

  String mapIsEmpty(String map);

  String serializeRestController(GLRestController ctrl);

  /// Spring answers a request that is not a valid multipart body with a 500; it is the client's mistake: 400, and 413 above the size limit.
  List<String> multipartErrorHandlers(GLRestController ctrl) {
    if (!ctrl.operations.any((op) => op.bodyKind == RestBodyKind.multipart)) return const [];
    ctrl.addImport(SpringRestImports.exceptionHandler);
    ctrl.addImport(SpringRestImports.responseStatus);
    ctrl.addImport(SpringRestImports.httpStatus);
    if (reactive) {
      ctrl.addImport('org.springframework.core.codec.DecodingException');
      return [exceptionHandlerMethod('DecodingException', 'BAD_REQUEST', '__glBadMultipart')];
    }
    ctrl.addImport(SpringRestImports.multipartException);
    ctrl.addImport(SpringRestImports.maxUploadSizeExceeded);
    return [
      exceptionHandlerMethod('MaxUploadSizeExceededException', 'PAYLOAD_TOO_LARGE', '__glUploadTooLarge'),
      exceptionHandlerMethod('MultipartException', 'BAD_REQUEST', '__glBadMultipart'),
    ];
  }

  String exceptionHandlerMethod(String exception, String status, String name);

  RestHandlerResult handlerResult(GLRestOperation op, String serviceCall, String? validationCall, GLToken context,
      {String? interceptCall});

  /// `interceptor.runBefore(tag, "operation", <list of args>, context)` in the target language.
  String runBeforeCall(String? tagArg, String operation, List<String> rawArgs, String contextVar);

  // ── Shared planning ─────────────────────────────────────────────────────────

  String serializeHandler(GLRestOperation op, GLRestController ctrl, String serviceInstanceName);

  RestHandlerPlan plan(GLRestOperation op, GLRestController context) {
    final params = <String>[];
    final declarations = <String>[];
    final byName = <String, String>{};
    for (final restArg in op.arguments) {
      final collected = <String>[];
      _planArgument(restArg, context, params, declarations, collected);
      byName[restArg.argument.bareName] = collected.single;
    }
    final serviceArgs = _inServiceOrder(op, context, byName);
    final intercepted = isIntercepted(op);
    final passesContext = passesContextToService(op, context);
    if (intercepted || passesContext) {
      context.addImport("graphql.GraphQLContext");
      final request = _requestBinding(context);
      for (final param in request.params) {
        if (!params.contains(param)) params.add(param);
      }
      declarations.add(codeGenUtils.constDecl(_contextVar, '$restSupportClassName.context(${request.expression})', type: localType("GraphQLContext")));
      if (passesContext) serviceArgs.add(_contextVar);
    }
    return RestHandlerPlan(
        mapping: _mapping(op, context),
        params: params,
        declarations: declarations,
        serviceArgs: serviceArgs,
        interceptCall: intercepted ? _interceptCall(op, context, byName) : null,
        readsForm: reactive && op.bodyKind == RestBodyKind.form);
  }

  static const _contextVar = '__gl_context__';

  bool isIntercepted(GLRestOperation op) => grammar.isIntercepted(op.field, op.type);

  /// The service method takes the GraphQL context (global `injectContext`, `@glInjectContext` or an interceptor on it).
  bool passesContextToService(GLRestOperation op, GLRestController ctrl) =>
      _serviceField(op, ctrl).arguments.any((a) => a.codeName == 'graphQLContext');

  bool usesInterceptor(GLRestController ctrl) => ctrl.operations.any(isIntercepted);

  /// What a REST request offers an interceptor instead of a GraphQL context: the HTTP request, under the `request` key.
  RawUploadBinding _requestBinding(GLToken context) {
    if (reactive) {
      context.addImport('org.springframework.web.server.ServerWebExchange');
      return RawUploadBinding(
          [renderParam('', '__gl_exchange__', GLType('ServerWebExchange'.toToken(), false))], '__gl_exchange__');
    }
    context.addImport(SpringRestImports.servletRequest);
    return RawUploadBinding(
        [renderParam('', '__gl_request__', GLType('HttpServletRequest'.toToken(), false))], '__gl_request__');
  }

  String _interceptCall(GLRestOperation op, GLRestController ctrl, Map<String, String> byName) {
    final tagEnum = grammar.enums[glInterceptorTagEnumName];
    String? tagArg;
    if (tagEnum != null) {
      ctrl.addImportDependecy(tagEnum);
      final tag = grammar.interceptTag(op.field, op.type);
      tagArg = tag == null ? 'null' : '${tagEnum.codeName}.${tagEnum.values.firstWhere((v) => v.token == tag).codeName}';
    }
    ctrl.addImportDependecy(grammar.interfaces[glInterceptorInterfaceName]!);
    return runBeforeCall(tagArg, op.name, [for (final restArg in op.arguments) byName[restArg.argument.bareName]!], _contextVar);
  }

  GLField _serviceField(GLRestOperation op, GLRestController ctrl) =>
      ctrl.service.fields.firstWhere((f) => f.name.token == op.field.name.token, orElse: () => op.field);

  /// The service interface orders its arguments as the generator left them (an upload argument moves to the end), not as the schema does.
  List<String> _inServiceOrder(GLRestOperation op, GLRestController ctrl, Map<String, String> byName) {
    final serviceField = _serviceField(op, ctrl);
    final ordered = [for (final a in serviceField.arguments) if (byName.containsKey(a.bareName)) byName[a.bareName]!];
    return ordered.length == byName.length ? ordered : byName.values.toList();
  }

  String _mapping(GLRestOperation op, GLToken context) {
    context.addImport(_mappingImport[op.method]!);
    final attributes = [
      pathAttribute(op.path.quote()),
      if (op.responseKind == RestResponseKind.text) 'produces = ${annotationArray('text/plain'.quote())}',
    ];
    return '@${_mappingAnnotation[op.method]}(${attributes.join(', ')})';
  }

  void _planArgument(
      GLRestArgument restArg, GLToken context, List<String> params, List<String> declarations, List<String> serviceArgs) {
    final arg = restArg.argument;
    final code = arg.codeName;
    _addDependencies(arg.type, context);
    if (restArg.role == RestArgRole.body) {
      _isUpload(arg.type)
          ? _bindRawUpload(restArg, context, params, serviceArgs)
          : _bindBody(restArg, context, params, declarations, serviceArgs);
      return;
    }
    if (restArg.role == RestArgRole.part) {
      _bindPart(restArg, context, params, declarations, serviceArgs);
      return;
    }
    if (grammar.usesStructuredParams(restArg)) {
      _bindStructured(restArg, context, params, declarations, serviceArgs);
      return;
    }
    if (restArg.role == RestArgRole.field) {
      _bindFormField(restArg, context, params, declarations, serviceArgs);
      return;
    }
    final binding = _bindings[restArg.role];
    if (binding == null) {
      throw StateError('The REST argument \'$code\' has an unsupported role ${restArg.role.name}');
    }
    final spread = restArg.encoding == RestEncoding.spread && _isInput(arg.type);
    final bind = spread ? _bindSpread : _bindScalar;
    bind(restArg, binding.annotation, binding.import, context, params, declarations, serviceArgs,
        required: restArg.role == RestArgRole.path);
  }

  void _bindScalar(GLRestArgument restArg, String annotationName, String import, GLToken context, List<String> params,
      List<String> declarations, List<String> serviceArgs,
      {bool required = false}) {
    final arg = restArg.argument;
    final defaultLiteral = _defaultLiteral(arg);
    final mustBePresent = required || (!arg.type.nullable && defaultLiteral == null);
    context.addImport(import);
    final attributes = [
      'name = ${restArg.wireName!.quote()}',
      if (!required) 'required = $mustBePresent',
      if (defaultLiteral != null) 'defaultValue = ${defaultLiteral.quote()}',
    ];
    final converts = _needsConversion(arg.type);
    final wireName = converts ? '${arg.codeName}Wire' : arg.codeName;
    params.add(renderParam('@$annotationName(${attributes.join(', ')})', wireName,
        _wireType(arg.type, nullable: !mustBePresent && arg.type.nullable)));
    if (converts) {
      declarations.add(codeGenUtils.constDecl(arg.codeName, decodeCall(serializer.fromJsonExpr(arg.type, wireName, context: context)), type: localType(serializer.serializeType(arg.type))));
    }
    serviceArgs.add(arg.codeName);
  }

  void _bindSpread(GLRestArgument restArg, String annotationName, String import, GLToken context, List<String> params,
      List<String> declarations, List<String> serviceArgs,
      {bool required = false}) {
    final arg = restArg.argument;
    final input = grammar.inputs[arg.type.firstType.token]!;
    final mapName = '${arg.codeName}Wire';
    context.addImport(import);
    declarations.add(declareWireMap(mapName));
    for (final field in input.fields) {
      final paramName = '${arg.codeName}_${field.name.token}';
      final wire = restArg.spreadFields[field.name.token] ?? field.name.token;
      _addDependencies(field.type, context);
      params.add(renderParam('@$annotationName(name = ${wire.quote()}, required = false)', paramName,
          _wireType(field.type, nullable: true)));
      declarations.add(putIfPresent(mapName, field.name.token, paramName));
    }
    final decoded = decodeCall(serializer.fromJsonExpr(GLType(arg.type.tokenInfo, false), mapName, context: context));
    declarations.add(codeGenUtils.constDecl(
        arg.codeName,
        arg.type.nullable
            ? codeGenUtils.ternaryOp(
                condition: mapIsEmpty(mapName), positiveStatement: 'null', negativeStatement: decoded)
            : decoded,
        type: localType(serializer.serializeType(arg.type))));
    serviceArgs.add(arg.codeName);
  }

  /// An input object, a list of them, or any value sent as JSON text, carried by the query string or a form.
  void _bindStructured(GLRestArgument restArg, GLToken context, List<String> params, List<String> declarations,
      List<String> serviceArgs) {
    final arg = restArg.argument;
    final source = structuredParams(restArg.role, context);
    for (final param in source.params) {
      if (!params.contains(param)) params.add(param);
    }
    for (final declaration in source.declarations) {
      if (!declarations.contains(declaration)) declarations.add(declaration);
    }
    context.addImport('$packageName.rest.GraphLinkRestParams');
    final required = !arg.type.nullable;
    final String read;
    if (restArg.encoding == RestEncoding.json) {
      read = 'GraphLinkRestParams.json(${source.variable}, ${restArg.wireName!.quote()}, $required)';
    } else {
      final spread = restArg.encoding == RestEncoding.spread;
      final shape = _shapeExpression(arg.type, spreadFields: spread ? restArg.spreadFields : const {});
      read = 'GraphLinkRestParams.nested(${source.variable}, ${spread ? '""' : restArg.wireName!.quote()}, $shape, $required)';
    }
    final wireName = '${arg.codeName}Wire';
    final wireType = serializer.serializeType(_wireType(arg.type, nullable: arg.type.nullable)).replaceAll('? extends ', '');
    declarations.add(codeGenUtils.constDecl(wireName, decodeCall(read), type: wireType));
    declarations.add(codeGenUtils.constDecl(arg.codeName, decodeCall(serializer.fromJsonExpr(arg.type, wireName, context: context)), type: localType(serializer.serializeType(arg.type))));
    serviceArgs.add(arg.codeName);
  }

  String _shapeExpression(GLType type, {Map<String, String> spreadFields = const {}}) {
    const shape = 'GraphLinkRestParams.Shape';
    if (type is GLListType) return '$shape.list(${_shapeExpression(type.inlineType)})';
    final token = type.token;
    final enumDefinition = grammar.enums[token];
    if (enumDefinition != null) return '$shape.enumOf(${enumDefinition.values.map((v) => v.wireName.quote()).join(', ')})';
    final input = grammar.inputs[token];
    if (input != null) {
      final fields = input.fields.map((field) {
        final name = field.name.token;
        return '.field(${name.quote()}, ${(spreadFields[name] ?? name).quote()}, ${_shapeExpression(field.type)})';
      }).join();
      return '$shape.obj()$fields';
    }
    switch (token) {
      case 'Int':
        return '$shape.INT';
      case 'Float':
        return '$shape.FLOAT';
      case 'Boolean':
        return '$shape.BOOLEAN';
      default:
        return '$shape.STRING';
    }
  }

  /// The request parameters (query string and form) of [role], as a `MultiValueMap<String, String>`.
  StructuredParams structuredParams(RestArgRole role, GLToken context);

  void _bindFormField(GLRestArgument restArg, GLToken context, List<String> params, List<String> declarations,
      List<String> serviceArgs) {
    if (!reactive) {
      _bindScalar(restArg, 'RequestParam', SpringRestImports.requestParam, context, params, declarations, serviceArgs);
      return;
    }
    final arg = restArg.argument;
    final defaultLiteral = _defaultLiteral(arg);
    final form = formParameter(context);
    if (!params.contains(form)) params.add(form);
    declarations.addAll(formFieldDeclarations(restArg, context,
        required: !arg.type.nullable && defaultLiteral == null, defaultLiteral: defaultLiteral));
    serviceArgs.add(arg.codeName);
  }

  /// The parameter giving access to the `application/x-www-form-urlencoded` body (WebFlux only: `@RequestParam` reads the query string alone there).
  String formParameter(GLToken context);

  /// The statements reading a form field off the parameter of [formParameter] and converting it to the domain value.
  List<String> formFieldDeclarations(GLRestArgument restArg, GLToken context, {required bool required, String? defaultLiteral});

  void _bindPart(GLRestArgument restArg, GLToken context, List<String> params, List<String> declarations,
      List<String> serviceArgs) {
    final arg = restArg.argument;
    if (_isUpload(arg.type)) {
      final required = !arg.type.nullable;
      final base = GLType((reactive ? 'FilePart' : 'MultipartFile').toToken(), false);
      context.addImport(SpringRestImports.requestPart);
      context.addImport(reactive ? SpringImports.filePart : SpringImports.multipartFile);
      if (reactive && arg.type is! GLListType) {
        // WebFlux hands a text field to a FilePart parameter as a plain Part, which fails inside the invocation: check the kind here.
        final wireName = '${arg.codeName}Wire';
        context.addImport('org.springframework.http.codec.multipart.Part');
        params.add(renderParam('@RequestPart(name = ${restArg.wireName!.quote()}, required = $required)', wireName,
            GLType('Part'.toToken(), !required)));
        declarations.add(codeGenUtils.constDecl(arg.codeName, filePartExpression(wireName), type: localType("FilePart")));
        serviceArgs.add(arg.codeName);
        return;
      }
      final type = arg.type is GLListType ? GLListType(base, !required) : GLType(base.tokenInfo, !required);
      params.add(renderParam('@RequestPart(name = ${restArg.wireName!.quote()}, required = $required)', arg.codeName, type));
      serviceArgs.add(arg.codeName);
      return;
    }
    if (!reactive) {
      _bindScalar(restArg, 'RequestParam', SpringRestImports.requestParam, context, params, declarations, serviceArgs);
      return;
    }
    _bindReactiveTextPart(restArg, context, params, declarations, serviceArgs);
  }

  /// A WebFlux multipart text part arrives as a `String`, whatever its schema type.
  void _bindReactiveTextPart(GLRestArgument restArg, GLToken context, List<String> params, List<String> declarations,
      List<String> serviceArgs) {
    final arg = restArg.argument;
    if (arg.type is GLListType) {
      throw ParseException(
          "The multipart list '${arg.bareName}' of '${restArg.argument.bareName}' is not supported with reactive Spring: use one value per part",
          info: arg.tokenInfo);
    }
    context.addImport(SpringRestImports.requestPart);
    final wireName = '${arg.codeName}Wire';
    params.add(renderParam('@RequestPart(name = ${restArg.wireName!.quote()}, required = ${!arg.type.nullable})', wireName,
        GLType('String'.toToken(), true)));
    declarations.add(codeGenUtils.constDecl(arg.codeName, decodeCall(textPartExpression(arg.type, wireName, context)), type: localType(serializer.serializeType(arg.type))));
    serviceArgs.add(arg.codeName);
  }

  /// The expression checking that a multipart part is a file (WebFlux only).
  String filePartExpression(String part);

  String? localType(String type) => null;

  /// The expression parsing the text of a multipart part, null-safe when [type] is nullable.
  String textPartExpression(GLType type, String text, GLToken context);

  void _bindRawUpload(GLRestArgument restArg, GLToken context, List<String> params, List<String> serviceArgs) {
    final binding = rawUploadBinding(context);
    params.addAll(binding.params);
    serviceArgs.add(binding.expression);
  }

  /// The parameters that give access to a raw request body, and the expression building the upload the service takes from them.
  RawUploadBinding rawUploadBinding(GLToken context);

  bool _isUpload(GLType type) => grammar.uploadScalarNames.contains(type.firstType.token);

  void _bindBody(GLRestArgument restArg, GLToken context, List<String> params, List<String> declarations,
      List<String> serviceArgs) {
    final arg = restArg.argument;
    final optional = restOperationBodyIsOptional(arg);
    context.addImport(SpringRestImports.requestBody);
    final wireName = '${arg.codeName}Wire';
    params.add(renderParam('@RequestBody(required = ${!optional})', wireName, _wireType(arg.type, nullable: optional)));
    declarations.add(codeGenUtils.constDecl(arg.codeName, decodeCall(serializer.fromJsonExpr(arg.type, wireName, context: context)), type: localType(serializer.serializeType(arg.type))));
    serviceArgs.add(arg.codeName);
  }

  bool restOperationBodyIsOptional(GLArgumentDefinition arg) => arg.type.nullable || arg.defaultValue != null;

  String? _defaultLiteral(GLArgumentDefinition arg) {
    final value = arg.defaultValue?.value;
    if (value == null) return null;
    return value.toString();
  }

  bool _isInput(GLType type) => grammar.inputs.containsKey(type.firstType.token);

  bool _needsConversion(GLType type) {
    final token = type.firstType.token;
    return grammar.isEnum(token) || grammar.isProjectableType(token);
  }

  GLType _wireType(GLType type, {required bool nullable}) {
    if (type is GLListType) {
      return GLListType(_wireType(type.inlineType, nullable: type.inlineType.nullable), nullable);
    }
    final token = type.token;
    if (grammar.isEnum(token)) return GLType('String'.toToken(), nullable);
    if (grammar.isProjectableType(token)) {
      return GLMapType(GLType('String'.toToken(), false), jsonMapValueType, nullable);
    }
    return GLType(type.tokenInfo, nullable);
  }

  /// The type of the JSON the handler returns for [field].
  GLType wireReturnType(GLField field) => _wireType(field.type, nullable: field.type.nullable);

  bool returnsConvertedValue(GLField field) => _needsConversion(field.type);

  bool returnsJsonString(GLRestOperation op) {
    if (op.responseKind != RestResponseKind.json || op.field.type.isList) return false;
    final token = op.field.type.token;
    return token == 'String' || token == 'ID' || grammar.isEnum(token);
  }

  bool wrapsResponse(GLRestOperation op) => op.responseKind == RestResponseKind.json && op.responsePathSegments.isNotEmpty;

  /// `GraphLinkRest.wrap(value, "a", "b")`: the value nested under the response path, as the server must send it.
  String wrapCall(GLRestOperation op, String value) =>
      '$restSupportClassName.wrap($value, ${op.responsePathSegments.map((s) => s.quote()).join(', ')})';

  bool isDownload(GLRestOperation op) => op.responseKind == RestResponseKind.binary;

  bool returnsVoid(GLRestOperation op) => op.responseKind == RestResponseKind.none;

  String serviceCallOf(GLRestOperation op, String serviceInstanceName, List<String> serviceArgs) =>
      '$serviceInstanceName.${op.field.codeName}(${serviceArgs.join(', ')})';

  String? validationCallOf(GLRestOperation op, String serviceInstanceName, List<String> serviceArgs) {
    if (!op.field.hasDirective(glValidate)) return null;
    return '$serviceInstanceName.${GLService.getValidationMethodName(op.field.name.token)}(${serviceArgs.join(', ')})';
  }

  void _addDependencies(GLType type, GLToken context) {
    final token = type.firstType.token;
    final dependency = grammar.inputs[token] ?? grammar.types[token] ?? grammar.enums[token] ?? grammar.interfaces[token];
    if (dependency != null) context.addImportDependecy(dependency);
  }

  void addReturnDependencies(GLRestOperation op, GLToken context) => _addDependencies(op.field.type, context);

  void addCollectionImports(GLToken context) {
    context.addImport(JavaImports.map);
    context.addImport(JavaImports.list);
  }
}
