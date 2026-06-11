import 'dart:io';
import 'package:graphlink/src/code_gen_utils.dart';
import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_controller.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/annotation_serializer.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/jvm_spring_controller_serializer_base.dart';
import 'package:graphlink/src/serializers/server_serializer.dart';

abstract class JvmSpringServerSerializerBase extends ServerSerializer
    with ServerSerializerUtils {
  final String packageName;
  final bool generateSchema;
  final bool injectDataFetching;
  final bool reactive;
  final bool useSpringSecurity;
  late final JvmSpringControllerSerializerBase _ctrl;

  GLSerializer get serializer;
  CodeGenUtilsBase get codeGenUtils;

  JvmSpringServerSerializerBase(
    GLParser grammar,
    JvmSpringControllerSerializerBase ctrl, {
    required this.packageName,
    this.generateSchema = false,
    this.injectDataFetching = false,
    this.reactive = false,
    this.useSpringSecurity = false,
  })  : assert(grammar.mode == CodeGenerationMode.server,
            "Grammar must be in code generation mode = `CodeGenerationMode.server`"),
        super(grammar) {
    _ctrl = ctrl;
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

  // ── ServerSerializer overrides ─────────────────────────────────────────────

  @override
  String serializeService(GLService service) {
    var body = serializeServiceBody(service);
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

  String serializeController(GLController ctrl) =>
      _ctrl.serializeController(ctrl);

  // ── Abstract body builders ───────────────────────────────────────────────────

  /// Builds the service interface body. Language-specific because the
  /// interface/method syntax differs (Java `interface`/`;` vs. Kotlin
  /// `interface`/`fun`/`suspend fun`).
  String serializeServiceBody(GLService service);

  // ── Shared helpers for subclasses ────────────────────────────────────────────

  JvmSpringControllerSerializerBase get ctrl => _ctrl;
}
