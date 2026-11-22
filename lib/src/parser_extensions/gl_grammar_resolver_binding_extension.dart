import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

enum GLResolverKind { query, mutation, subscription, typeField }

class GLResolverBinding {
  final GLResolverKind kind;
  final String wireName;

  const GLResolverBinding(this.kind, this.wireName);

  @override
  bool operator ==(Object other) => other is GLResolverBinding && other.kind == kind && other.wireName == wireName;

  @override
  int get hashCode => Object.hash(kind, wireName);
}

extension GLGrammarResolverBindingExtension on GLParser {
  GLResolverBinding rootResolverBinding(GLQueryType type, String fieldName) {
    if (type == GLQueryType.mutation) return GLResolverBinding(GLResolverKind.mutation, fieldName);
    if (type == GLQueryType.subscription) return GLResolverBinding(GLResolverKind.subscription, fieldName);
    return GLResolverBinding(GLResolverKind.query, fieldName);
  }

  GLResolverBinding typeFieldResolverBinding(String fieldName) => GLResolverBinding(GLResolverKind.typeField, fieldName);
}
