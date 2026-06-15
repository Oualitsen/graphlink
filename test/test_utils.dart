import 'package:graphlink/src/model/gl_type_definition.dart';

String toServerProjectionName(String token) {
  return GLTypeDefinition.getServerProjectionName(token);
}