import 'package:graphlink/src/kotlin_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_controller.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_schema_mapping.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/serializers/jvm_spring_controller_serializer_base.dart';
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
    throw UnimplementedError();
  }
  

  @override
  String serializehandlerMethod(GLQueryType type, GLField method, String serviceInstanceName, GLToken context,
      {String? qualifier}) {
        throw UnimplementedError();

  }

  @override
  String serializeIdentityMapping(GLSchemaMapping mapping, GLToken context) {
    throw UnimplementedError();
  }

  @override
  String serializeForwardedMapping(GLSchemaMapping mapping, GLToken context) {
    throw UnimplementedError();
  }

  

  

  @override
  String serializeControllerMethodHeader(GLSchemaMapping mapping, GLToken context) {
    throw UnimplementedError();
  }

  // ── Service declarations ───────────────────────────────────────────────────

  @override
  String serializeMethodDeclaration(GLField method, GLQueryType type, GLToken context) {
    throw UnimplementedError();
  }

  @override
  String serializeServiceMappingImplMethodHeader(GLSchemaMapping mapping, GLToken context) {
   throw UnimplementedError();
  }

  // ── Args ────────────────────────────────────────────────────────────────────

  @override
  String serializeArg(GLArgumentDefinition arg, GLToken context) {
   throw UnimplementedError();
  }

 

  @override
  String resolveArgType(GLArgumentDefinition arg, GLToken context) {
    throw UnimplementedError();
  }
  
  @override
  String serializeMappingMethod(GLSchemaMapping mapping, String serviceInstanceName, GLToken context) {
    throw UnimplementedError();
  }
}
