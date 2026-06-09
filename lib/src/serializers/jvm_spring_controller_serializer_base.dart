import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_controller.dart';
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
  final codeGenUtils = JavaCodeGenUtils();

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
        method.addDirective(_createResolverDirective(queryType));
        for (var arg in method.arguments) {
          arg.addDirective(_createArgumentDirective());
        }
      }
    }
  }

  GLDirectiveValue _createResolverDirective(GLQueryType type) {
    return GLDirectiveValue(
        "_gqMapping".toToken(),
        [],
        [
          GLArgumentValue(glAnnotation.toToken(), true),
          GLArgumentValue(glClass.toToken(), _toMappingAnnotationValue(type)),
          GLArgumentValue(glImport.toToken(), _toMappingAnnotationImport(type)),
          GLArgumentValue(glOnServer.toToken(), true),
        ],
        generated: true);
  }

  GLDirectiveValue _createControllerDirective() {
    return GLDirectiveValue(
        "_gqController".toToken(),
        [],
        [
          GLArgumentValue(glAnnotation.toToken(), true),
          GLArgumentValue(glClass.toToken(), "@Controller"),
          GLArgumentValue(glImport.toToken(), SpringImports.controller),
          GLArgumentValue(glOnServer.toToken(), true),
        ],
        generated: true);
  }

  GLDirectiveValue _createArgumentDirective() {
    return GLDirectiveValue(
        "_gqController".toToken(),
        [],
        [
          GLArgumentValue(glAnnotation.toToken(), true),
          GLArgumentValue(glClass.toToken(), "@Argument"),
          GLArgumentValue(glImport.toToken(), SpringImports.gqlArgument),
          GLArgumentValue(glOnServer.toToken(), true),
        ],
        generated: true);
  }

  String getAnnotationForMapping(GLSchemaMapping mapping, GLToken context) {
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
    var mappedTo = grammar
        .getType(dir.getArgumentByName(glMapTo)!.tokenInfo.ofNewName(mapTo));
    if (mappedTo.getDirectiveByName(glSkipOnServer) != null) {
      throw ParseException(
          "You cannot mapTo ${mappedTo.tokenInfo} because it is annotated with $glSkipOnServer",
          info: mappedTo.tokenInfo);
    }
    return mappedTo.token;
  }

  // ── Args ───────────────────────────────────────────────────────────────────

  String serializeArgs(List<GLArgumentDefinition> args, GLToken context,
      [String? prefix]) {
    return args.map((a) => serializeArg(a, context)).map((e) {
      if (prefix != null) return "$prefix $e";
      return e;
    }).join(", ");
  }

  String serializeArg(GLArgumentDefinition arg, GLToken context) {
    return "${resolveArgType(arg, context)} ${arg.tokenInfo}";
  }

  // ── Abstract ───────────────────────────────────────────────────────────────

  String resolveArgType(GLArgumentDefinition arg, GLToken context);
  String serializeController(GLController ctrl);
  String serializehandlerMethod(GLQueryType type, GLField method,
      String serviceInstanceName, GLToken context,
      {String? qualifier});
  String serializeMappingMethod(
      GLSchemaMapping mapping, String serviceInstanceName, GLToken context);
  String serializeMethodDeclaration(GLField method, GLQueryType type,
      GLToken context,
      {String? argPrefix});
  String serializeServiceMappingImplMethodHeader(
      GLSchemaMapping mapping, GLToken context);
  String serializeControllerMethodHeader(
      GLSchemaMapping mapping, GLToken context);
  String serializeIdentityMapping(GLSchemaMapping mapping, GLToken context);
  String serializeForwardedMapping(GLSchemaMapping mapping, GLToken context);
}
