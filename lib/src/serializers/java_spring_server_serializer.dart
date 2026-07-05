import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/java_imports.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/java_spring_controller_serializer.dart';
import 'package:graphlink/src/serializers/jvm_spring_server_serializer_base.dart';

class JavaSpringServerSerializer extends JvmSpringServerSerializerBase {
  @override
  final JavaSerializer serializer;
  @override
  final JavaCodeGenUtils codeGenUtils = JavaCodeGenUtils();
  final String? defaultRepositoryBase;

  JavaSpringServerSerializer._(
    super.grammar,
    JavaSpringControllerSerializer super.ctrl,
    this.serializer, {
    required super.packageName,
    this.defaultRepositoryBase,
    super.generateSchema,
    super.injectDataFetching,
    super.reactive,
    super.useSpringSecurity,
  });

  factory JavaSpringServerSerializer(
    GLParser grammar, {
    required String packageName,
    String? defaultRepositoryBase,
    JavaSerializer? javaSerializer,
    bool generateSchema = false,
    bool injectDataFetching = false,
    bool reactive = false,
    bool useSpringSecurity = false,
  }) {
    final serializer = javaSerializer ??
        JavaSerializer(grammar,
            inputsCheckForNulls: true,
            typesCheckForNulls: grammar.mode == CodeGenerationMode.client,
            importPrefix: packageName);
    final ctrl = JavaSpringControllerSerializer(
      grammar: grammar,
      serializer: serializer,
      reactive: reactive,
      injectDataFetching: injectDataFetching,
      useSpringSecurity: useSpringSecurity,
      generateSchema: generateSchema,
    );
    return JavaSpringServerSerializer._(grammar, ctrl, serializer,
        packageName: packageName,
        defaultRepositoryBase: defaultRepositoryBase,
        generateSchema: generateSchema,
        injectDataFetching: injectDataFetching,
        reactive: reactive,
        useSpringSecurity: useSpringSecurity);
  }

  // ── Repository ─────────────────────────────────────────────────────────────

  String serializeRepository(GLInterfaceDefinition interface) {
    var body = _serializeRepositoryBody(interface);
    return serializer.serializeWithImport(interface, body);
  }

  String _serializeRepositoryBody(GLInterfaceDefinition interface) {
    interface
        .getSerializableFields(grammar.mode)
        .where((f) => f.name.token == "_")
        .forEach((f) {
      f.addDirective(
          GLDirectiveValue(glSkipOnServer.toToken(), [], [], generated: true));
    });
    interface.invalidateSerializableCacheFields(grammar.mode);
    interface.addImport(SpringImports.repository);

    var gqRepo = interface.getDirectiveByName(glRepository)!;
    var className = gqRepo.getArgValueAsString(glClass);
    if (className == null) {
      className = "JpaRepository";
      interface.addImport(SpringImports.jpaRepository);
    }
    var id = gqRepo.getArgValueAsString(glIdType);
    var onType = gqRepo.getArgValueAsString(glType)!;

    interface.addInterface(GLInterfaceDefinition(
        name: "$className<$onType, ${id}>".toToken(),
        nameDeclared: false,
        fields: [],
        directives: [],
        interfaceNames: {},
        extension: false));

    return serializer.serializeInterface(interface, getters: false);
  }

  // ── Service body ─────────────────────────────────────────────────────────────

  @override
  String serializeServiceBody(GLService service) {
    return serializer.serializeInterface(service, getters: false, skipJsonConversionMethods: true);
  }
}
