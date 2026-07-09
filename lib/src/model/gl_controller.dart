import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_schema_mapping.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_token.dart';

class GLController extends GLService {
  final String serviceName;
  GLController({
    required this.serviceName,
    required super.name,
    required super.nameDeclared,
    required super.fields,
    required super.interfaceNames,
    required super.directives,
    required super.parser,
  });

  static GLController ofService(GLService service, GLParser parser) {
    var ctrl = GLController(
      serviceName: service.token,
      name: "${service.token}Controller".toToken(),
      nameDeclared: service.nameDeclared,
      fields: [],
      interfaceNames: {},
      directives: [],
      parser: parser,
    );
    for (var f in service.fields) {
      var validationDirective = f.getDirectiveByName(glValidate);
      if (validationDirective == null || !validationDirective.generated) {
        var targetField = GLField(
          name: f.name,
          type: f.type.copy,
          arguments: [...f.arguments.map((arg) => GLArgumentDefinition(arg.tokenInfo, arg.type.copy, []))],
          directives: [...f.getDirectives()],
          initialValue: f.initialValue,
          documentation: f.documentation,
        );
        ctrl.addField(targetField);
        ctrl.setFieldType(f.name.token, service.getTypeByFieldName(f.name.token)!);
      }
    }
    return ctrl;
  }

  @override
  void addMapping(GLSchemaMapping mapping) {
    String newTypeName = mapping.type.token;
    String newFieldTypeName = mapping.field.type.token;
    final newMapping = mapping.ofNewTypes(mapping, newTypeName, newFieldTypeName, mapping.key);
    if (mapping.isBatch && !mapping.identity) {
      // A (non-identity) batch mapping's real return shape is `Map<Key,
      // Value>` — model it as a GLMapType so the serializer's generic
      // GLMapType handling (and any wrapper later applied, e.g.
      // CompletableFuture/Mono) lands on the whole map instead of on the
      // value type embedded inside it. Identity batch mappings return
      // List<Value>/Flux<Value> directly (the value already is the key), so
      // they keep the bare value type.
      final keyType = GLType(mapping.getMappedToType(parser).tokenInfo, false);
      newMapping.field = newMapping.field.ofType(GLMapType(keyType, newMapping.field.type, false));
    }
    super.addMapping(newMapping);
  }

  @override
  Set<GLToken> getImportDependecies(GLParser g) {
    var result = {...super.getImportDependecies(g)};
    if (g.services.containsKey(serviceName)) {
      result.add(g.services[serviceName]!);
    }
    return result;
  }

  /// [GLTokenWithFields.getImports] only walks regular fields — schema/batch
  /// mapping methods live in [mappings] instead, so their return types,
  /// arguments, and directive-declared imports (e.g. the `Mono`/`Flux`/
  /// `CompletableFuture` wrapper set by the Spring controller serializer, or
  /// `Map<String, Object>` from JVM wire-encoding mappification) would
  /// otherwise never make it into the controller's import block.
  @override
  Set<String> getImports(GLParser g) {
    var result = {...super.getImports(g)};
    for (var mapping in mappings) {
      final field = mapping.field;
      result.addAll(GLTokenWithFields.extractImports(field, g.mode, skipOwnImports: false));
      result.addAll(collectionImportsOf(field.type));

      final token = g.getTokenByKey(field.type.token);
      if (token != null && token is GLDirectivesMixin) {
        result.addAll(GLTokenWithFields.extractImports(token as GLDirectivesMixin, g.mode, skipOwnImports: true));

        for (var arg in field.arguments) {
          result.addAll(GLTokenWithFields.extractImports(arg, g.mode, skipOwnImports: false));
          var argToken = g.getTokenByKey(arg.type.token);
          if (argToken != null && argToken is GLDirectivesMixin) {
            result.addAll(GLTokenWithFields.extractImports(argToken as GLDirectivesMixin, g.mode, skipOwnImports: true));
          }
        }
      }
      for (var arg in field.arguments) {
        result.addAll(arg.getAnnotations().map((e) => e.getArgValueAsString(glImport)).where((imp) => imp != null).map((e) => e!));
        result.addAll(arg.getImports(g));
      }
    }
    return result;
  }

}
