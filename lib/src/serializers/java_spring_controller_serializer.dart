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
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/java_imports.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/jvm_spring_controller_serializer_base.dart';
import 'package:graphlink/src/utils.dart';

class _ArgumentConversions {
  final List<String> declarations;
  final List<String> serviceArgs;

  _ArgumentConversions(this.declarations, this.serviceArgs);
}

class JavaSpringControllerSerializer extends JvmSpringControllerSerializerBase {
  final JavaSerializer serializer;
  @override
  final JavaCodeGenUtils codeGenUtils = JavaCodeGenUtils();

  JavaSpringControllerSerializer({
    required super.grammar,
    required this.serializer,
    required super.reactive,
    required super.injectDataFetching,
    required super.useSpringSecurity,
    required super.generateSchema,
  });

  @override
  void annotateControllers() {
    super.annotateControllers();
    _wrapSubscriptionReturnTypes();
    _wrapControllerHandlerReturnTypes();
    _mappifyControllers();
  }

  /// Wraps every controller field's return type in the wrapper its Spring
  /// handler method actually returns — `Flux<T>` for subscriptions, `Mono<T>`
  /// for everything else in reactive mode, `CompletableFuture<T>` otherwise —
  /// so [JavaSerializer.serializeType] emits it directly. Schema/batch mapping
  /// methods are never subscriptions, so they only ever get Mono/CompletableFuture.
  void _wrapControllerHandlerReturnTypes() {
    for (var ctrl in grammar.controllers.values) {
      for (var field in ctrl.fields) {
        if (ctrl.isSubscription(field)) {
          field.type.wrapper = 'Flux';
          field.type.wrapperImport = JavaImports.flux;
        } else {
          _wrapAsyncReturnType(field);
        }
      }
      for (var mapping in ctrl.mappings) {
        _wrapAsyncReturnType(mapping.field);
      }
    }
  }

  void _wrapAsyncReturnType(GLField field) {
    if (reactive) {
      field.type.wrapper = 'Mono';
      field.type.wrapperImport = JavaImports.mono;
    } else {
      field.type.wrapper = 'CompletableFuture';
      field.type.wrapperImport = JavaImports.completableFuture;
    }
  }

  /// Spring GraphQL subscription handlers must return a reactive
  /// `Publisher`/`Flux<T>`, regardless of the reactive/blocking mode used for
  /// queries and mutations. Marks every subscription field's return type in
  /// the service layer with that wrapper so [JavaSerializer.serializeType]
  /// emits `Flux<T>` for it. Controller subscription fields are handled by
  /// [_wrapControllerHandlerReturnTypes].
  void _wrapSubscriptionReturnTypes() {
    for (var service in grammar.services.values) {
      for (var field in service.fields) {
        if (service.isSubscription(field)) {
          field.type.wrapper = 'Flux';
          field.type.wrapperImport = JavaImports.flux;
        }
      }
    }
  }

  /// Applies GLController's JVM wire-encoding mappification (enum -> String,
  /// projectable type -> Map<String, Object>, same for arguments) to every
  /// controller field and schema/batch-mapping method, then adds the
  /// java.util.List/Map imports the resulting types need.
  void _mappifyControllers() {
    for (var ctrl in grammar.controllers.values) {
      for (var field in [...ctrl.fields]) {
        if (field.type.isList) ctrl.addImport(JavaImports.list);
        final mapped = ctrl.mappifyForJvmController(field);
        ctrl.replaceField(mapped);
        _addImportsIfNeeded(ctrl, mapped);
      }
      for (var mapping in ctrl.mappings) {
        mapping.field = ctrl.mappifyForJvmController(mapping.field);
        _addImportsIfNeeded(ctrl, mapping.field);
      }
    }
  }

  void _addImportsIfNeeded(GLController ctrl, GLField field) {
    final needsMap = field.type is GLMapType || field.arguments.any((a) => a.type is GLMapType);
    if (needsMap) ctrl.addImport(JavaImports.map);
  }

  /// Converts [expr] — a Java expression evaluating to the real domain value
  /// the service layer returned for [field] — into the shape the mappified
  /// controller signature promises: `.toJson()` for enum/projectable types,
  /// recursing through list nesting. Returns [expr] unchanged when [field]'s
  /// type was left untouched by [_getMappifiedField] (plain scalars).
  String _serviceResultToJson(GLField field, String expr, GLToken context) {
    final originalType = field.originalType;
    if (originalType == null) return expr;
    return serializer.callToJson(field, originalType, expr, 0, context);
  }

  /// Wraps a Mono/Flux-returning [reactiveExpr] with `.map(v -> ...)` to apply
  /// [_serviceResultToJson]'s conversion to its emitted value(s). Returns
  /// [reactiveExpr] unchanged when no conversion is needed.
  String _mapReactiveResult(GLField field, String reactiveExpr, GLToken context) {
    final converted = _serviceResultToJson(field, "v", context);
    if (converted == "v") return reactiveExpr;
    return "$reactiveExpr.map(v -> $converted)";
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

    var decorators = serializer.serializeDecorators(ctrl.getDirectives()).trim();

    var buffer = StringBuffer();
    buffer.writeln(decorators);
    buffer.writeln(codeGenUtils.createClass(className: controllerName, statements: [
      if (grammar.services.containsKey(ctrl.serviceName)) 'private final ${ctrl.serviceName} $serviceInstanceName;',
      '',
      serializer.generateContructor(
          controllerName,
          [
            if (grammar.services.containsKey(ctrl.serviceName))
              GLField(name: serviceInstanceName.toToken(), type: GLType(ctrl.serviceName.toToken(), false), arguments: [], directives: [])
          ],
          "public",
          ctrl),
      '',
      ...ctrl.fields
          .map((field) => serializehandlerMethod(ctrl.getTypeByFieldName(field.name.token)!, field, serviceInstanceName, ctrl, qualifier: "public")),
      '',
      ...ctrl.mappings.map((m) => serializeMappingMethod(m, serviceInstanceName, ctrl))
    ]));

    return buffer.toString();
  }

  /// Builds the local `fromJson` declarations for arguments that were
  /// mappified to `Map<String, Object>` (see `_convertArgumentsToJsonMapForField`),
  /// plus the resolved argument list to pass through to the service call —
  /// original (unmapped) args where available, mappified args otherwise.
  /// Shared between resolver methods and schema/batch-mapping methods.
  _ArgumentConversions _buildArgumentConversions(List<GLArgumentDefinition> arguments, GLToken context) {
    final declarations = <String>[];
    for (final arg in arguments) {
      final origArg = arg.originalArg;
      if (origArg == null) continue;
      final declaration = serializer.serializeType(origArg.type, false);
      final fromJsonCall = _inputFromJsonConversion(origArg.type, arg.codeName, context);
      final importSource = grammar.inputs[origArg.type.token] ?? grammar.types[origArg.type.token];
      if (importSource != null) {
        context.addImportDependecy(importSource);
      }
      declarations.add('${declaration} ${origArg.codeName} = ${fromJsonCall};');
    }
    final serviceArgs = arguments.map((e) => e.originalArg ?? e).map((arg) => arg.codeName).toList();
    return _ArgumentConversions(declarations, serviceArgs);
  }

  @override
  String serializehandlerMethod(GLQueryType type, GLField method, String serviceInstanceName, GLToken context, {String? qualifier}) {
    final decorators = serializer.serializeDecorators(method.getDirectives()).trim();
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators);
    }

    final conversions = _buildArgumentConversions(method.arguments, context);
    final inputConversions = conversions.declarations;
    final serviceCall = '$serviceInstanceName.${method.codeName}(${conversions.serviceArgs.join(", ")})';
    final String returnType;
    final List<String> statements;

    final validationMethodCall = method.getDirectiveByName(glValidate) != null
        ? '$serviceInstanceName.${GLService.getValidationMethodName(method.name.token)}(${conversions.serviceArgs.join(", ")})'
        : null;
    final validationCall = validationMethodCall != null ? '$validationMethodCall;' : null;
    final baseReturnType = serializer.serializeType(method.type, false);
    final returnTypeIsVoid = baseReturnType == "void";
    returnType = baseReturnType;
    if (type == GLQueryType.subscription) {
      // Subscription handlers pass the service's Flux straight through —
      // never wrapped in a CompletableFuture.
      statements = [
        ...inputConversions,
        if (validationCall != null) validationCall,
        'return ${_mapReactiveResult(method, serviceCall, context)};',
      ];
    } else {
      context.addImport(JavaImports.completableFuture);
      statements = [
        ...inputConversions,
        ..._wrapInCompletableFuture([
          if (validationCall != null) validationCall,
          _serviceResultToJson(method, serviceCall, context),
        ], returnTypeIsVoid, context),
      ];
    }

    final fullReturnType = qualifier != null ? "$qualifier $returnType" : returnType;

    buffer.writeln(codeGenUtils.createMethod(
        returnType: fullReturnType,
        methodName: method.codeName,
        arguments: method.arguments.map((e) => serializer.serializeArgument(e)).toList(),
        statements: statements));

    return buffer.toString();
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
    final typeDef = grammar.types[type.token] ?? grammar.interfaces[type.token];
    final typeToken = typeDef?.mappedToType?.token ?? typeDef?.token ?? type.token;

    final call = '${typeToken}.fromJson((Map<String, Object>) $sourceExpr)';
    return JavaCodeGenUtils.nullSafeExpr(sourceExpr, call, type.nullable);
  }

  List<String> _wrapInCompletableFuture(List<String> innerStatements, bool returnVoid, GLToken context) {
    final method = returnVoid ? 'runAsync' : 'supplyAsync';
    final preceding = innerStatements.sublist(0, innerStatements.length - 1);
    final last = innerStatements.last;
    final bodyStatements = [
      ...preceding,
      returnVoid ? "$last;" : "return $last;",
    ];

    if (!useSpringSecurity) {
      final lambdaBody = bodyStatements.length == 1 ? innerStatements.first : codeGenUtils.block(bodyStatements);
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
            '''throw new GraphQLException("Access denied to field '${mapping.type.tokenInfo}.${mapping.field.name}'");'''
          ])}';
    }

    if (mapping.identity) {
      return serializeIdentityMapping(mapping, context);
    }

    final conversions = _buildArgumentConversions(mapping.field.arguments, context);
    final serviceCall = '$serviceInstanceName.${mapping.key}(${conversions.serviceArgs.join(", ")})';

    var statementList = <String>[...conversions.declarations];

    if (mapping.isBatch) {
      if (reactive) {
        final lambdaBody = codeGenUtils.block([
          ..._buildBatchResultConversion(mapping, "resultMap", context),
          'return result;',
        ]);
        statementList.add('return $serviceCall.map(resultMap -> $lambdaBody);');
      } else {
        statementList.addAll(_buildBatchResultConversion(mapping, serviceCall, context));
        statementList.add('result');
        statementList = _wrapInCompletableFuture(statementList, false, context);
      }
    } else if (reactive) {
      statementList.add('return ${_mapReactiveResult(mapping.field, serviceCall, context)};');
    } else {
      statementList.add(_serviceResultToJson(mapping.field, serviceCall, context));
      statementList = _wrapInCompletableFuture(statementList, false, context);
    }

    return '${serializeControllerMethodHeader(mapping, context)} ${codeGenUtils.block(statementList)}';
  }

  /// Returns the codeName of the argument matching [originalBareName] —
  /// looked up by its original (pre-mappification) bare name — after
  /// resolving it back to its original (unmappified) form, e.g. the
  /// reconstructed local variable a `fromJson` declaration binds it to (see
  /// [_buildArgumentConversions]), not the raw `Map<String, Object>` wire
  /// parameter.
  String _resolvedArgumentCodeName(List<GLArgumentDefinition> arguments, String originalBareName) {
    final arg = arguments.firstWhere((arg) => (arg.originalArg ?? arg).bareName == originalBareName);
    return (arg.originalArg ?? arg).codeName;
  }

  @override
  String serializeIdentityMapping(GLSchemaMapping mapping, GLToken context) {
    var buffer = StringBuffer();
    var annotation = getAnnotationForMapping(mapping, context);
    if (annotation.isNotEmpty) {
      buffer.writeln(annotation);
    }
    final type = serializer.serializeType(mapping.field.type, false);
    
    final conversions = _buildArgumentConversions(mapping.field.arguments, context);
    final valueCodeName = _resolvedArgumentCodeName(mapping.field.arguments, 'value');

    final wrapperImport = mapping.field.type.wrapperImport;
    if (wrapperImport != null) context.addImport(wrapperImport);

    final String returnType;
    final List<String> statements;
    if (mapping.isBatch) {
      final baseType = JavaCodeGenUtils.listOf(grammar, type);
      returnType = baseType.toBoxedType;
      final perItem = _serviceResultToJson(mapping.field, "v", context);
      final listExpr = perItem == "v" ? valueCodeName : JavaCodeGenUtils.streamMapCollect(receiver: valueCodeName, param: "v", body: perItem);
      statements = _wrapInCompletableFuture([...conversions.declarations, listExpr], false, context);
    } else {
      returnType = type.toBoxedType;
      statements =
          _wrapInCompletableFuture([...conversions.declarations, _serviceResultToJson(mapping.field, valueCodeName, context)], false, context);
    }

    buffer.writeln(
      codeGenUtils.createMethod(
          returnType: 'public $returnType',
          methodName: mapping.key,
          arguments: [...mapping.field.arguments.map((arg) => serializer.serializeArgument(arg))],
          statements: statements),
    );

    return buffer.toString();
  }

  @override
  String serializeForwardedMapping(GLSchemaMapping mapping, GLToken context) {
    var buffer = StringBuffer();
    buffer.writeln(getAnnotationForMapping(mapping, context));

    final fieldType = serializer.serializeType(mapping.field.type, false);

    final conversions = _buildArgumentConversions(mapping.field.arguments, context);
    final valueCodeName = _resolvedArgumentCodeName(mapping.field.arguments, 'value');
    final getterCall =
        '$valueCodeName.${JavaSerializer.getterCall(mapping.field, isRecord: serializer.typesAsRecords, isBoolean: fieldType == 'boolean')}';

    final wrapperImport = mapping.field.type.wrapperImport;
    if (wrapperImport != null) context.addImport(wrapperImport);

    final resultExpr = _serviceResultToJson(mapping.field, getterCall, context);
    final statements = mapping.field.type.wrapper == 'Mono'
        ? [...conversions.declarations, 'return Mono.just($resultExpr);']
        : _wrapInCompletableFuture([...conversions.declarations, resultExpr], false, context);

    buffer.writeln(codeGenUtils.createMethod(
      returnType: 'public $fieldType',
      methodName: mapping.key,
      arguments: mapping.field.arguments.map((arg) => serializer.serializeArgument(arg)).toList(),
      statements: statements,
    ));

    return buffer.toString();
  }
 
  List<String> _buildBatchResultConversion(GLSchemaMapping mapping, String sourceMapExpr, GLToken context) {
    context.addImport(JavaImports.hashMap);
    context.addImport(JavaImports.map);
    final serviceMapping = mapping.serviceMapping!;
    final mappedToType = serviceMapping.getMappedToType(grammar);
    final fieldTypeToken = grammar.getTokenByKey(serviceMapping.field.type.token);
    context.addImportDependecy(mappedToType);
    if (fieldTypeToken != null && !grammar.scalars.containsKey(fieldTypeToken.token)) {
      context.addImportDependecy(fieldTypeToken);
    }
    final keyType = serializer.serializeType(GLType(mappedToType.tokenInfo, false), false);
    String realValueType = serializer.serializeType(serviceMapping.field.type, false).toBoxedType;
    if (serviceMapping.field.type.isList) {
      realValueType = "? extends $realValueType";
    }
    final mappedType = mapping.field.type;
    final mappedValueType = serializer.serializeType(mappedType is GLMapType ? mappedType.valueType : mappedType, false).toBoxedType;
    final valueConversion = _serviceResultToJson(mapping.field, "entry.getValue()", context);

    final loopBody = codeGenUtils.block(['result.put(entry.getKey(), $valueConversion);']);
    return [
      'Map<$keyType, $mappedValueType> result = new HashMap<>();',
      'for (Map.Entry<$keyType, $realValueType> entry : $sourceMapExpr.entrySet()) $loopBody',
    ];
  }

  String _getMappingArgument(GLSchemaMapping mapping, GLToken context) {
    return mapping.field.arguments
        .map((arg) {
          if (arg.type.isList) {
            context.addImport(JavaImports.list);
          }
          return arg;
        })
        .map((arg) => serializer.serializeArgument(arg))
        .join(", ");
  }

  @override
  String serializeControllerMethodHeader(GLSchemaMapping mapping, GLToken context) {
    var buffer = StringBuffer();
    buffer.writeln(getAnnotationForMapping(mapping, context));
    buffer.write("public ");

    final wrapperImport = mapping.field.type.wrapperImport;
    if (wrapperImport != null) context.addImport(wrapperImport);
    final returnType = serializer.serializeType(mapping.field.type, false);

    buffer.write("${returnType.toBoxedType} ${mapping.key}(${_getMappingArgument(mapping, context)}");
    buffer.write(')');
    return buffer.toString();
  }

  // ── Service declarations ───────────────────────────────────────────────────

  @override
  String serializeMethodDeclaration(GLField method, GLQueryType type, GLToken context) {
    GLType returnType;
    if (method.getDirectiveByName(glValidate)?.generated == true) {
      returnType = GLType('void'.toToken(), false);
    } else {
      returnType = getServiceReturnType(method.type);
    }
    var result =
        "${serializer.serializeType(createListTypeOnSubscription(returnType, type), false)} ${method.codeName}(${serializeArgs(method.arguments, context)}";

    return "${result})";
  }

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
