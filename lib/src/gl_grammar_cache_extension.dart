import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_token.dart';

final _cacheTagRegExp = RegExp(r'^[a-zA-Z0-9_]+$');

extension GLGrammarCacheExtension on GLParser {
  ///
  ///glCache/glNoCache should not be applied to mutations or subscriptions
  ///
  void checkCacheOnMutationsAndSubscriptions() {
    queries.values.where((e) => e.type != GLQueryType.query).forEach((q) {
      _checkForCacheExistanceAndThrow(q);
      _checkCacheOnMutationsAndSubscriptionsElements(q.elements);
    });
  }

  void checkCacheAndNoCacheConflict() {
    queries.values.where((q) => q.type == GLQueryType.query).forEach((q) {
      _checkForCacheAndNoCacheConflict(q);
      q.elements.forEach(_checkForCacheAndNoCacheConflict);
    });
  }

  void _checkForCacheAndNoCacheConflict(GLDirectivesMixin e) {
    if (e.hasDirective(glCache) && e.hasDirective(glNoCache)) {
      final token = e as GLToken;
      throw ParseException(
        "$glCache AND $glNoCache on the same query? Incredible. You're the human equivalent of a merge conflict.",
        info: token.tokenInfo,
      );
    }
  }

  void checkCacheInvalidateOnQueriesAndSubscriptions() {
    queries.values.where((e) => e.type != GLQueryType.mutation).forEach((q) {
      _checkForCacheInvalidateExistanceAndThrow(q);
      _checkInvalidateCacheOnMutationsAndSubscriptionsElements(q.elements);
    });
  }

  void _checkInvalidateCacheOnMutationsAndSubscriptionsElements(
      List<GLQueryElement> elements) {
    elements.forEach(_checkForCacheInvalidateExistanceAndThrow);
  }

  void _checkCacheOnMutationsAndSubscriptionsElements(
      List<GLQueryElement> elements) {
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

  void _checkForCacheInvalidateExistanceAndThrow(GLDirectivesMixin e) {
    final token = e as GLToken;
    if (e.hasDirective(glCacheInvalidate)) {
      throw ParseException(
        "$glCacheInvalidate is not allowed on queries or subscriptions",
        info: token.tokenInfo,
      );
    }
  }

  void fixTagListValues() {
    for (var directive in directiveValues) {
      _stripTagQuotes(directive);
    }
  }

  void validateTagValues() {
    for (var directive in directiveValues) {
      _validateTagValues(directive);
    }
  }

  void _stripTagQuotes(GLDirectiveValue? value) {
    if (value == null) return;
    var tags = value.getArgValue(glCacheTagList);
    if (tags == null || tags is! List) return;
    for (var i = 0; i < tags.length; i++) {
      var tag = tags[i];
      if (tag is String && tag.startsWith('"') && tag.endsWith('"')) {
        tags[i] = tag.substring(1, tag.length - 1);
      }
    }
  }

  void _validateTagValues(GLDirectiveValue? value) {
    if (value == null) return;
    var tags = value.getArgValue(glCacheTagList);
    if (tags == null || tags is! List) return;
    for (var tag in tags) {
      if (tag is! String) {
        throw ParseException(
          "$glCacheTagList on ${value.token} must contain only strings! found: $tag",
          info: value.tokenInfo,
        );
      }
      if (!_cacheTagRegExp.hasMatch(tag)) {
        throw ParseException(
          "tag on ${value.token} directives should be alphanumeric with underscores only! found: $tag",
          info: value.tokenInfo,
        );
      }
    }
  }

  ///
  /// checks all glCache directves
  /// ttl should not be null
  /// ttl should be an integer
  void checkGLCacheDirectives() {
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
      final staleIfOffline = directive.getArgValue(glCacheArgStaleIfOffline);
      if (staleIfOffline != null && staleIfOffline is! bool) {
        throw ParseException(
          "$glCacheArgStaleIfOffline on $glCache must be a boolean! found: $staleIfOffline",
          info: directive.tokenInfo,
        );
      }
    });
  }

  ///
  /// The goal is check the existance of tags tageted by glCacheInvalidate directive
  ///

  void checkGLCacheTags() {
    final allTags = getAllCacheTags();
    directiveValues
        .where((d) => d.token == glCacheInvalidate)
        .where((e) => e.getArgValue(glCacheTagList) != null)
        .forEach((directive) {
      var tagList =
          (directive.getArgValue(glCacheTagList) as List).cast<String>();
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

  void checkGLCacheInvalidateDirectives() {
    directiveValues
        .where((d) => d.token == glCacheInvalidate)
        .forEach((directive) {
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

      if ((allArg == null || allArg == false) &&
          (tagsList == null || tagsList.isEmpty)) {
        throw ParseException(
          "$glCacheInvalidate requires either $glCacheArgAll: true or a non-empty $glCacheTagList",
          info: directive.tokenInfo,
        );
      }
    });
  }

  ///
  ///Applies the default cache to all queries
  void applyDefaultCacheToQueries(int defaultTTL) {
    queries.values.where((q) => q.type == GLQueryType.query).forEach((query) {
      query.applyDefaultCache(defaultTTL);
    });
  }

  void propagateCacheTags() {
    queries.values
        .where((q) => q.type == GLQueryType.query)
        .where((q) => q.hasDirective(glCache))
        .forEach((q) {
      final cache = q.getDirectiveByName(glCache)!;
      final ttl = cache.getArgValue(glCacheTTL) as int;
      final tags =
          (cache.getArgValue(glCacheTagList) as List? ?? []).cast<String>();
      for (final elm in q.elements) {
        elm.propagateCache(ttl, tags);
      }
    });
  }

  void propagateInvalidateCacheTags() {
    queries.values
        .where((q) => q.type == GLQueryType.mutation)
        .where((q) => q.hasDirective(glCacheInvalidate))
        .forEach((q) {
      final cache = q.getDirectiveByName(glCacheInvalidate)!;
      final tags =
          (cache.getArgValue(glCacheTagList) as List? ?? []).cast<String>();
      final invalidateAll = cache.getArgValueAsBool(glCacheArgAll);
      for (final elm in q.elements) {
        elm.propagateInvalidateCache(invalidateAll, tags);
      }
    });
  }

  Set<String> getAllCacheTags() {
    return directiveValues
        .where((val) => val.token == glCache)
        .map((e) => e.getArgValue(glCacheTagList))
        .where((e) => e != null)
        .map((e) => e!)
        .expand((e) => (e as List).cast<String>())
        .toSet();
  }
}
