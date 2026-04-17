import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';

mixin GLDirectivesMixin {
  List<GLDirectiveValue> getDirectives({bool skipGenerated = false}) {
    final result = [..._directives.values, ..._decorators];
    if (skipGenerated) {
      return result.where((d) => !d.generated).toList(growable: false);
    }
    return result;
  }

  ///
  /// We need to handle decorators differently as one field can have multiple
  /// decorators comming from different other annotations.
  ///
  final _decorators = <GLDirectiveValue>[];

  final Map<String, GLDirectiveValue> _directives = {};

  List<GLDirectiveValue> getAnnotations({CodeGenerationMode? mode}) {
    return getDirectives().where((d) => d.getArgValueAsBool(glAnnotation)).where((d) {
      switch (mode) {
        case CodeGenerationMode.client:
          return d.getArgValueAsBool(glOnClient);
        case CodeGenerationMode.server:
          return d.getArgValueAsBool(glOnServer);
        case null:
          return true;
      }
    }).toList(growable: false);
  }

  void addDecoratorIfAbsent(GLDirectiveValue decorator) {}

  void addDirective(GLDirectiveValue directiveValue) {
    if (directiveValue.token == glDecorators) {
      _decorators.add(directiveValue);
      return;
    }
    if (_directives.containsKey(directiveValue.token)) {
      throw ParseException("Directive '${directiveValue.tokenInfo}' already exists",
          info: directiveValue.tokenInfo);
    }
    _directives[directiveValue.token] = directiveValue;
  }

  void addDirectiveIfAbsent(GLDirectiveValue directiveValue) {
    _directives.putIfAbsent(directiveValue.token, () => directiveValue);
  }

  void removeDirectiveByName(String name) {
    _directives.remove(name);
  }

  GLDirectiveValue? getDirectiveByName(String name) {
    return _directives[name];
  }

  bool hasDirective(String name) {
    return _directives.containsKey(name);
  }
}
