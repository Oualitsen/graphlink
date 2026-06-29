import 'package:graphlink/src/kotlin_code_gen_utils.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/java_imports.dart';
import 'package:graphlink/src/serializers/jvm_spring_server_serializer_base.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/kotlin_spring_controller_serializer.dart';

class KotlinSpringServerSerializer extends JvmSpringServerSerializerBase {
  @override
  final KotlinSerializer serializer;
  @override
  final KotlinCodeGenUtils codeGenUtils = KotlinCodeGenUtils();

  KotlinSpringServerSerializer._(
    GLParser grammar,
    KotlinSpringControllerSerializer ctrl,
    this.serializer, {
    required String packageName,
    bool generateSchema = false,
    bool injectDataFetching = false,
  }) : super(grammar, ctrl,
            packageName: packageName,
            generateSchema: generateSchema,
            injectDataFetching: injectDataFetching,
            reactive: false,
            useSpringSecurity: false);

  factory KotlinSpringServerSerializer(
    GLParser grammar, {
    required String packageName,
    bool inputsAsDataClass = false,
    bool typesAsDataClass = false,
    KotlinSerializer? kotlinSerializer,
    bool generateSchema = false,
    bool injectDataFetching = false,
    bool blockingServices = true,
  }) {
    final serializer = kotlinSerializer ??
        KotlinSerializer(grammar,
            inputsAsDataClass: inputsAsDataClass,
            typesAsDataClass: typesAsDataClass,
            importPrefix: packageName,
            generateJsonMethods: true);
    final ctrl = KotlinSpringControllerSerializer(
      grammar: grammar,
      serializer: serializer,
      packageName: packageName,
      injectDataFetching: injectDataFetching,
      generateSchema: generateSchema,
      blockingServices: blockingServices,
    );
    return KotlinSpringServerSerializer._(grammar, ctrl, serializer,
        packageName: packageName,
        generateSchema: generateSchema,
        injectDataFetching: injectDataFetching);
  }

  // ── Security ───────────────────────────────────────────────────────────────

  /// Returns the source for `SecurityCoroutineContext`, a `ThreadContextElement`
  /// that propagates `SecurityContextHolder` across coroutine dispatcher
  /// thread-hops. Emitted when `blockingServices` is enabled, since controller
  /// methods then use `withContext(Dispatchers.IO + SecurityCoroutineContext())`.
  String serializeSecurityCoroutineContext() {
    return '''import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.ThreadContextElement
import org.springframework.security.core.context.SecurityContext
import org.springframework.security.core.context.SecurityContextHolder

class SecurityCoroutineContext(
    private val securityContext: SecurityContext = SecurityContextHolder.getContext(),
) : ThreadContextElement<SecurityContext> {
    companion object Key : CoroutineContext.Key<SecurityCoroutineContext>

    override val key: CoroutineContext.Key<*> get() = Key

    override fun updateThreadContext(context: CoroutineContext): SecurityContext {
        val previous = SecurityContextHolder.getContext()
        SecurityContextHolder.setContext(securityContext)
        return previous
    }

    override fun restoreThreadContext(context: CoroutineContext, oldState: SecurityContext) {
        SecurityContextHolder.setContext(oldState)
    }
}
''';
  }

  // ── Repository ─────────────────────────────────────────────────────────────

  String serializeRepository(GLInterfaceDefinition interface) {
    var body = _serializeRepositoryBody(interface);
    return serializer.serializeWithImport(interface, body);
  }

  String _serializeRepositoryBody(GLInterfaceDefinition interface) {
    interface.addImport(SpringImports.repository);

    var gqRepo = interface.getDirectiveByName(glRepository)!;
    var className = gqRepo.getArgValueAsString(glClass);
    if (className == null) {
      className = "JpaRepository";
      interface.addImport(SpringImports.jpaRepository);
    }
    var id = gqRepo.getArgValueAsString(glIdType);
    var onType = gqRepo.getArgValueAsString(glType)!;

    var decorators = serializer.serializeDecorators(interface.getDirectives()).trim();
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators);
    }
    buffer.writeln('interface ${interface.token} : $className<$onType, $id>');
    return buffer.toString();
  }

  // ── Service body ─────────────────────────────────────────────────────────────

  @override
  String serializeServiceBody(GLService service) {
    var mappings = service.serviceMapping;
    return codeGenUtils.kotlinInterface(
      name: service.token,
      body: [
        ...service.fields.map((n) =>
            ctrl.serializeMethodDeclaration(n, service.getTypeByFieldName(n.name.token)!, service)),
        ...mappings.map((m) => ctrl.serializeServiceMappingImplMethodHeader(m, service)),
      ],
    );
  }
}
