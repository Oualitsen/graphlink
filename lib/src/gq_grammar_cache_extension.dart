import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/gq_grammar.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gq_cache_definition.dart';
import 'package:graphlink/src/model/gq_directive.dart';
import 'package:graphlink/src/model/gq_queries.dart';

final _cacheTagRegExp = RegExp(r'^[a-zA-Z0-9_]+$');

extension GQGrammarCacheExtension on GQGrammar {
  ///
  /// checks all gqCache directves
  /// ttl should not be null
  /// ttl should be an integer
  void checkGqCacheDirectives() {
    directiveValues.where((d) => d.token == gqCache).forEach((directive) {
      // check TTL is not null
      var ttlObject = directive.getArgValue(gqCacheTTL);
      if (ttlObject == null) {
        throw ParseException("${gqCacheTTL} is required on $gqCache directives",
            info: directive.tokenInfo);
      }
      if (ttlObject is! int || ttlObject < 0) {
        throw ParseException(
            "${gqCacheTTL} on $gqCache directives should be a positive integer! found: ${ttlObject}",
            info: directive.tokenInfo);
      }
      var tag = directive.getArgValueAsString(gqCacheTag);
      if (tag != null) {
        if (!_cacheTagRegExp.hasMatch(tag)) {
          throw ParseException(
              "${gqCacheTag} on $gqCache directives should be alphanumeric with underscores only! found: $tag",
              info: directive.tokenInfo);
        }
      }
    });
  }

  ///
  ///Applies the default cache to all queries
  void applyDefaultCacheToQueries(int defaultTTL) {
    queries.values.where((q) => q.type == GQQueryType.query).forEach((query) {
      query.cacheDefinition = GqCacheDefinition(defaultTTL, null);
    });
  }

  ///
  ///applies cache to queries having gqCache directive and override default
  void applyCachesToQueries() {
    queries.values.where((q) => q.type == GQQueryType.query).forEach((query) {
      if (query.hasDirective(gqCache)) {
        query.cacheDefinition = fromDirective(query.getDirectiveByName(gqCache)!);
      }
      _applyCacheToQueryElements(query);
    });
  }

  void _applyCacheToQueryElements(GQQueryDefinition def) {
    def.elements.where((e) => e.hasDirective(gqCache)).forEach((e) {
      e.cacheDefinition = fromDirective(e.getDirectiveByName(gqCache)!);
    });
  }

  GqCacheDefinition fromDirective(GQDirectiveValue val) {
    return GqCacheDefinition(
        val.getArgValue(gqCacheTTL) as int, val.getArgValueAsString(gqCacheTag));
  }

  /// removes default applied cache on queries having @gqNoCache
  void applyNoCachesToQueries() {
    queries.values.where((q) => q.type == GQQueryType.query).forEach((query) {
      if (query.hasDirective(gqNoCache)) {
        query.cacheDefinition = null;
      }
      _applyNoCachesToQuerieElements(query);
    });
  }

  void _applyNoCachesToQuerieElements(GQQueryDefinition def) {
    def.elements.where((e) => e.hasDirective(gqNoCache)).forEach((e) {
      e.cacheDefinition = null;
    });
  }
}
