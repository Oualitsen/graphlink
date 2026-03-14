import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/gq_directive.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/serializers/language.dart';

mixin GQDirectivesMixin {
  List<GQDirectiveValue> getDirectives({bool skipGenerated = false}) {
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
  final _decorators = <GQDirectiveValue>[];

  final Map<String, GQDirectiveValue> _directives = {};

  List<GQDirectiveValue> getAnnotations({CodeGenerationMode? mode}) {
    return getDirectives().where((d) => d.getArgValueAsBool(gqAnnotation)).where((d) {
      switch (mode) {
        case CodeGenerationMode.client:
          return d.getArgValueAsBool(gqOnClient);
        case CodeGenerationMode.server:
          return d.getArgValueAsBool(gqOnServer);
        case null:
          return true;
      }
    }).toList(growable: false);
  }

  void addDecoratorIfAbsent(GQDirectiveValue decorator) {}

  void addDirective(GQDirectiveValue directiveValue) {
    if (directiveValue.token == gqDecorators) {
      _decorators.add(directiveValue);
      return;
    }
    if (_directives.containsKey(directiveValue.token)) {
      throw ParseException("Directive '${directiveValue.tokenInfo}' already exists",
          info: directiveValue.tokenInfo);
    }
    _directives[directiveValue.token] = directiveValue;
  }

  void addDirectiveIfAbsent(GQDirectiveValue directiveValue) {
    _directives.putIfAbsent(directiveValue.token, () => directiveValue);
  }

  void removeDirectiveByName(String name) {
    _directives.remove(name);
  }

  GQDirectiveValue? getDirectiveByName(String name) {
    return _directives[name];
  }

  bool hasDirective(String name) {
    return _directives.containsKey(name);
  }
}
