import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/kotlin_code_gen_utils.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_intercept_extension.dart';
import 'package:graphlink/src/serializers/java_imports.dart';
import 'package:graphlink/src/serializers/jvm_spring_server_serializer_base.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/kotlin_spring_controller_serializer.dart';

class KotlinSpringServerSerializer extends JvmSpringServerSerializerBase {
  @override
  final KotlinSerializer serializer;
  @override
  final KotlinCodeGenUtils codeGenUtils = KotlinCodeGenUtils();

  /// Whether the developer-implemented `*Service` methods are blocking. When
  /// `false`, service methods are generated as `suspend fun` so implementations
  /// can call other suspend functions directly.
  final bool blockingServices;

  KotlinSpringServerSerializer._(
    super.grammar,
    KotlinSpringControllerSerializer super.ctrl,
    this.serializer, {
    required super.packageName,
    required this.blockingServices,
    super.generateSchema,
    super.injectDataFetching,
  }) : super(reactive: false,
            useSpringSecurity: false);

  factory KotlinSpringServerSerializer(
    GLParser grammar, {
    required String packageName,
    bool inputsAsDataClass = false,
    bool typesAsDataClass = false,
    KotlinSerializer? kotlinSerializer,
    bool generateSchema = false,
    bool injectContext = false,
    bool blockingServices = true,
  }) {
    final serializer = kotlinSerializer ??
        KotlinSerializer(grammar,
            inputsAsDataClass: inputsAsDataClass,
            typesAsDataClass: typesAsDataClass,
            importPrefix: packageName);
    final ctrl = KotlinSpringControllerSerializer(
      grammar: grammar,
      serializer: serializer,
      packageName: packageName,
      injectContext: injectContext,
      generateSchema: generateSchema,
      blockingServices: blockingServices,
    );
    return KotlinSpringServerSerializer._(grammar, ctrl, serializer,
        packageName: packageName,
        blockingServices: blockingServices,
        generateSchema: generateSchema,
        injectDataFetching: injectContext);
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

  // ── interfaces/GraphLinkInterceptor.kt ──────────────────────────────────────

  /// Appends the JVM-specific `context` param onto the shared `runBefore` IR,
  /// then serializes normally.
  String? serializeInterceptorInterface() {
    if (!grammar.usesInterceptor) return null;
    final interfaceDef = grammar.interfaces[glInterceptorInterfaceName]!;
    _addInterceptorContextArg(interfaceDef);

    final body = serializer.serializeInterface(interfaceDef,
        skipJsonConversionMethods: true, fieldsAsFunctions: true, suspendFunctions: true);
    return serializer.serializeWithImport(interfaceDef, body);
  }

  void _addInterceptorContextArg(GLInterfaceDefinition def) {
    final runBefore = def.fields.firstWhere((f) => f.name.token == glInterceptorRunBeforeMethod);
    if (runBefore.arguments.any((a) => a.token == 'context')) return;
    runBefore.addArgument(
        GLArgumentDefinition('context'.toToken(), GLType('GraphQLContext'.toToken(), false), []));
    def.addImport(SpringImports.gqlGraphQLContext);
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
    return serializer.serializeInterface(service,
        skipJsonConversionMethods: true,
        fieldsAsFunctions: true,
        suspendFunctions: !blockingServices);
  }
}
