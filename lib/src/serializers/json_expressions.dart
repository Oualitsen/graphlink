import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/parser_extensions/gl_validation_extension.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';

/// The one place that decides how a value of a GraphQL type is turned into JSON and back.
///
/// The walk is the same in every language and respects nullability at every level:
/// list, then scalar codec, then enum, then type/input/interface/union (their own
/// `toJson`/`fromJson`), then the plain scalar. A language only supplies the leaves.
mixin JsonExpressions on GLSerializer {
  @override
  String toJsonExpr(GLType type, String value, {int depth = 0, GLImportSink? context}) {
    if (type is GLListType) {
      final element = elementVariable(depth);
      final body = toJsonExpr(type.inlineType, element, depth: depth + 1, context: context);
      return listToJson(type, value, element, body, context);
    }
    final codec = toJsonCodecOf(type);
    if (codec != null) return scalarToJson(codec, value, nullable: type.nullable);
    if (grammar.isEnum(type.token) || grammar.isProjectableType(type.token)) return modelToJson(type, value);
    return value;
  }

  @override
  String fromJsonExpr(GLType type, String json, {int depth = 0, GLImportSink? context}) {
    if (type is GLListType) {
      final element = elementVariable(depth);
      final body = fromJsonExpr(type.inlineType, element, depth: depth + 1, context: context);
      return listFromJson(type, json, element, body, context);
    }
    final codec = fromJsonCodecOf(type);
    if (codec != null) return scalarFromJson(codec, json, nullable: type.nullable);
    if (grammar.isEnum(type.token)) return enumFromJson(type, json);
    if (grammar.isProjectableType(type.token)) return modelFromJson(type, json);
    return plainFromJson(type, json);
  }

  String elementVariable(int depth) => 'e$depth';

  /// [body] is the conversion of one element, written in terms of [element]; it equals
  /// [element] when elements need no conversion.
  String listToJson(GLType list, String value, String element, String body, GLImportSink? context);

  /// [body] is the conversion of one element, written in terms of [element].
  String listFromJson(GLType list, String json, String element, String body, GLImportSink? context);

  /// An enum, or a type/input/interface/union, to its JSON form through its own `toJson`.
  String modelToJson(GLType type, String value);

  String enumFromJson(GLType type, String json);

  /// A type/input/interface/union from its JSON form through its own `fromJson`.
  String modelFromJson(GLType type, String json);

  /// A scalar without a codec: the cast or number coercion the language needs.
  String plainFromJson(GLType type, String json);
}
