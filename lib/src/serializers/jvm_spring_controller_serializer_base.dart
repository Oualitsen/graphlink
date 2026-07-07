import 'package:graphlink/src/code_gen_utils.dart';
import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/extensions.dart';
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

abstract class JvmSpringControllerSerializerBase {
  final GLParser grammar;
  final bool reactive;
  final bool injectDataFetching;
  final bool useSpringSecurity;
  final bool generateSchema;

  CodeGenUtilsBase get codeGenUtils;

  JvmSpringControllerSerializerBase({
    required this.grammar,
    required this.reactive,
    required this.injectDataFetching,
    required this.useSpringSecurity,
    required this.generateSchema,
  });

  // ── Spring annotation factories ────────────────────────────────────────────
  // Identical for Java Spring and Kotlin Spring

  void annotateControllers() {
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
    if (injectDataFetching || field.hasDirective(glReturnsProjection)) {
      field.addArgument(GLArgumentDefinition('dataFetchingEnvironment'.toToken(), GLType('DataFetchingEnvironment'.toToken(), false), []));
      service.addImport(SpringImports.gqlDataFetchingEnvironment);
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
          if (arg.codeName != arg.bareName) GLArgumentValue("name".toToken(), arg.bareName),
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

  // ── Abstract ───────────────────────────────────────────────────────────────

  String serializeController(GLController ctrl);
  String serializeHandlerMethod(GLQueryType type, GLField method, String serviceInstanceName, GLToken context);
  String serializeMappingMethod(GLSchemaMapping mapping, String serviceInstanceName, GLToken context);
  String serializeIdentityMapping(GLSchemaMapping mapping, GLToken context);
  String serializeForwardedMapping(GLSchemaMapping mapping, GLToken context);
}
