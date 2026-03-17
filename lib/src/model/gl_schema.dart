import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/token_info.dart';

class GLSchema extends GLExtensibleToken with GLDirectivesMixin {
  final Map<GLQueryType, TokenInfo> _schemaMap = {};

  GLSchema(
    super.tokenInfo,
    super.extension, {
    required List<SchemaElement> operationTypes,
    required List<GLDirectiveValue> directives,
  }) {
    directives.forEach(addDirective);
    operationTypes.forEach(addSchemaElement);
  }

  void addSchemaElement(SchemaElement element) {
    if (_schemaMap.containsKey(element.type)) {
      throw ParseException("Schema already contains a definition for ${element.type}", info: element.name);
    }
    _schemaMap[element.type] = element.name;
  }

  String getByQueryType(GLQueryType type) {
    switch (type) {
      case GLQueryType.query:
        return _schemaMap[type]?.token ?? "Query";
      case GLQueryType.mutation:
        return _schemaMap[type]?.token ?? "Mutation";
      case GLQueryType.subscription:
        return _schemaMap[type]?.token ?? "Subscription";
    }
  }

  @override
  void merge<T extends GLExtensibleToken>(T other) {
    if (other is GLSchema) {
      other.getDirectives().forEach(addDirective);
      other._schemaMap.forEach((key, value) {
        addSchemaElement(SchemaElement(key, value));
      });
    }
  }
}

class SchemaElement {
  final GLQueryType type;
  final TokenInfo name;
  SchemaElement(this.type, this.name);
}
