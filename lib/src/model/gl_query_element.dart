import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_fragment.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/token_info.dart';

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

  Set<GLFragmentDefinitionBase> getFragmentsAndDependecies(GLParser g) {
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
    var set1 = block.projections.values
        .where((element) => element.isFragmentReference)
        .map((e) => e.fragmentName!)
        .toSet();
    var set2 = block.projections.values
        .where(
            (element) => !element.isFragmentReference && element.block != null)
        .map((e) => e.block!)
        .expand((element) => _getFragmentNamesByBlock(element))
        .toSet();
    return {...set1, ...set2};
  }

  GLType _getReturnProjectedType(
      GLTypeDefinition? projectedType, GLType returnType) {
    if (projectedType == null) {
      return returnType;
    } else {
      if (returnType is GLListType) {
        return GLListType(
            _getReturnProjectedType(projectedType, returnType.type),
            returnType.nullable);
      } else {
        return GLType(projectedType.tokenInfo, returnType.nullable);
      }
    }
  }

  GLType get returnProjectedType =>
      _getReturnProjectedType(projectedType, returnType);

  GLQueryElement(super.tokenInfo, List<GLDirectiveValue> directives, this.block,
      this.arguments, this.alias) {
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
      addDirective(GLDirectiveValue.createDefaultCacheDirectiveValue(
          tokenInfo, defaultTTL));
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
      addDirective(GLDirectiveValue.createInvalidateCacheDirective(
          tokenInfo, invalidateAll, tags));
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
