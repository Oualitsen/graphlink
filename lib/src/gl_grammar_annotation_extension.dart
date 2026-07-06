import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';

extension GLGrammarAnnotationExtension on GLParser {
  void convertAnnotationsToDecorators(List<GLDirectivesMixin> mixins, String Function(GLDirectiveValue value) serializer) {
    for (var elm in mixins) {
      elm
          .getAnnotations(mode: mode)
          .map(
            (an) => GLDirectiveValue.createGqDecorators(
                decorators: [serializer(an)],
                applyOnClient: mode == CodeGenerationMode.client,
                applyOnServer: mode == CodeGenerationMode.server,
                import: an.getArgValueAsString(glImport)),
          )
          .forEach(elm.addDirective);
      if (elm is GLService) {
        for (var m in elm.mappings) {
          m.field
              .getAnnotations(mode: mode)
              .map(
                (an) => GLDirectiveValue.createGqDecorators(
                    decorators: [serializer(an)],
                    applyOnClient: mode == CodeGenerationMode.client,
                    applyOnServer: mode == CodeGenerationMode.server,
                    import: an.getArgValueAsString(glImport)),
              )
              .forEach((e) {
                m.field.addDirective(e);
              });
        }
      }
    }
  }

  void handleAnnotations(String Function(GLDirectiveValue value) serializer) {
    if (annotationsProcessed) {
      return;
    }
    annotationsProcessed = true;
    convertAnnotationsToDecorators(_getDirectiveObjects(), serializer);
  }

  List<GLDirectivesMixin> _getDirectiveObjects() {
    var result = [
      ...inputs.values,
      ...typesWithNoResolvers,
      ...interfaces.values,
      ...scalars.values,
      ...enums.values,
      ...repositories.values,
    ].map((f) => f as GLDirectivesMixin).toList();

    var inputFields = inputs.values.expand((e) => e.fields);
    var interfaceFields = interfaces.values.expand((e) => e.fields);
    var repositoryFields = repositories.values.expand((e) => e.fields);
    var typeFields = typesWithNoResolvers.expand((e) => e.fields);
    var enumValues = enums.values.expand((e) => e.values);
    result.addAll([
      ...inputFields,
      ...interfaceFields,
      ...typeFields,
      ...enumValues,
      ...repositoryFields,
    ]);
    var params = <GLDirectivesMixin>[];
    result.whereType<GLField>().where((f) => f.arguments.isNotEmpty).forEach((f) {
      params.addAll(f.arguments);
    });
    result.addAll(params);

    return result;
  }

  void applyJspecifyAnnotations({required bool Function(GLType) isPrimitive}) {
    if (jspecifyAnnotationsProcessed) return;
    jspecifyAnnotationsProcessed = true;
    const nonNullImport = 'org.jspecify.annotations.NonNull';
    const nullableImport = 'org.jspecify.annotations.Nullable';

    List<String> annotateAndGetImports(List<GLField> fields, {required bool isTypeField}) {
      final imports = <String>{};
      for (final field in fields) {
        if (isPrimitive(field.type)) continue;
        final isNullable = field.type.nullable || (isTypeField && field.hasInculeOrSkipDiretives);
        if (isNullable) {
          field.addDirective(GLDirectiveValue.createGqDecorators(
            decorators: [jspecifyNullable],
            applyOnClient: mode == CodeGenerationMode.client,
            applyOnServer: mode == CodeGenerationMode.server,
          ));
          imports.add(nullableImport);
        } else {
          field.addDirective(GLDirectiveValue.createGqDecorators(
            decorators: [jspecifyNonNull],
            applyOnClient: mode == CodeGenerationMode.client,
            applyOnServer: mode == CodeGenerationMode.server,
          ));
          imports.add(nonNullImport);
        }
      }
      return imports.toList();
    }

    final typeTargets = mode == CodeGenerationMode.server ? typesWithNoResolvers : projectedTypes.values.toList();
    final interfaceTargets = mode == CodeGenerationMode.server ? interfaces.values.toList() : projectedInterfaces.values.toList();

    for (final def in typeTargets) {
      final imports = annotateAndGetImports(def.getSerializableFields(mode), isTypeField: true);
      imports.forEach(def.addImport);
    }
    for (final def in interfaceTargets) {
      final imports = annotateAndGetImports(def.getSerializableFields(mode), isTypeField: true);
      imports.forEach(def.addImport);
    }
    for (final def in inputs.values) {
      final imports = annotateAndGetImports(def.getSerializableFields(mode), isTypeField: false);
      imports.forEach(def.addImport);
    }
  }

  void setDirectivesDefaultValues() {
    var values = [...directiveValues];
    for (var value in values) {
      var def = directiveDefinitions[value.token];
      if (def != null) {
        value.setDefualtArguments(def.arguments);
      }
    }
  }

  void proparageAnnotationsOnFields() {
    extensibleTokens.values.expand((e) => e.data).whereType<GLTokenWithFields>().forEach(_propagateAnnotations);
  }

  void _propagateAnnotations(GLTokenWithFields tokenWithFields) {
    if (tokenWithFields is! GLDirectivesMixin) {
      return;
    }
    var mixin = tokenWithFields as GLDirectivesMixin;

    var annotations = mixin.getDirectives().where((d) => d.getArgValueAsBool(glAnnotation) && d.getArgValueAsBool(glApplyOnFields)).toList();
    if (annotations.isEmpty) {
      return;
    }
    for (var field in tokenWithFields.fields) {
      annotations.forEach(field.addDirectiveIfAbsent);
    }
    // remove directives from the super class.
    annotations.map((e) => e.token).forEach(mixin.removeDirectiveByName);
  }
}
