import 'dart:io';
import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_controller.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/serializers/annotation_serializer.dart';
import 'package:graphlink/src/serializers/java_imports.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/server_serializer.dart';
import 'package:graphlink/src/serializers/spring_controller_serializer.dart';

class SpringServerSerializer extends ServerSerializer with ServerSerializerUtils {
  final String? defaultRepositoryBase;
  final String packageName;

  final JavaSerializer serializer;
  final bool generateSchema;
  final bool injectDataFetching;
  final bool reactive;
  final bool useSpringSecurity;
  final codeGenUtils = JavaCodeGenUtils();
  late final SpringControllerSerializer _ctrl;

  SpringServerSerializer(GLParser grammar,
      {required this.packageName,
      this.defaultRepositoryBase,
      JavaSerializer? javaSerializer,
      this.generateSchema = false,
      this.injectDataFetching = false,
      this.reactive = false,
      this.useSpringSecurity = false})
      : assert(grammar.mode == CodeGenerationMode.server,
            "Grammar must be in code generation mode = `CodeGenerationMode.server`"),
        serializer = javaSerializer ??
            JavaSerializer(grammar,
                inputsCheckForNulls: true,
                typesCheckForNulls: grammar.mode == CodeGenerationMode.client,
                importPrefix: packageName),
        super(grammar) {
    _ctrl = SpringControllerSerializer(
      grammar: grammar,
      serializer: serializer,
      reactive: reactive,
      injectDataFetching: injectDataFetching,
      useSpringSecurity: useSpringSecurity,
      generateSchema: generateSchema,
    );
    _validateFieldArguments();
    _annotateRepositories();
    _ctrl.annotateControllers();
    _warnIfUploadScalarsPresent();
    grammar.convertAnnotationsToDecorators(
        _getControllerMixins(),
        (val) => AnnotationSerializer.serializeAnnotation(val,
            multiLineString: false));
  }

  // ── Initialization ─────────────────────────────────────────────────────────

  void _warnIfUploadScalarsPresent() {
    if (grammar.uploadScalarNames.isEmpty) return;
    final scalars = grammar.uploadScalarNames.join(', ');
    stdout.writeln('''
ℹ  File upload detected — Spring Boot configuration required
   ─────────────────────────────────────────────────────────
   Upload scalar(s) found: $scalars

   1. Multipart support
      Spring for GraphQL does not handle multipart requests out of the box.
      Add the following library to your project:

        https://github.com/nkonev/multipart-spring-graphql

      Follow its README to register the multipart scalar and configure
      the servlet multipart resolver in application.properties:

        spring.servlet.multipart.enabled=true
        spring.servlet.multipart.max-file-size=10MB
        spring.servlet.multipart.max-request-size=10MB

   2. Prevent schema redefinition errors
      The $scalars scalar is declared in your schema file. If GraphLink
      copies that file to the server output (generateSchema: true), the
      library above will also register the scalar — causing a duplicate
      definition error at startup.

      To avoid this, annotate the scalar in your schema with @glSkipOnServer
      so GraphLink omits it from the generated schema copy:

        scalar Upload @glUpload @glSkipOnServer

      Then enable schema copying in your config:

        "generateSchema": true
        "schemaTargetPath": "src/main/resources/graphql/schema.graphqls"
   ─────────────────────────────────────────────────────────
''');
  }

  List<GLDirectivesMixin> _getControllerMixins() {
    var ctrlList = grammar.controllers.values.toList();
    var fields = ctrlList.expand((ctrl) => ctrl.fields);
    var args = fields.expand((e) => e.arguments);
    return [...ctrlList, ...fields, ...args];
  }

  void _validateFieldArguments() {
    final rootTypeNames =
        GLQueryType.values.map((e) => grammar.schema.getByQueryType(e)).toSet();
    grammar.types.values
        .where((type) => !rootTypeNames.contains(type.token))
        .forEach((type) {
      for (var field in type.fields) {
        if (field.arguments.isEmpty) continue;
        final skipOnServer = field.getDirectiveByName(glSkipOnServer);
        if (skipOnServer == null) {
          throw ParseException(
            "Field '${field.name}' on type '${type.token}' has arguments but is missing $glSkipOnServer — "
            "add $glSkipOnServer(batch: false) to generate a @SchemaMapping for it",
            info: field.name,
          );
        }
        final batch = skipOnServer.getArgValue(glBatch) as bool?;
        if (batch == true) {
          throw ParseException(
            "Field '${field.name}' on type '${type.token}' has arguments and cannot use @BatchMapping — "
            "change to $glSkipOnServer(batch: false) to generate a @SchemaMapping instead",
            info: field.name,
          );
        }
      }
    });
  }

  void _annotateRepositories() {
    for (var repo in grammar.repositories.values) {
      var dec = GLDirectiveValue.createGqDecorators(
          decorators: ["@Repository"],
          applyOnClient: false,
          import: "org.springframework.stereotype.Repository");
      repo.addDirective(dec);
    }
  }

  // ── Base class overrides ───────────────────────────────────────────────────

  @override
  String serializeService(GLService service) {
    var body = _serializeServiceBody(service);
    return serializer.serializeWithImport(service, body);
  }

  @override
  String? serializeGuard(GLService service) => null;

  @override
  List<String> serializeResolvers() =>
      grammar.controllers.values.map(_ctrl.serializeController).toList();

  @override
  String serializeTypeDefs() =>
      generateSchema ? GLGraphqlSerializer(grammar).generateSchema() : '';

  // ── Spring-specific public API ─────────────────────────────────────────────

  String serializeController(GLController ctrl) => _ctrl.serializeController(ctrl);

  String serializeRepository(GLInterfaceDefinition interface) {
    var body = _serializeRepositoryBody(interface);
    return serializer.serializeWithImport(interface, body);
  }

  // ── Private body builders ──────────────────────────────────────────────────

  String _serializeServiceBody(GLService service) {
    var mappings = service.serviceMapping;
    var buffer = StringBuffer();
    buffer.writeln(
        codeGenUtils.createInterface(interfaceName: service.token, statements: [
      '',
      ...service.fields
          .map((n) => _ctrl.serializeMethodDeclaration(
              n, service.getTypeByFieldName(n.name.token)!, service))
          .map((e) => "${e};"),
      '',
      ...mappings
          .map((m) => _ctrl.serializeServiceMappingImplMethodHeader(m, service))
          .map((e) => "${e};")
    ]));
    return buffer.toString();
  }

  String _serializeRepositoryBody(GLInterfaceDefinition interface) {
    interface
        .getSerializableFields(grammar.mode)
        .where((f) => f.name.token == "_")
        .forEach((f) {
      f.addDirective(
          GLDirectiveValue(glSkipOnServer.toToken(), [], [], generated: true));
    });
    interface.addImport(SpringImports.repository);

    var gqRepo = interface.getDirectiveByName(glRepository)!;
    var className = gqRepo.getArgValueAsString(glClass);
    if (className == null) {
      className = "JpaRepository";
      interface.addImport(SpringImports.jpaRepository);
    }
    var id = gqRepo.getArgValueAsString(glIdType);
    var ontType = gqRepo.getArgValueAsString(glType)!;

    interface.addInterface(GLInterfaceDefinition(
        name: "$className<$ontType, ${id}>".toToken(),
        nameDeclared: false,
        fields: [],
        directives: [],
        interfaceNames: {},
        extension: false));

    return serializer.serializeInterface(interface, getters: false);
  }
}
