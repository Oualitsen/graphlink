import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';

mixin GqDirectivesMixin {
  List<GQDirectiveValue> getDirectives({bool skipGenerated = false}) {
    final result = [..._directives.values, ..._decorators];
    if(skipGenerated) {
      return result.where((d) => !d.generated).toList();
    }
    return result;
  }

  ///
  /// We need to handle decorators differently as one field can have multiple
  /// decorators comming from different other annotations.
  ///
  final _decorators = <GQDirectiveValue>[];

  final Map<String, GQDirectiveValue> _directives = {};

  List<GQDirectiveValue> getAnnotations({CodeGenerationMode? mode}) {
    return getDirectives().where((d) => d.getArgValue(gqAnnotation) == true).where((d) {
      switch (mode) {
        case CodeGenerationMode.client:
          return d.getArgValue(gqOnClient) == true;
        case CodeGenerationMode.server:
          return d.getArgValue(gqOnServer) == true;
        case null:
          return true;
      }
    }).toList();
  }

  void addDirective(GQDirectiveValue directiveValue) {
    if (directiveValue.token == gqDecorators) {
      _decorators.add(directiveValue);
      return;
    }
    if (_directives.containsKey(directiveValue.token)) {
      throw ParseException("Directive '${directiveValue.token}' already exists");
    }
    _directives[directiveValue.token] = directiveValue;
  }

  void addDirectiveIfAbsent(GQDirectiveValue directiveValue) {
    _directives.putIfAbsent(directiveValue.token, () => directiveValue);
  }

  GQDirectiveValue? getDirectiveByName(String name) {
    return _directives[name];
  }
}
