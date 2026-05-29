import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_query_element.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_fragment.dart';
import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/utils.dart';

enum GLQueryType { query, mutation, subscription }

class GLQueryDefinition extends GLToken with GLDirectivesMixin {
  final List<GLArgumentDefinition> arguments;
  final List<GLQueryElement> elements;
  final GLQueryType type; //query|mutation|subscription
  Set<GLFragmentDefinitionBase>? _allFrags;

  GLTypeDefinition? _glTypeDefinition;
  GLTypeDefinition? _glFullResponse;

  Set<String> get fragmentNames {
    return elements.expand((e) => e.fragmentNames).toSet();
  }

  Set<GLFragmentDefinitionBase> fragments(GLParser g) {
    if (_allFrags == null) {
      var frags = fragmentNames
          .map((e) => g.getFragmentByName(e))
          .where((e) => e != null)
          .map((e) => e!)
          .toSet();
      _allFrags = {...frags, ...frags.expand((e) => e.dependecies)};
    }
    return _allFrags!;
  }

  GLQueryDefinition(super.tokenInfo, List<GLDirectiveValue> directives,
      this.arguments, this.elements, this.type) {
    directives.forEach(addDirective);
    checkVariables();
  }

  void checkVariables() {
    for (var elem in elements) {
      checkElement(elem);
    }
  }

  void checkElement(GLQueryElement element) {
    var list = element.arguments;

    for (var arg in list) {
      if ("${arg.value}".startsWith("\$")) {
        var check = checkValue("${arg.value}");
        if (!check) {
          throw ParseException("Argument ${arg.value} was not declared",
              info: arg.tokenInfo);
        }
      }
    }
  }

  bool checkValue(String value) {
    for (var arg in arguments) {
      if (arg.token == value) {
        return true;
      }
    }
    return false;
  }

  GLTypeDefinition getFullResponseTypeDefinition(GLParser parser) {
    var result = _glFullResponse;
    if(result == null) {
      final errorsType = GLListType(GLType(parser.getTypeByName('GraphLinkError')!.tokenInfo, false), true);
      final dataType = GLType(getGeneratedTypeDefinition().tokenInfo, true);
      result = _glFullResponse = GLTypeDefinition(name: tokenInfo.ofNewName(_fullResponseName()), nameDeclared: false, fields: [
        GLField(name: "errors".toToken(), type: errorsType, arguments: [], directives: []),
        GLField(name: "data".toToken(), type: dataType, arguments: [], directives: []),
      ], interfaceNames: {}, directives: [], derivedFromType: null, extension: false, isResponseType: true);
      result.addInterface(parser.interfaces["GraphLinkFullResponse"]!);
      result.addDirective(
          GLDirectiveValue(glInternal.toToken(), [], [], generated: true));
    }
    return result;
  }

  GLTypeDefinition getGeneratedTypeDefinition() {
    var gqDef = _glTypeDefinition;
    if (gqDef == null) {
      _glTypeDefinition = gqDef = GLTypeDefinition(
        name: tokenInfo.ofNewName(_getGeneratedTypeName()),
        nameDeclared: getNameValueFromDirectives(getDirectives()) != null,
        fields: _generateFields(),
        directives: getDirectives(),
        interfaceNames: {},
        derivedFromType: null,
        extension: false,
        isResponseType: true,
      );
      gqDef.addDirective(
          GLDirectiveValue(glInternal.toToken(), [], [], generated: true));
    }
    return gqDef;
  }

  void updateTypeDefinition(GLTypeDefinition def) {
    _glTypeDefinition = def;
  }

  GLTypeDefinition? get typeDefinition => _glTypeDefinition;

  String _getGeneratedTypeName() {
    return getNameValueFromDirectives(getDirectives()) ??
        "${tokenInfo.token.firstUp}Response";
  }

  String _fullResponseName() => "${tokenInfo.token.firstUp}FullResponse";

  List<GLField> _generateFields() {
    return elements
        .map(
          (e) => GLField(
            name: e.alias ?? e.tokenInfo,
            type: e.returnProjectedType,
            arguments: [],
            directives: e.getDirectives(),
          ),
        )
        .toList();
  }

  GLArgumentDefinition findByName(String name) =>
      arguments.where((arg) => arg.token == name).first;

  void applyDefaultCache(int defaultTTL) {
    if (type != GLQueryType.query) {
      throw ParseException("You cannot apply cache to ${type}",
          info: tokenInfo);
    }
    if (!hasDirective(glCache) && !hasDirective(glNoCache)) {
      addDirective(GLDirectiveValue.createDefaultCacheDirectiveValue(
          tokenInfo, defaultTTL));
    }
    for (final element in elements) {
      element.applyDefaultCache(defaultTTL);
    }
  }

  int get cacheTTL {
    var cache = getDirectiveByName(glCache);
    if (cache == null) {
      return 0;
    }
    return cache.getArgValue(glCacheTTL) as int? ?? 0;
  }

  List<String> get cacheTags {
    var cache = getDirectiveByName(glCache);
    if (cache == null) {
      return [];
    }
    return (cache.getArgValue(glCacheTagList) as List? ?? []).cast<String>();
  }

  List<String> get invalidateCacheTags {
    var cacheDir = getDirectiveByName(glCacheInvalidate);
    if (cacheDir == null) {
      return [];
    }
    return (cacheDir.getArgValue(glCacheTagList) as List? ?? []).cast<String>();
  }

  bool get cacheInvalidateAll {
    var cache = getDirectiveByName(glCacheInvalidate);
    if (cache == null) {
      return false;
    }
    return cache.getArgValueAsBool(glCacheArgAll);
  }
}
