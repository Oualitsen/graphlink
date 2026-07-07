import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';

mixin GLDirectivesMixin {
  List<GLDirectiveValue>? _cachedDirectives;
  bool? _containsSkipOrIncludeDirective;


  List<GLDirectiveValue> getDirectives({bool skipGenerated = false}) {
    final all = _cachedDirectives ??=
        (_directives == null && _decorators == null)
            ? const []
            : [...?_directives?.values, ...?_decorators];
    if (skipGenerated) {
      return all.where((d) => !d.generated).toList(growable: false);
    }
    return all;
  }

  ///
  /// We need to handle decorators differently as one field can have multiple
  /// decorators comming from different other annotations.
  ///
  /// Both collections are lazily allocated: most fields/arguments carry no
  /// directives, so we avoid allocating an empty List + Map per mixer (every
  /// GLField, GLArgumentDefinition, GLTypeDefinition, GLQueryElement) across a
  /// large schema.
  List<GLDirectiveValue>? _decorators;

  Map<String, GLDirectiveValue>? _directives;

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
      (_decorators ??= []).add(directiveValue);
      _cachedDirectives = null;
      return;
    }
    final directives = _directives ??= {};
    if (directives.containsKey(directiveValue.token)) {
      throw ParseException("Directive '${directiveValue.tokenInfo}' already exists",
          info: directiveValue.tokenInfo);
    }
    directives[directiveValue.token] = directiveValue;
    _cachedDirectives = null;
  }

  void addDirectiveIfAbsent(GLDirectiveValue directiveValue) {
    (_directives ??= {}).putIfAbsent(directiveValue.token, () => directiveValue);
    _cachedDirectives = null;
  }

  void removeDirectiveByName(String name) {
    _directives?.remove(name);
    _cachedDirectives = null;
  }

  GLDirectiveValue? getDirectiveByName(String name) {
    return _directives?[name];
  }

  bool hasDirective(String name) {
    return _directives?.containsKey(name) ?? false;
  }

  bool get isExternal => hasDirective(glExternal);

  String? get externalImport => getDirectiveByName(glExternal)?.getArgValueAsString(glImport);

  //check for inclue or skip directives
  bool get hasInculeOrSkipDiretives => _containsSkipOrIncludeDirective ??=
      getDirectives().where((d) => [includeDirective, skipDirective].contains(d.token)).isNotEmpty;
}
