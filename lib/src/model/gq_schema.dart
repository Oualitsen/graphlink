import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_directives_mixin.dart';
import 'package:retrofit_graphql/src/model/gq_queries.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';

class GQSchema extends GQExtensibleToken with GQDirectivesMixin {
  final Map<GQQueryType, TokenInfo> _schemaMap = {};

  GQSchema(
    super.tokenInfo,
    super.extension, {
    required List<SchemaElement> operationTypes,
    required List<GQDirectiveValue> directives,
  }) {
    directives.forEach(addDirective);
    operationTypes.forEach(addSchemaElement);
  }

  void addSchemaElement(SchemaElement element) {
    if (_schemaMap.containsKey(element.type)) {
      throw ParseException("Schema already contains a definition for ${element.type}",
          info: element.name);
    }
    _schemaMap[element.type] = element.name;
  }

  String getByQueryType(GQQueryType type) {
    switch (type) {
      case GQQueryType.query:
        return _schemaMap[type]?.token ?? "Query";
      case GQQueryType.mutation:
        return _schemaMap[type]?.token ?? "Mutation";
      case GQQueryType.subscription:
        return _schemaMap[type]?.token ?? "Subscription";
    }
  }

  @override
  void merge<T extends GQExtensibleToken>(T other) {
    if (other is GQSchema) {
      other.getDirectives().forEach(addDirective);
      other._schemaMap.forEach((key, value) {
        addSchemaElement(SchemaElement(key, value));
      });
    }
  }
}

class SchemaElement {
  final GQQueryType type;
  final TokenInfo name;
  SchemaElement(this.type, this.name);
}
