import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/utils.dart';

class AnnotationSerializer {
  static String serializeAnnotation(GLDirectiveValue value, {bool multiLineString = false}) {
    if (value.getArgValue(glAnnotation) != true) {
      throw ParseException(
          "Cannot serialze annotation ${value.tokenInfo} with argment ${glAnnotation} = ${value.getArgValue(glAnnotation)}",
          info: value.tokenInfo);
    }
    if (value.getArgValue(glClass) is! String) {
      throw ParseException(
          "Cannot serialze annotation ${value.tokenInfo} with argment ${glClass} = ${value.getArgValue(glClass)}",
          info: value.tokenInfo);
    }
    const skip = [glClass, glAnnotation, glOnClient, glOnServer, glImport, glApplyOnFields];
    var args = value.getArguments().where((arg) => !skip.contains(arg.token)).map((arg) {
      var argValue = arg.value;
      if (argValue is String && !multiLineString) {
        argValue = argValue.toJavaString();
      }

      return "${arg.tokenInfo} = ${argValue}";
    }).join(", ");
    var fqcn = getFqcnFromDirective(value);
    return "${fqcn}(${args})";
  }

  static String decoratorName(GLDirectiveValue value) {
    final name = value.getArgValueAsString(glClass);
    if (name == null) {
      throw ParseException("Cannot serialze annotation ${value.tokenInfo} without $glClass", info: value.tokenInfo);
    }
    return name.startsWith('@') ? name.substring(1) : name;
  }

  static List<MapEntry<String, String>> namedArguments(GLDirectiveValue value, String Function(String) quoteString) {
    const skip = [glClass, glAnnotation, glOnClient, glOnServer, glImport, glApplyOnFields];
    return [
      for (final arg in value.getArguments())
        if (!skip.contains(arg.token)) MapEntry(arg.token, arg.value is String ? quoteString(arg.value as String) : '${arg.value}'),
    ];
  }
}
