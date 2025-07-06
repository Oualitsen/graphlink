import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';

mixin GqHasDirectives {
  List<GQDirectiveValue> getDirectives() {
    return [..._directives];
  }

  final List<GQDirectiveValue> _directives = [];

  final Map<String, GQDirectiveValue?> _cache = {};

  void addDirective(GQDirectiveValue directiveValue) {
    _directives.add(directiveValue);
  }

  List<GQDirectiveValue> findQueryDirectives() {
    return getDirectives().where((dir) {
      var isQuery = dir.getArgValue(gqQueryArg);
      return isQuery != null && isQuery is bool && isQuery;
    }).toList();
  }

  GQDirectiveValue? getDirectiveByName(String name) {
    var result = _cache[name];
    if (result == null && !_cache.containsKey(name)) {
      var directiveList = getDirectives().where((d) => d.token == name).toList();
      if (directiveList.isEmpty) {
        result = null;
      } else {
        result = directiveList.first;
      }
      _cache[name] = result;
    }
    return result;
  }
}
