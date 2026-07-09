import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_controller.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_schema_mapping.dart';
import 'package:graphlink/src/model/gl_token.dart';
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
    required super.grammar,
    required this.serializer,
    required super.reactive,
    required super.injectContext,
    required super.useSpringSecurity,
    required super.generateSchema,
  });

  @override
  GLType get jsonMapValueType => GLType('Object'.toToken(), false);

  @override
  void wrapReturnTypes() {
    _wrapSubscriptionReturnTypes();
    if (reactive) {
      _wrapReactiveReturnTypes();
    } else {
      _wrapControllerHandlerReturnTypes();
    }
  }

  void _wrapControllerHandlerReturnTypes() {
    for (var ctrl in grammar.controllers.values) {
      for (var field in ctrl.fields) {
        if (ctrl.isSubscription(field)) {
          field.type.wrapper = 'Flux';
          field.type.wrapperImport = JavaImports.flux;
        } else {
          _wrapCompletableFutureReturnType(field);
        }
      }
      for (var mapping in ctrl.mappings) {
        _wrapCompletableFutureReturnType(mapping.field);
      }
    }
  }

  void _wrapReactiveReturnTypes() {
    for (var service in [...grammar.services.values, ...grammar.controllers.values]) {
      for (var field in [...service.fields]) {
        final wrapped = _reactiveWrappedField(field, isSubscription: service.isSubscription(field));
        if (!identical(wrapped, field)) {
          service.replaceField(wrapped);
        }
      }
      if (service is GLController) {
        for (var mapping in service.mappings) {
          mapping.field = _reactiveWrappedField(mapping.field, isSubscription: false);
        }
      }
    }
  }

  GLField _reactiveWrappedField(GLField field, {required bool isSubscription}) {
    if (isSubscription) {
      final elementType = field.type;
      elementType.wrapper = 'Flux';
      elementType.wrapperImport = JavaImports.flux;
      return field.ofType(elementType);
    } else if (field.type.isList) {
      final elementType = field.type.inlineType;
      elementType.wrapper = 'Flux';
      elementType.wrapperImport = JavaImports.flux;
      return field.type.isList ? field.ofType(elementType) : field;
    }
    field.type.wrapper = 'Mono';
    field.type.wrapperImport = JavaImports.mono;
    return field;
  }

  void _wrapCompletableFutureReturnType(GLField field) {
    field.type.wrapper = 'CompletableFuture';
    field.type.wrapperImport = JavaImports.completableFuture;
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

  /// Wraps a Mono/Flux-returning [reactiveExpr] with `.map(__gl_result__ -> ...)`
  /// to apply [_serviceResultToJson]'s conversion to its emitted value(s).
  /// Returns [reactiveExpr] unchanged when no conversion is needed. The
  /// lambda parameter is namespaced via [safeLocalVar] so it can't shadow a
  /// real service/domain identifier also named "result".
  String _mapReactiveResult(GLField field, String reactiveExpr, GLToken context) {
    final resultVar = codeGenUtils.safeLocalVar('result');
    final converted = _serviceResultToJson(field, resultVar, context);
    if (converted == resultVar) return reactiveExpr;
    return "$reactiveExpr.map($resultVar -> $converted)";
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
      ...ctrl.fields.map((field) => serializeHandlerMethod(ctrl.getTypeByFieldName(field.name.token)!, field, serviceInstanceName, ctrl)),
      '',
      ...ctrl.mappings.map((m) => serializeMappingMethod(m, serviceInstanceName, ctrl)).map((e) => "${e}\n")
    ]));

    return buffer.toString();
  }

  /// Builds the local `fromJson` declarations for arguments that were
  /// mappified to `Map<String, Object>` (see `_convertArgumentsToJsonMapForField`),
  /// plus the resolved argument list to pass through to the service call —
  /// original (unmapped) args where available, mappified args otherwise.
  /// Shared between resolver methods and schema/batch-mapping methods.
  ArgumentConversions _buildArgumentConversions(List<GLArgumentDefinition> arguments, GLToken context) {
    final declarations = <String>[];
    for (final arg in arguments) {
      final origArg = arg.originalArg;
      if (origArg == null) continue;
      final declaration = serializer.serializeType(origArg.type);
      final fromJsonCall = _inputFromJsonConversion(origArg.type, arg.codeName, context);
      final importSource = grammar.inputs[origArg.type.token] ?? grammar.types[origArg.type.token];
      if (importSource != null) {
        context.addImportDependecy(importSource);
      }
      declarations.add('${declaration} ${origArg.codeName} = ${fromJsonCall};');
    }
    final serviceArgs = arguments.map((e) => e.originalArg ?? e).map((arg) => arg.codeName).toList();
    return ArgumentConversions(declarations, serviceArgs);
  }

  @override
  String serializeHandlerMethod(GLQueryType type, GLField method, String serviceInstanceName, GLToken context) {
    final conversions = _buildArgumentConversions(method.arguments, context);
    final inputConversions = conversions.declarations;
    final serviceCall = '$serviceInstanceName.${method.codeName}(${conversions.serviceArgs.join(", ")})';
    final List<String> statements;

    final validationCall = getValidationCallStatement(method, serviceInstanceName, conversions.serviceArgs);
    final returnTypeIsVoid = serializer.serializeType(method.type) == "void";

    if (reactive) {
      // The generated validation method always returns Mono<Void> (or
      // Flux<Void> for a subscription) — its emitted value is irrelevant, we
      // only need to run it before the real call. `.then()`/`.thenMany()`
      // sequence on it without touching the value, chaining straight into the
      // mapped result instead of firing the validation as a disconnected
      // statement (which would never actually subscribe to it).
      final mapped = _mapReactiveResult(method, serviceCall, context);
      final validationMethodCall = getValidationMethodCall(method, serviceInstanceName, conversions.serviceArgs);
      String result;
      if (validationMethodCall != null) {
        final isSubscriptionFlow = method.type.wrapper == 'Flux';
        final deferType = isSubscriptionFlow ? 'Flux' : 'Mono';
        final chainMethod = isSubscriptionFlow ? 'thenMany' : 'then';
        // $mapped itself calls the service (building carService.getCar(id)'s
        // Mono/Flux eagerly, as any Java expression argument must) — wrapping
        // it in defer() postpones that call until subscription time, so it
        // only actually happens once validation's Mono/Flux has completed,
        // even if the service method isn't written lazily.
        result = '$validationMethodCall.$chainMethod($deferType.defer(() -> $mapped))';
      } else {
        result = mapped;
      }
      statements = [
        ...inputConversions,
        'return $result;',
      ];
    } else if (type == GLQueryType.subscription) {
      statements = [
        ...inputConversions,
        if (validationCall != null) validationCall,
        'return ${_mapReactiveResult(method, serviceCall, context)};',
      ];
    } else {
      statements = [
        ...inputConversions,
        ..._wrapInCompletableFuture([
          if (validationCall != null) validationCall,
          _serviceResultToJson(method, serviceCall, context),
        ], returnTypeIsVoid, context),
      ];
    }

    final header = serializer.serializeMethod(method, modifier: "public");
    var buffer = StringBuffer();
    buffer.writeln('$header ${codeGenUtils.block(statements)}');
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
    if (mapping.forbid) {
      if (generateSchema) {
        return "";
      }
      context.addImport(SpringImports.gqlGraphQLException);
      return '${serializer.serializeMethod(mapping.field, modifier: "public")} ${codeGenUtils.block([
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

    return '${serializer.serializeMethod(mapping.field)} ${codeGenUtils.block(statementList)}';
  }

  @override
  String serializeIdentityMapping(GLSchemaMapping mapping, GLToken context) {
    var buffer = StringBuffer();
    buffer.write(serializer.serializeMethod(mapping.field, modifier: "public"));
    buffer.write(" ");
    final List<String> statements;
    if (reactive) {
      statements = ["return Mono.just(${mapping.field.arguments.first.bareName});"];
    } else {
      statements = _wrapInCompletableFuture(['${mapping.field.arguments.first.bareName}'], false, context);
    }
    buffer.write(codeGenUtils.block(statements));
    return buffer.toString();
  }

  @override
  String serializeForwardedMapping(GLSchemaMapping mapping, GLToken context) {
    final fieldType = serializer.serializeType(mapping.field.type);
    final conversions = _buildArgumentConversions(mapping.field.arguments, context);
    final valueCodeName = resolvedArgumentCodeName(mapping.field.arguments, 'value');
    final getterCall =
        '$valueCodeName.${JavaSerializer.getterCall(mapping.field, isRecord: serializer.typesAsRecords, isBoolean: fieldType == 'boolean')}';

    final resultExpr = _serviceResultToJson(mapping.field, getterCall, context);
    final statements = mapping.field.type.wrapper == 'Mono'
        ? [...conversions.declarations, 'return Mono.just($resultExpr);']
        : _wrapInCompletableFuture([...conversions.declarations, resultExpr], false, context);

    final header = serializer.serializeMethod(mapping.field, modifier: "public");
    var buffer = StringBuffer();
    buffer.writeln('$header ${codeGenUtils.block(statements)}');
    return buffer.toString();
  }

  /// Emits the statements that turn a batch service call's
  /// `Map<DomainParent, Value>` into the `Map<Map<String,Object>, Value>` that
  /// Spring's `@BatchMapping` needs — one entry per source parent, keyed by the
  /// exact wire instances Spring passed in (`valueAsMap`), not by the
  /// reconstructed domain objects (which never equal the sources → all-null).
  /// [serviceCallExpr] is the (single) call that yields the domain-keyed map.
  List<String> _buildBatchResultConversion(GLSchemaMapping mapping, String serviceCallExpr, GLToken context) {
    context.addImport(JavaImports.hashMap);
    final serviceMapping = mapping.serviceMapping!;
    final mappedToType = serviceMapping.getMappedToType(grammar);
    final fieldTypeToken = grammar.getTokenByKey(serviceMapping.field.type.token);
    if (fieldTypeToken != null && !grammar.scalars.containsKey(fieldTypeToken.token)) {
      context.addImportDependecy(fieldTypeToken);
    }
    final domainKeyType = serializer.serializeType(GLType(mappedToType.tokenInfo, false));
    String realValueType = serializer.serializeType(serviceMapping.field.type).toBoxedType;
    if (serviceMapping.field.type.isList) {
      realValueType = "? extends $realValueType";
    }
    final mappedType = mapping.field.type as GLMapType;
    final sourceKeyType = serializer.serializeType(mappedType.keyType);
    final mappedValueType = serializer.serializeType(mappedType.valueType).toBoxedType;

    final sourceArg = mapping.field.arguments.firstWhere((a) => (a.originalArg ?? a).bareName == 'value');
    final sourceListName = sourceArg.codeName;
    final domainListName = (sourceArg.originalArg ?? sourceArg).codeName;

    final serviceResultVar = codeGenUtils.safeLocalVar('serviceResult');
    final indexVar = codeGenUtils.safeLocalVar('i');
    final valueExpr = '$serviceResultVar.get($domainListName.get($indexVar))';
    final valueConversion = _serviceResultToJson(mapping.field, valueExpr, context);

    final loopBody = codeGenUtils.block(['result.put($sourceListName.get($indexVar), $valueConversion);']);
    return [
      'Map<$domainKeyType, $realValueType> $serviceResultVar = $serviceCallExpr;',
      'Map<$sourceKeyType, $mappedValueType> result = new HashMap<>();',
      'for (int $indexVar = 0; $indexVar < $sourceListName.size(); $indexVar++) $loopBody',
    ];
  }

  // ── Arg type resolution ────────────────────────────────────────────────────

  String serializeArg(GLArgumentDefinition arg) {
    return serializer.serializeArgument(arg);
  }

  String serializeArgs(Iterable<GLArgumentDefinition> args) {
    return args.map(serializeArg).join(", ");
  }
}
