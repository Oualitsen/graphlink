import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_queries.dart';

class GQService {
  final Map<String, _FieldWithType> _methods = {};
  final String name;

  GQService({required this.name});

  void addMethod(GQField method, GQQueryType type) {
    if (_methods.containsKey(method.name)) {
      throw ParseException("Service $name already contains method ${method.name}");
    }
    _methods[method.name] = _FieldWithType(field: method, type: type);
  }

  GQField? getMethod(String name) {
    return _methods[name]?.field;
  }

  GQQueryType? getMethodType(String name) {
    return _methods[name]?.type;
  }

  List<String> getMethodNames() {
    var methods = _methods.keys.toList();
    methods.sort();
    return methods;
  }
}

class _FieldWithType {
  final GQField field;
  final GQQueryType type;
  _FieldWithType({required this.field, required this.type});
}
