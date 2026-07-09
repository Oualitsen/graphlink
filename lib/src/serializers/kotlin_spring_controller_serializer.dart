import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/kotlin_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_controller.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_schema_mapping.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_extension.dart';
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
    required super.injectContext,
    required super.generateSchema,
    this.blockingServices = true,
  }) : super(
          reactive: false,
          useSpringSecurity: false,
        );

  static const _securityContext = 'Dispatchers.IO + SecurityCoroutineContext()';

  @override
  GLType get jsonMapValueType => GLType('Any'.toToken(), true);

  @override
  void wrapReturnTypes() {
    _wrapSubscriptionReturnTypes();
  }

  /// Spring GraphQL subscription handlers must return a reactive stream — in
  /// Kotlin that is a `Flow<T>` (never a `suspend` value). Marks every
  /// subscription field's return type, on both the service interface and the
  /// controller, so [KotlinSerializer.serializeType] emits `Flow<T>`.
  void _wrapSubscriptionReturnTypes() {
    for (var service in [...grammar.services.values, ...grammar.controllers.values]) {
      for (var field in service.fields) {
        if (service.isSubscription(field)) {
          field.type.wrapper = 'Flow';
          field.type.wrapperImport = KotlinImports.flow;
        }
      }
    }
  }

  // ── Controller ─────────────────────────────────────────────────────────────

  @override
  String serializeController(GLController ctrl) {
    final body = _serializeControllerBody(ctrl);
    return serializer.serializeWithImport(ctrl, body);
  }

  String _serializeControllerBody(GLController ctrl) {
    final controllerName = ctrl.token;
    final serviceInstanceName = ctrl.serviceName.firstLow;
    final decorators = serializer.serializeDecorators(ctrl.getDirectives()).trim();
    final hasService = grammar.services.containsKey(ctrl.serviceName);

    final params = [
      if (hasService) 'private val $serviceInstanceName: ${ctrl.serviceName}',
    ];

    final members = <String>[];
    for (final field in ctrl.fields) {
      members.add(serializeHandlerMethod(
          ctrl.getTypeByFieldName(field.name.token)!, field, serviceInstanceName, ctrl));
      members.add('');
    }
    for (final mapping in ctrl.mappings) {
      members.add(serializeMappingMethod(mapping, serviceInstanceName, ctrl));
      members.add('');
    }

    final classStr = codeGenUtils.kotlinClass(
        name: controllerName, params: params.isEmpty ? null : params, body: members);
    return decorators.isEmpty ? classStr : '$decorators\n$classStr';
  }

  // ── Handler methods ──────────────────────────────────────────────────────────

  @override
  String serializeHandlerMethod(GLQueryType type, GLField method, String serviceInstanceName, GLToken context) {
    final conversions = _buildArgumentConversions(method.arguments, context);
    final serviceCall = '$serviceInstanceName.${method.codeName}(${conversions.serviceArgs.join(", ")})';
    final validationCall = getValidationCallStatement(method, serviceInstanceName, conversions.serviceArgs);

    final List<String> statements;
    if (type == GLQueryType.subscription) {
      // Subscriptions return `Flow<T>` directly — no `suspend`, no
      // `withContext`; the domain→wire conversion is applied per element.
      statements = [
        ...conversions.declarations,
        if (validationCall != null) validationCall,
        'return ${_mapFlowResult(method, serviceCall, context)}',
      ];
    } else {
      statements = [
        ...conversions.declarations,
        ..._blockingReturn(method, serviceCall, validationCall, context),
      ];
    }

    final header = _methodHeader(method, suspend: type != GLQueryType.subscription);
    return '$header ${codeGenUtils.block(statements)}';
  }

  /// Builds the terminal `return` statement(s) for a non-subscription handler
  /// or mapping. When [blockingServices] is set, the service call (and any
  /// validation) runs inside `withContext(Dispatchers.IO + …)` so blocking
  /// JDBC/JPA work is offloaded off the coroutine's thread; the last
  /// expression in the block is the value `withContext` (and the method)
  /// returns.
  List<String> _blockingReturn(GLField field, String serviceCall, String? validationCall, GLToken context) {
    final resultExpr = _serviceResultToJson(field, serviceCall);
    if (!blockingServices) {
      return [
        if (validationCall != null) validationCall,
        'return $resultExpr',
      ];
    }
    _addWithContextImports(context);
    final lambda = codeGenUtils.block([
      if (validationCall != null) validationCall,
      resultExpr,
    ]);
    return ['return withContext($_securityContext) $lambda'];
  }

  // ── Mapping methods ──────────────────────────────────────────────────────────

  @override
  String serializeMappingMethod(GLSchemaMapping mapping, String serviceInstanceName, GLToken context) {
    if (mapping.forwarded) {
      return serializeForwardedMapping(mapping, context);
    }
    if (mapping.forbid) {
      if (generateSchema) {
        return '';
      }
      context.addImport(SpringImports.gqlGraphQLException);
      final header = _methodHeader(mapping.field, suspend: true);
      return '$header ${codeGenUtils.block([
            '''throw GraphQLException("Access denied to field '${mapping.type.tokenInfo}.${mapping.field.name}'")'''
          ])}';
    }
    if (mapping.identity) {
      return serializeIdentityMapping(mapping, context);
    }

    final conversions = _buildArgumentConversions(mapping.field.arguments, context);
    final serviceCall = '$serviceInstanceName.${mapping.key}(${conversions.serviceArgs.join(", ")})';

    final List<String> statements;
    if (mapping.isBatch) {
      statements = [
        ...conversions.declarations,
        ..._buildBatchReturn(mapping, serviceCall, context),
      ];
    } else {
      statements = [
        ...conversions.declarations,
        ..._blockingReturn(mapping.field, serviceCall, null, context),
      ];
    }

    final header = _methodHeader(mapping.field, suspend: true);
    return '$header ${codeGenUtils.block(statements)}';
  }

  @override
  String serializeIdentityMapping(GLSchemaMapping mapping, GLToken context) {
    // The key/parent already is the resolved value — echo it straight back.
    final valueName = mapping.field.arguments.first.codeName;
    final header = _methodHeader(mapping.field, suspend: true);
    return '$header ${codeGenUtils.block(['return $valueName'])}';
  }

  @override
  String serializeForwardedMapping(GLSchemaMapping mapping, GLToken context) {
    final conversions = _buildArgumentConversions(mapping.field.arguments, context);
    final valueCodeName = resolvedArgumentCodeName(mapping.field.arguments, 'value');
    // The parent is reconstructed as a data class; read the field as a property.
    final propertyAccess = '$valueCodeName.${mapping.field.codeName}';
    final resultExpr = _serviceResultToJson(mapping.field, propertyAccess);

    final statements = [
      ...conversions.declarations,
      'return $resultExpr',
    ];
    final header = _methodHeader(mapping.field, suspend: true);
    return '$header ${codeGenUtils.block(statements)}';
  }

  /// Turns a batch service call's `Map<DomainParent, DomainValue>` into the
  /// `Map<WireParent, WireValue>` Spring's `@BatchMapping` needs — one entry
  /// per source parent, keyed by the exact wire instances Spring passed in
  /// (`value`), not by the reconstructed domain objects (which never equal the
  /// sources → all-null).
  List<String> _buildBatchReturn(GLSchemaMapping mapping, String serviceCall, GLToken context) {
    final serviceMapping = mapping.serviceMapping!;
    final mappedToType = serviceMapping.getMappedToType(grammar);
    final fieldTypeToken = grammar.getTokenByKey(serviceMapping.field.type.token);
    if (fieldTypeToken != null && !grammar.scalars.containsKey(fieldTypeToken.token)) {
      context.addImportDependecy(fieldTypeToken);
    }

    final domainKeyType = serializer.serializeType(GLType(mappedToType.tokenInfo, false));
    final domainValueType = serializer.serializeType(serviceMapping.field.type);
    final mappedType = mapping.field.type as GLMapType;
    final wireKeyType = serializer.serializeType(mappedType.keyType);
    final wireValueType = serializer.serializeType(mappedType.valueType);

    final sourceArg = mapping.field.arguments.firstWhere((a) => (a.originalArg ?? a).bareName == 'value');
    final sourceListName = sourceArg.codeName;
    final domainListName = (sourceArg.originalArg ?? sourceArg).codeName;

    final serviceResultVar = codeGenUtils.safeLocalVar('serviceResult');
    final indexVar = codeGenUtils.safeLocalVar('i');

    // Kotlin `Map.get` is always nullable; force non-null when the schema
    // value is non-null before converting/inserting into the non-null result.
    final rawAccess = '$serviceResultVar[$domainListName[$indexVar]]';
    final valueAccess = mappedType.valueType.nullable ? rawAccess : '$rawAccess!!';
    final valueConversion = _serviceResultToJson(mapping.field, valueAccess);

    final loopBody = codeGenUtils.block(['result[$sourceListName[$indexVar]] = $valueConversion']);
    final conversion = [
      'val $serviceResultVar: Map<$domainKeyType, $domainValueType> = $serviceCall',
      'val result = mutableMapOf<$wireKeyType, $wireValueType>()',
      'for ($indexVar in $sourceListName.indices) $loopBody',
    ];

    if (!blockingServices) {
      return [...conversion, 'return result'];
    }
    _addWithContextImports(context);
    final lambda = codeGenUtils.block([...conversion, 'result']);
    return ['return withContext($_securityContext) $lambda'];
  }

  // ── Shared helpers ────────────────────────────────────────────────────────────

  /// Builds the local `fromJson` declarations for arguments mappified to the
  /// wire map type, plus the resolved argument list to pass to the service
  /// call — original (unmapped) args where available, mappified args otherwise.
  ArgumentConversions _buildArgumentConversions(List<GLArgumentDefinition> arguments, GLToken context) {
    final declarations = <String>[];
    for (final arg in arguments) {
      final origArg = arg.originalArg;
      if (origArg == null) continue;
      final declaredType = serializer.serializeType(origArg.type);
      final fromJsonCall = _inputFromJsonConversion(origArg.type, arg.codeName);
      final importSource =
          grammar.inputs[origArg.type.firstType.token] ?? grammar.types[origArg.type.firstType.token];
      if (importSource != null) {
        context.addImportDependecy(importSource);
      }
      declarations.add('val ${origArg.codeName}: $declaredType = $fromJsonCall');
    }
    final serviceArgs = arguments.map((e) => e.originalArg ?? e).map((arg) => arg.codeName).toList();
    return ArgumentConversions(declarations, serviceArgs);
  }

  /// Reconstructs an input/type argument from its wire map form, recursing
  /// through list nesting. Mirrors [KotlinSerializer]'s `fromJson` cast style
  /// (`as`/`as?` + `?.let`/`.map`).
  String _inputFromJsonConversion(GLType type, String sourceExpr, [int depth = 0]) {
    if (type is GLListType) {
      final varName = codeGenUtils.safeLocalVar('m$depth');
      final inner = _inputFromJsonConversion(type.inlineType, varName, depth + 1);
      final casted = type.nullable ? '($sourceExpr as? List<*>)' : '($sourceExpr as List<*>)';
      return KotlinCodeGenUtils.mapCall(receiver: casted, param: varName, body: inner, nullable: type.nullable);
    }
    final typeToken = serializer.resolveCodeName(type.token);
    if (type.nullable) {
      return KotlinCodeGenUtils.letCall(
          receiver: '($sourceExpr as? Map<String, Any?>)', body: '$typeToken.fromJson(it)');
    }
    return '$typeToken.fromJson($sourceExpr as Map<String, Any?>)';
  }

  /// Converts [expr] — an expression evaluating to the real domain value the
  /// service returned for [field] — into the wire shape the mappified
  /// signature promises (`.toJson()` for enum/projectable, recursing lists).
  /// Returns [expr] unchanged when [field]'s type was left untouched by
  /// mappification (plain scalars).
  String _serviceResultToJson(GLField field, String expr) {
    final originalType = field.originalType;
    if (originalType == null) return expr;
    return serializer.callToJson(field, originalType, expr, 0);
  }

  /// Wraps a `Flow`-returning [flowExpr] with `.map { … }` to apply the
  /// domain→wire conversion to each emitted element. Returns [flowExpr]
  /// unchanged when no conversion is needed.
  String _mapFlowResult(GLField field, String flowExpr, GLToken context) {
    final resultVar = codeGenUtils.safeLocalVar('result');
    final converted = _serviceResultToJson(field, resultVar);
    if (converted == resultVar) return flowExpr;
    context.addImport(KotlinImports.flowMap);
    return '$flowExpr.map { $resultVar -> $converted }';
  }

  void _addWithContextImports(GLToken context) {
    context.addImport(KotlinImports.withContext);
    context.addImport(KotlinImports.dispatchers);
    context.addImport('$packageName.security.SecurityCoroutineContext');
  }

  String _methodHeader(GLField field, {required bool suspend}) {
    final decorators = serializer.serializeDecorators(field.getDirectives()).trim();
    final args = field.arguments.map(_serializeArg).join(', ');
    final keyword = suspend ? 'suspend fun' : 'fun';
    final signature = '$keyword ${field.codeName}($args): ${serializer.serializeType(field.type)}';
    return decorators.isEmpty ? signature : '$decorators\n$signature';
  }

  String _serializeArg(GLArgumentDefinition arg) {
    final decorators = serializer.serializeDecorators(arg.getDirectives(), joiner: ' ').trim();
    final base = '${arg.codeName}: ${serializer.serializeType(arg.type)}';
    return decorators.isEmpty ? base : '$decorators $base';
  }
}
