import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/utils.dart';

class AnnotationSerializer {

 static String serializeAnnotation(GQDirectiveValue value, {bool multiLineString = false}) {
    if (value.getArgValue(gqAnnotation) != true) {
      throw ParseException(
          "Cannot serialze annotation ${value.token} with argment ${gqAnnotation} = ${value.getArgValue(gqAnnotation)}");
    }
    if (value.getArgValue(gqFQCN) is! String) {
      throw ParseException(
          "Cannot serialze annotation ${value.token} with argment ${gqFQCN} = ${value.getArgValue(gqFQCN)}");
    }
    const skip = [gqFQCN, gqAnnotation, gqOnClient, gqOnServer];
    var args = value
        .getArguments()
        .where((arg) => !skip.contains(arg.token))
        .map((arg) {
      var argValue = arg.value;
      if (argValue is String && !multiLineString) {
        argValue = argValue.toJavaString();
      }

      return "${arg.token} = ${argValue}";
    }).join(", ");
    var fqcn = getFqcnFromDirective(value);
    return "${fqcn}(${args})";
    

  }
}

