import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';

mixin GqHasDirectives {
  List<GQDirectiveValue> getDirectives() {
    return _directives.values.toList();
  }

  final Map<String, GQDirectiveValue> _directives = {};


  void addDirective(GQDirectiveValue directiveValue) {
    if (_directives.containsKey(directiveValue.token)) {
      throw ParseException("Directive '${directiveValue.token}' already exists");
    }
    _directives[directiveValue.token] = directiveValue;
  }

  void addDirectiveIfAbsent(GQDirectiveValue directiveValue) {
    _directives.putIfAbsent(directiveValue.token, () => directiveValue);
  }

  List<GQDirectiveValue> findQueryDirectives() {
    return getDirectives().where((dir) {
      var isQuery = dir.getArgValue(gqQueryArg);
      return isQuery != null && isQuery is bool && isQuery;
    }).toList();
  }

  GQDirectiveValue? getDirectiveByName(String name) {
    return _directives[name];
  }
}
