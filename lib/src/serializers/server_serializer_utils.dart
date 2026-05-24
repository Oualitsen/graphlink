import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/server_serializer.dart';

mixin ServerSerializerUtils on ServerSerializer {
  bool isUploadScalar(GLType type) =>
      grammar.uploadScalarNames.contains(type.firstType.token);

  bool get hasUploads =>
      grammar.uploadScalarNames.isNotEmpty &&
      grammar.services.values.any(
          (s) => s.fields.any((f) => f.arguments.any((a) => isUploadScalar(a.type))));

  bool get hasSubscriptions =>
      grammar.services.values.any((s) =>
          s.fields.any((f) =>
              s.getTypeByFieldName(f.name.token) == GLQueryType.subscription));

  bool fieldHasValidation(GLField field) =>
      field.getDirectiveByName(glValidate) != null &&
      field.getDirectiveByName(glValidate)?.generated != true;

  String validationMethodName(String fieldName) =>
      GLService.getValidationMethodName(fieldName);
}
