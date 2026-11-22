import 'dart:convert';

import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/serializers/annotation_serializer.dart';

class TypeScriptAnnotationSerializer {
  static String serializeAnnotation(GLDirectiveValue value) {
    final args = AnnotationSerializer.namedArguments(value, (s) => jsonEncode(s.replaceAll(RegExp(r'^"|"$'), '')));
    return '@${AnnotationSerializer.decoratorName(value)}(${args.isEmpty ? '' : '{ ${args.map((a) => '${a.key}: ${a.value}').join(', ')} }'})';
  }
}
