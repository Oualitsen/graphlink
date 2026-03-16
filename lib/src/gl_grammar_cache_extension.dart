import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_cache_definition.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_token.dart';

final _cacheTagRegExp = RegExp(r'^[a-zA-Z0-9_]+$');

extension GLGrammarCacheExtension on GLGrammar {
  ///
  ///glCache/glNoCache should not be applied to mutations or subscriptions
  ///
  void checkCacheOnMutationsAndSubscriptions() {
    queries.values.where((e) => e.type != GLQueryType.query).forEach((q) {
      _checkForCacheExistanceAndThrow(q);
      _checkCacheOnMutationsAndSubscriptionsElements(q.elements);
    });
  }

  void _checkCacheOnMutationsAndSubscriptionsElements(List<GLQueryElement> elements) {
    elements.forEach(_checkForCacheExistanceAndThrow);
  }

  void _checkForCacheExistanceAndThrow(GLDirectivesMixin e) {
    final token = e as GLToken;
    if (e.hasDirective(glCache)) {
      throw ParseException(
        "$glCache is not allowed on mutations or subscriptions — "
        "caching their response would silently skip writes or has no meaning on event streams.",
        info: token.tokenInfo,
      );
    }
    if (e.hasDirective(glNoCache)) {
      throw ParseException(
        "$glNoCache is not allowed on mutations or subscriptions — "
        "these operations are never cached.",
        info: token.tokenInfo,
      );
    }
  }

  ///
  /// checks all glCache directves
  /// ttl should not be null
  /// ttl should be an integer
  void checkGqCacheDirectives() {
    directiveValues.where((d) => d.token == glCache).forEach((directive) {
      // check TTL is not null
      var ttlObject = directive.getArgValue(glCacheTTL);
      if (ttlObject == null) {
        throw ParseException("${glCacheTTL} is required on $glCache directives",
            info: directive.tokenInfo);
      }
      if (ttlObject is! int || ttlObject < 0) {
        throw ParseException(
            "${glCacheTTL} on $glCache directives should be a positive integer! found: ${ttlObject}",
            info: directive.tokenInfo);
      }
      var tag = directive.getArgValueAsString(glCacheTag);
      if (tag != null) {
        if (!_cacheTagRegExp.hasMatch(tag)) {
          throw ParseException(
              "${glCacheTag} on $glCache directives should be alphanumeric with underscores only! found: $tag",
              info: directive.tokenInfo);
        }
      }
    });
  }

  ///
  /// The goal is check the existance of tags tageted by glCacheInvalidate directive
  ///

  void checkGqCacheTags() {
    final allTags = directiveValues
        .where((val) => val.token == glCache)
        .map((e) => e.getArgValueAsString(glCacheTag))
        .where((e) => e != null)
        .map((e) => e!)
        .toSet();
    directiveValues
        .where((d) => d.token == glCacheInvalidate)
        .where((e) => e.getArgValue(glCacheTagList) != null)
        .forEach((directive) {
      var tagList = (directive.getArgValue(glCacheTagList) as List).cast<String>();
      for (var tag in tagList) {
        if (!allTags.contains(tag)) {
          throw ParseException(
            "Tag \"$tag\" used in $glCacheInvalidate is not declared on any $glCache directive",
            info: directive.tokenInfo,
          );
        }
      }
    });
  }

  void checkGqCacheInvalidateDirectives() {
    directiveValues.where((d) => d.token == glCacheInvalidate).forEach((directive) {
      var all = directive.getArgValue(glCacheArgAll);
      var tags = directive.getArgValue(glCacheTagList);

      if (all != null && all is! bool) {
        throw ParseException(
          "$glCacheArgAll on $glCacheInvalidate must be a boolean! found: $all",
          info: directive.tokenInfo,
        );
      }

      if (tags != null && tags is! List) {
        throw ParseException(
          "$glCacheTagList on $glCacheInvalidate must be a list of strings! found: $tags",
          info: directive.tokenInfo,
        );
      }

      final allArg = all as bool?;
      final tagsList = tags as List?;

      if ((allArg == null || allArg == false) && (tagsList == null || tagsList.isEmpty)) {
        throw ParseException(
          "$glCacheInvalidate requires either $glCacheArgAll: true or a non-empty $glCacheTagList",
          info: directive.tokenInfo,
        );
      }
      if (tagsList != null && tagsList.isNotEmpty) {
        for (var i = 0; i < tagsList.length; i++) {
          var element = tagsList[i];
          if (element is! String) {
            throw ParseException(
              "$glCacheTagList on $glCacheInvalidate must contain only strings! found: $element",
              info: directive.tokenInfo,
            );
          }
          var trimmed = element.startsWith('"') && element.endsWith('"')
              ? element.substring(1, element.length - 1)
              : element;
          tagsList[i] = trimmed;
        }
      }
    });
  }

  ///
  ///Applies the default cache to all queries
  void applyDefaultCacheToQueries(int defaultTTL) {
    queries.values.where((q) => q.type == GLQueryType.query).forEach((query) {
      query.cacheDefinition = GLCacheDefinition(defaultTTL, null);
    });
  }

  ///
  ///applies cache to queries having glCache directive and override default
  void applyCachesToQueries() {
    queries.values.where((q) => q.type == GLQueryType.query).forEach((query) {
      if (query.hasDirective(glCache)) {
        query.cacheDefinition = fromDirective(query.getDirectiveByName(glCache)!);
      }
      _applyCacheToQueryElements(query);
    });
  }

  void _applyCacheToQueryElements(GLQueryDefinition def) {
    def.elements.where((e) => e.hasDirective(glCache)).forEach((e) {
      e.cacheDefinition = fromDirective(e.getDirectiveByName(glCache)!);
    });
  }

  GLCacheDefinition fromDirective(GLDirectiveValue val) {
    return GLCacheDefinition(
        val.getArgValue(glCacheTTL) as int, val.getArgValueAsString(glCacheTag));
  }

  /// removes default applied cache on queries having @glNoCache
  void applyNoCachesToQueries() {
    queries.values.where((q) => q.type == GLQueryType.query).forEach((query) {
      if (query.hasDirective(glNoCache)) {
        query.cacheDefinition = null;
      }
      _applyNoCachesToQuerieElements(query);
    });
  }

  void _applyNoCachesToQuerieElements(GLQueryDefinition def) {
    def.elements.where((e) => e.hasDirective(glNoCache)).forEach((e) {
      e.cacheDefinition = null;
    });
  }
}
