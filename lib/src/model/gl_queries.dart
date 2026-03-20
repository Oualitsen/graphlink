import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_fragment.dart';
import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/token_info.dart';
import 'package:graphlink/src/utils.dart';

enum GLQueryType { query, mutation, subscription }

class GLQueryDefinition extends GLToken with GLDirectivesMixin {
  final List<GLArgumentDefinition> arguments;
  final List<GLQueryElement> elements;
  final GLQueryType type; //query|mutation|subscription
  Set<GLFragmentDefinitionBase>? _allFrags;

  GLTypeDefinition? _gqTypeDefinition;

  Set<String> get fragmentNames {
    return elements.expand((e) => e.fragmentNames).toSet();
  }

  Set<GLFragmentDefinitionBase> fragments(GLGrammar g) {
    if (_allFrags == null) {
      var frags = fragmentNames.map((e) => g.getFragmentByName(e)).where((e) => e != null).map((e) => e!).toSet();
      _allFrags = {...frags, ...frags.expand((e) => e.dependecies)};
    }
    return _allFrags!;
  }

  GLQueryDefinition(super.tokenInfo, List<GLDirectiveValue> directives, this.arguments, this.elements, this.type) {
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
          throw ParseException("Argument ${arg.value} was not declared", info: arg.tokenInfo);
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

  GLTypeDefinition getGeneratedTypeDefinition() {
    var gqDef = _gqTypeDefinition;
    if (gqDef == null) {
      _gqTypeDefinition = gqDef = GLTypeDefinition(
        name: tokenInfo.ofNewName(_getGeneratedTypeName()),
        nameDeclared: getNameValueFromDirectives(getDirectives()) != null,
        fields: _generateFields(),
        directives: getDirectives(),
        interfaceNames: {},
        derivedFromType: null,
        extension: false,
      );
      gqDef.addDirective(GLDirectiveValue(glInternal.toToken(), [], [], generated: true));
    }
    return gqDef;
  }

  void updateTypeDefinition(GLTypeDefinition def) {
    _gqTypeDefinition = def;
  }

  GLTypeDefinition? get typeDefinition => _gqTypeDefinition;

  String _getGeneratedTypeName() {
    return getNameValueFromDirectives(getDirectives()) ?? "${tokenInfo.token.firstUp}Response";
  }

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

  GLArgumentDefinition findByName(String name) => arguments.where((arg) => arg.token == name).first;

  void applyDefaultCache(int defaultTTL) {
    if (type != GLQueryType.query) {
      throw ParseException("You cannot apply cache to ${type}", info: tokenInfo);
    }
    if (!hasDirective(glCache) && !hasDirective(glNoCache)) {
      addDirective(GLDirectiveValue.createDefaultCacheDirectiveValue(tokenInfo, defaultTTL));
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

class GLQueryElement extends GLToken with GLDirectivesMixin {
  final GLFragmentBlockDefinition? block;

  final List<GLArgumentValue> arguments;
  final TokenInfo? alias;

  ///
  ///This is unknown on parse time. It is filled on run time.
  ///
  late final GLType returnType;

  ///
  ///This is unknown on parse time. It is filled on run time.
  ///
  GLTypeDefinition? projectedType;

  String? projectedTypeKey;

  Set<String> get fragmentNames {
    if (block == null) {
      return {};
    }
    return _getFragmentNamesByBlock(block!);
  }

  Set<GLFragmentDefinitionBase> getFragmentsAndDependecies(GLGrammar g) {
    var frags = fragmentNames.map((e) => g.getFragmentByName(e)!).toSet();
    return {...frags, ...frags.expand((e) => e.dependecies)};
  }

  List<String> get cacheTags {
    var cacheDir = getDirectiveByName(glCache);
    if (cacheDir == null) {
      return [];
    }
    return (cacheDir.getArgValue(glCacheTagList) as List? ?? []).cast<String>();
  }

  List<String> get invalidateCacheTags {
    var cacheDir = getDirectiveByName(glCacheInvalidate);
    if (cacheDir == null) {
      return [];
    }
    return (cacheDir.getArgValue(glCacheTagList) as List? ?? []).cast<String>();
  }

  int get cacheTTL {
    var cacheDir = getDirectiveByName(glCache);
    if (cacheDir == null) {
      return 0;
    }
    return (cacheDir.getArgValue(glCacheTTL) as int?) ?? 0;
  }

  Set<String> _getFragmentNamesByBlock(GLFragmentBlockDefinition block) {
    var set1 =
        block.projections.values.where((element) => element.isFragmentReference).map((e) => e.fragmentName!).toSet();
    var set2 = block.projections.values
        .where((element) => !element.isFragmentReference && element.block != null)
        .map((e) => e.block!)
        .expand((element) => _getFragmentNamesByBlock(element))
        .toSet();
    return {...set1, ...set2};
  }

  GLType _getReturnProjectedType(GLTypeDefinition? projectedType, GLType returnType) {
    if (projectedType == null) {
      return returnType;
    } else {
      if (returnType is GLListType) {
        return GLListType(_getReturnProjectedType(projectedType, returnType.type), returnType.nullable);
      } else {
        return GLType(projectedType.tokenInfo, returnType.nullable);
      }
    }
  }

  GLType get returnProjectedType => _getReturnProjectedType(projectedType, returnType);

  GLQueryElement(super.tokenInfo, List<GLDirectiveValue> directives, this.block, this.arguments, this.alias) {
    directives.forEach(addDirective);
  }

  String get escapedToken {
    var aliasText = alias == null ? '' : "$alias:";
    return "$aliasText$tokenInfo".replaceFirst("\$", "\\\$");
  }

  String get nonEscapedToken {
    var aliasText = alias == null ? '' : "$alias:";
    return "$aliasText$tokenInfo";
  }

  void applyDefaultCache(int defaultTTL) {
    if (!hasDirective(glCache) && !hasDirective(glNoCache)) {
      addDirective(GLDirectiveValue.createDefaultCacheDirectiveValue(tokenInfo, defaultTTL));
    }
  }

  void propagateCache(int ttl, List<String> tags) {
    if (hasDirective(glNoCache)) {
      return;
    }
    if (!hasDirective(glCache)) {
      addDirective(GLDirectiveValue.createCacheDirective(tokenInfo, ttl, tags));
    } else {
      // union of tags
      var cache = getDirectiveByName(glCache)!;
      var newTags = {...cacheTags, ...tags}.toList();
      cache.addArg(glCacheTagList, newTags);
    }
  }

  void propagateInvalidateCache(bool invalidateAll, List<String> tags) {
    if (!hasDirective(glCacheInvalidate)) {
      addDirective(GLDirectiveValue.createInvalidateCacheDirective(tokenInfo, invalidateAll, tags));
    } else {
      // union of tags
      var cache = getDirectiveByName(glCacheInvalidate)!;
      if (cache.getArgValueAsBool(glCacheArgAll)) {
        // no need to add the tags as the invalidation will be on the whole cache
        return;
      }
      if (invalidateAll) {
        cache.addArg(glCacheArgAll, invalidateAll);
        // reset tags
        cache.addArg(glCacheTagList, []);
        return;
      }
      var newTags = {...invalidateCacheTags, ...tags}.toList();
      cache.addArg(glCacheTagList, newTags);
    }
  }

  bool get cacheInvalidateAll {
    var cache = getDirectiveByName(glCacheInvalidate);
    if (cache == null) {
      return false;
    }
    return cache.getArgValueAsBool(glCacheArgAll);
  }
}
