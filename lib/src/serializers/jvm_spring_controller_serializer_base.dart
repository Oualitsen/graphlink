import 'package:graphlink/src/code_gen_utils.dart';
import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_controller.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_schema_mapping.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/token_info.dart';
import 'package:graphlink/src/serializers/java_imports.dart';

/// The reconstructed `fromJson` local declarations for arguments that were
/// mappified to the wire map type, plus the resolved argument list to pass
/// through to the service call. Built per-language (the declaration syntax
/// differs) but the shape is identical across JVM targets.
class ArgumentConversions {
  final List<String> declarations;
  final List<String> serviceArgs;

  ArgumentConversions(this.declarations, this.serviceArgs);
}

abstract class JvmSpringControllerSerializerBase {
  final GLParser grammar;
  final bool reactive;
  final bool injectContext;
  final bool useSpringSecurity;
  final bool generateSchema;

  CodeGenUtilsBase get codeGenUtils;

  JvmSpringControllerSerializerBase({
    required this.grammar,
    required this.reactive,
    required this.injectContext,
    required this.useSpringSecurity,
    required this.generateSchema,
  });

  // ── Spring annotation factories ────────────────────────────────────────────
  // Identical for Java Spring and Kotlin Spring

  /// Template for the full controller-preparation pass. Shared across JVM
  /// targets: annotate with the Spring mapping directives, let the subclass
  /// apply its language-specific return-type wrapping (CompletableFuture/Mono/
  /// Flux for Java, `suspend`/`Flow` for Kotlin), then retype upload arguments
  /// and mappify controller wire types — both identical across targets.
  void annotateControllers() {
    _annotateControllerDirectives();
    wrapReturnTypes();
    wrapUploadArguments();
    mappifyControllers();
  }

  /// Language-specific return-type wrapping hook (see [annotateControllers]).
  void wrapReturnTypes();

  void _annotateControllerDirectives() {
    for (var ctrl in grammar.controllers.values) {
      ctrl.addDirective(_createControllerDirective());
      for (var method in ctrl.fields) {
        var queryType = ctrl.getTypeByFieldName(method.name.token)!;
        method.addDirective(_createResolverDirective(queryType, method, ctrl));
        for (var arg in method.arguments) {
          arg.addDirective(_createArgumentDirective(arg));
        }
      }
      for (var mapping in ctrl.mappings) {
        // The "value" argument is the parent-type source instance Spring binds
        // by type, not a GraphQL field argument, so it never gets `@Argument`.
        for (var arg in mapping.field.arguments) {
          if (arg.skipOnGraphqlSerialization) continue;
          arg.addDirective(_createArgumentDirective(arg));
        }
      }
    }
    injectDataFetchingIntoArgs();
    _annotateMappingMethods();
  }

  /// Annotates every controller schema/batch-mapping method with
  /// `@SchemaMapping` or `@BatchMapping`. Forwarded, forbidden and identity
  /// mappings are always `@SchemaMapping` regardless of [GLSchemaMapping.batch]
  /// — only a "real" mapping method (one that actually delegates to a batch
  /// service call) can be `@BatchMapping`.
  void _annotateMappingMethods() {
    for (var ctrl in grammar.controllers.values) {
      for (var mapping in ctrl.mappings) {
        final isSchemaMapping = mapping.forwarded || mapping.forbid || mapping.identity || !mapping.isBatch;
        mapping.field.addDirective(isSchemaMapping ? _createSchemaMappingDirective(mapping) : _createBatchMappingDirective(mapping));
      }
    }
  }

  void injectDataFetchingIntoArgs() {
    for (var ctrl in [...grammar.controllers.values, ...grammar.services.values]) {
      for (var field in ctrl.fields) {
        _interDataFetchingEnv(ctrl, field);
      }

      for (var mapping in ctrl.mappings) {
        _interDataFetchingEnv(ctrl, mapping.field);
      }
    }
  }

  void _interDataFetchingEnv(GLService service, GLField field) {
    if (injectContext || field.hasDirective(glInjectContext)) {
      // GraphQLContext is the one non-trivial parameter Spring can bind on both
      // @SchemaMapping and @BatchMapping; DataFetchingEnvironment is illegal on a
      // @BatchMapping (batch loading is detached from any single field), so use
      // GraphQLContext everywhere to keep the injected env consistent.
      field.addArgument(GLArgumentDefinition('graphQLContext'.toToken(), GLType('GraphQLContext'.toToken(), false), []));
      service.addImport(SpringImports.gqlGraphQLContext);
    }
  }

  GLDirectiveValue _createResolverDirective(GLQueryType type, GLField method, GLService ctrl) {
    // The keyword pass (which assigns codeName) runs after this annotation step,
    // so predict the sanitized method name with the same deterministic rule.
    // When the bare top-level mapping (`@QueryMapping`) would otherwise bind to
    // the renamed method, pin it to the original wire name (`name = "return"`).
    final wire = method.name.token;
    final code = ctrl.resolveCodeName(wire, grammar.reservedWords);
    return GLDirectiveValue(
        "_glMapping".toToken(),
        [],
        [
          GLArgumentValue(glAnnotation.toToken(), true),
          GLArgumentValue(glClass.toToken(), _toMappingAnnotationValue(type)),
          if (code != wire) GLArgumentValue("name".toToken(), wire),
          GLArgumentValue(glImport.toToken(), _toMappingAnnotationImport(type)),
          GLArgumentValue(glOnServer.toToken(), true),
        ],
        generated: true);
  }

  GLDirectiveValue _createControllerDirective() {
    return GLDirectiveValue(
        "_glController".toToken(),
        [],
        [
          GLArgumentValue(glAnnotation.toToken(), true),
          GLArgumentValue(glClass.toToken(), "@Controller"),
          GLArgumentValue(glImport.toToken(), SpringImports.controller),
          GLArgumentValue(glOnServer.toToken(), true),
        ],
        generated: true);
  }

  GLDirectiveValue _createArgumentDirective(GLArgumentDefinition arg) {
    return GLDirectiveValue(
        "_glController".toToken(),
        [],
        [
          GLArgumentValue(glAnnotation.toToken(), true),
          GLArgumentValue(glClass.toToken(), "@Argument"),
          GLArgumentValue("name".toToken(), arg.bareName),
          GLArgumentValue(glImport.toToken(), SpringImports.gqlArgument),
          GLArgumentValue(glOnServer.toToken(), true),
        ],
        generated: true);
  }

  GLDirectiveValue _createSchemaMappingDirective(GLSchemaMapping mapping) {
    return GLDirectiveValue(
        "_glSchemaMapping".toToken(),
        [],
        [
          GLArgumentValue(glAnnotation.toToken(), true),
          GLArgumentValue(glClass.toToken(), "@SchemaMapping"),
          GLArgumentValue(glImport.toToken(), SpringImports.schemaMapping),
          GLArgumentValue("typeName".toToken(), mapping.type.tokenInfo.token.quote()),
          GLArgumentValue("field".toToken(), mapping.field.name.token.quote()),
          GLArgumentValue(glOnServer.toToken(), true),
        ],
        generated: true);
  }

  GLDirectiveValue _createBatchMappingDirective(GLSchemaMapping mapping) {
    return GLDirectiveValue(
        "_glBatchMapping".toToken(),
        [],
        [
          GLArgumentValue(glAnnotation.toToken(), true),
          GLArgumentValue(glClass.toToken(), "@BatchMapping"),
          GLArgumentValue(glImport.toToken(), SpringImports.batchMapping),
          GLArgumentValue("typeName".toToken(), mapping.type.tokenInfo.token.quote()),
          GLArgumentValue("field".toToken(), mapping.field.name.token.quote()),
          GLArgumentValue(glOnServer.toToken(), true),
        ],
        generated: true);
  }

  String getAnnotationForMapping1(GLSchemaMapping mapping, GLToken context) {
    if (mapping.isBatch) {
      context.addImport(SpringImports.batchMapping);
      return '@BatchMapping(typeName="${mapping.type.tokenInfo}", field="${mapping.field.name}")';
    } else {
      context.addImport(SpringImports.schemaMapping);
      return '@SchemaMapping(typeName="${mapping.type.tokenInfo}", field="${mapping.field.name}")';
    }
  }

  String _toMappingAnnotationValue(GLQueryType queryType) {
    switch (queryType) {
      case GLQueryType.query:
        return "@QueryMapping";
      case GLQueryType.mutation:
        return "@MutationMapping";
      case GLQueryType.subscription:
        return "@SubscriptionMapping";
    }
  }

  String _toMappingAnnotationImport(GLQueryType queryType) {
    switch (queryType) {
      case GLQueryType.query:
        return SpringImports.queryMapping;
      case GLQueryType.mutation:
        return SpringImports.mutationMapping;
      case GLQueryType.subscription:
        return SpringImports.subscriptionMapping;
    }
  }

  // ── Schema utilities ───────────────────────────────────────────────────────
  // Language-agnostic — same logic for Java Spring and Kotlin Spring

  GLType createListTypeOnSubscription(GLType type, GLQueryType queryType) {
    if (queryType == GLQueryType.subscription) {
      return GLListType(type, false);
    }
    return type;
  }

  GLType getServiceReturnType(GLType type) {
    var token = type.token;
    if (grammar.isNonProjectableType(token)) {
      return type;
    }
    var returnType = grammar.getType(type.tokenInfo);
    var skipOnServerDir = returnType.getDirectiveByName(glSkipOnServer);
    if (skipOnServerDir != null) {
      var mapTo = getMapTo(type.tokenInfo);
      var rt = GLType(mapTo.toToken(), false);
      if (type.isList) {
        if (mapTo == "Object") {
          rt = GLType("?".toToken(), false);
        }
        return GLListType(rt, false);
      } else {
        return rt;
      }
    }
    return type;
  }

  String getMapTo(TokenInfo typeToken) {
    var type = grammar.getType(typeToken);
    var dir = type.getDirectiveByName(glSkipOnServer);
    if (dir == null) {
      return type.token;
    }
    var mapTo = dir.getArgValueAsString(glMapTo);
    if (mapTo == null) {
      return "Object";
    }
    var mappedTo = grammar.getType(dir.getArgumentByName(glMapTo)!.tokenInfo.ofNewName(mapTo));
    if (mappedTo.getDirectiveByName(glSkipOnServer) != null) {
      throw ParseException("You cannot mapTo ${mappedTo.tokenInfo} because it is annotated with $glSkipOnServer", info: mappedTo.tokenInfo);
    }
    return mappedTo.token;
  }

  // ── Shared wire-encoding passes (JVM, serializer-independent) ──────────────

  /// Applies JVM wire-encoding mappification (enum -> String, projectable type
  /// -> wire map, same for arguments) to every controller field and
  /// schema/batch-mapping method.
  void mappifyControllers() {
    for (var ctrl in grammar.controllers.values) {
      for (var field in [...ctrl.fields]) {
        final mapped = _mappifyForJvmController(field);
        ctrl.replaceField(mapped);
      }
      for (var mapping in ctrl.mappings) {
        mapping.field = _mappifyForJvmController(mapping.field);
      }
    }
  }

  /// The wire type a projectable value's map is valued by — language-specific
  /// (`Object` for Java, `Any?` for Kotlin). A fresh [GLType] per call so it is
  /// never aliased across the [GLMapType]s built from it.
  GLType get jsonMapValueType;

  /// JVM Spring controller wire encoding: retypes [field]'s return type
  /// (enum -> `String`, projectable type -> wire map) and any of its arguments
  /// carrying an input or projectable-type value the same way.
  /// [GLField.originalType] / [GLArgumentDefinition.originalArg] keep pointing
  /// back to the real type/argument so the serializer can still emit the
  /// `toJson`/`fromJson` conversion. Returns [field] unchanged when nothing
  /// needs mappification. Mutates [field]'s arguments in place.
  GLField _mappifyForJvmController(GLField field) {
    final mappedField = _mappifyReturnType(field);
    _mappifyArguments(mappedField);
    return mappedField;
  }

  GLField _mappifyReturnType(GLField field) {
    final fieldType = field.type;
    // A batch mapping's return type is a GLMapType whose key is the parent
    // identity; `firstType` reports the value type, so a scalar-valued batch
    // (e.g. `Map<Message, Boolean>`) would otherwise skip mappification and
    // leave the key un-mappified. Trigger on a projectable key too.
    final batchKeyProjectable = fieldType is GLMapType && grammar.isProjectableType(fieldType.keyType.firstType.token);
    if (grammar.isEnum(fieldType.firstType.token) || grammar.isProjectableType(fieldType.firstType.token) || batchKeyProjectable) {
      final mapped = field.ofType(_mappifyType(fieldType));
      // originalType is only ever consulted to build a *single-value*
      // toJson() conversion (e.g. `entry.getValue()`), so for a batch
      // mapping (fieldType wrapping the value in a GLMapType key/value
      // shape) it must point at the value alone, not the whole map.
      mapped.originalType = fieldType is GLMapType ? fieldType.valueType : fieldType;
      return mapped;
    }
    return field;
  }

  void _mappifyArguments(GLField field) {
    for (var arg in field.arguments) {
      if (grammar.isInput(arg.type.firstType.token) || grammar.types.containsKey(arg.type.firstType.token)) {
        final newArg = GLArgumentDefinition(
            arg.tokenInfo.ofNewName("${arg.token}AsMap"), _mappifyToJsonMapType(arg.type), arg.getDirectives());
        field.addArgument(newArg);
        field.removeArgument(arg.tokenInfo.token);
        newArg.originalArg = arg;
      }
    }
  }

  /// Recurses through [GLListType] nesting, replacing the innermost element
  /// type with `String` (enum) or the wire map (projectable type) — e.g.
  /// `[User!]!` becomes `List<Map<String, …>>`, not a flattened
  /// `Map<String, …>`. Preserves [GLType.wrapper]/[GLType.wrapperImport]
  /// (e.g. the `Flux` wrapper set on a subscription's return type) at every
  /// level so mappification doesn't drop it.
  GLType _mappifyType(GLType type) {
    if (type is GLMapType) {
      // A batch mapping's key is the parent identity, which reaches the
      // controller as its wire form for a projectable parent. Spring's
      // @BatchMapping does map.get(source) against those wire instances, so
      // the key must be mappified just like the value — otherwise the returned
      // map is keyed by reconstructed domain objects that never equal the
      // sources and every field resolves null.
      return GLMapType(_mappifyType(type.keyType), _mappifyType(type.valueType), type.nullable, wrapper: type.wrapper, wrapperImport: type.wrapperImport);
    }
    if (type is GLListType) {
      return GLListType(_mappifyType(type.inlineType), type.nullable, wrapper: type.wrapper, wrapperImport: type.wrapperImport);
    }
    if (grammar.isEnum(type.token)) {
      return type.ofNewName('String'.toToken());
    }
    if (grammar.isProjectableType(type.token)) {
      return _jsonMapType(type.nullable, wrapper: type.wrapper, wrapperImport: type.wrapperImport);
    }
    // Scalar (e.g. a batch mapping's Boolean/Int value) — no wire remapping.
    return type;
  }

  /// Recurses through [GLListType] nesting, unconditionally replacing the
  /// innermost element type with the wire map — used for arguments, where the
  /// caller has already established mappification is needed.
  GLType _mappifyToJsonMapType(GLType type) {
    if (type is GLListType) {
      return GLListType(_mappifyToJsonMapType(type.inlineType), type.nullable, wrapper: type.wrapper, wrapperImport: type.wrapperImport);
    }
    return _jsonMapType(type.nullable, wrapper: type.wrapper, wrapperImport: type.wrapperImport);
  }

  GLMapType _jsonMapType(bool nullable, {String? wrapper, String? wrapperImport}) => GLMapType(
      GLType('String'.toToken(), false), jsonMapValueType, nullable,
      wrapper: wrapper, wrapperImport: wrapperImport);

  /// Retypes every upload-scalar argument on service fields (and schema/batch
  /// mapping methods) to the wire type the controller passes through —
  /// `FilePart` in reactive mode, `MultipartFile` otherwise — so the generated
  /// service interface declares the same parameter type its controller handler
  /// calls it with.
  void wrapUploadArguments() {
    for (var service in [...grammar.services.values, ...grammar.controllers.values]) {
      for (var field in service.fields) {
        _retypeUploadArguments(field);
      }
      for (var mapping in service.mappings) {
        _retypeUploadArguments(mapping.field);
      }
    }
  }

  void _retypeUploadArguments(GLField field) {
    final uploadNames = grammar.uploadScalarNames;
    for (var arg in field.arguments) {
      if (!uploadNames.contains(arg.type.firstType.token)) continue;
      final baseToken = (reactive ? 'FilePart' : 'MultipartFile').toToken();
      final String externalImport = reactive ? SpringImports.filePart : SpringImports.multipartFile;
      final GLType newType = arg.type.ofNewName(baseToken)..externalImport = externalImport;
      field.addArgument(GLArgumentDefinition(arg.tokenInfo, newType, arg.getDirectives(),
          defaultValue: arg.defaultValue, isDeclared: arg.isDeclared));
    }
  }

  // ── Shared validation / argument resolution (serializer-independent) ───────

  String? getValidationMethodCall(GLField method, String serviceInstanceName, List<String> argsCalls) {
    if (method.getDirectiveByName(glValidate) == null) return null;
    return '$serviceInstanceName.${GLService.getValidationMethodName(method.name.token)}(${argsCalls.join(", ")})';
  }

  String? getValidationCallStatement(GLField method, String serviceInstanceName, List<String> argsCalls) {
    final validationMethodCall = getValidationMethodCall(method, serviceInstanceName, argsCalls);
    return validationMethodCall != null ? '$validationMethodCall;' : null;
  }

  /// Returns the codeName of the argument matching [originalBareName] —
  /// looked up by its original (pre-mappification) bare name — resolved back to
  /// its original (unmappified) form, e.g. the reconstructed local variable a
  /// `fromJson` declaration binds it to, not the raw wire map parameter.
  String resolvedArgumentCodeName(List<GLArgumentDefinition> arguments, String originalBareName) {
    final arg = arguments.firstWhere((arg) => (arg.originalArg ?? arg).bareName == originalBareName);
    return (arg.originalArg ?? arg).codeName;
  }

  // ── Abstract ───────────────────────────────────────────────────────────────

  String serializeController(GLController ctrl);
  String serializeHandlerMethod(GLQueryType type, GLField method, String serviceInstanceName, GLToken context);
  String serializeMappingMethod(GLSchemaMapping mapping, String serviceInstanceName, GLToken context);
  String serializeIdentityMapping(GLSchemaMapping mapping, GLToken context);
  String serializeForwardedMapping(GLSchemaMapping mapping, GLToken context);
}
