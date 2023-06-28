import 'package:retrofit_graphql/graphql_parser/model/gq_token.dart';

class GQType extends GQToken {
  final bool nullable;

  ///
  ///used to check if the type is a scalar or an object
  ///This is mainly used for fragments and queries
  ///
  bool isScalar;

  GQType(super.name, this.nullable, {this.isScalar = true});

  @override
  String toString() {
    return serialize();
  }

  String toDartType(Map<String, String> typeMapping, bool forceNullable) {
    var dartTpe = typeMapping[token] ?? token;
    if (forceNullable) {
      return "$dartTpe?";
    }
    return "$dartTpe$nullableTextDart";
  }

  @override
  String serialize() {
    return "$token$nullableText";
  }

  String get nullableText => nullable ? "" : "!";
  String get nullableTextDart => nullable ? "?" : "";

  GQType get inlineType => this;
}

class GQListType extends GQType {
  ///this could be an instance of GQListType
  final GQType type;
  GQListType(this.type, bool nullable)
      : super("#List[${type.serialize()}]", nullable, isScalar: false);

  @override
  String serialize() {
    return "[${type.serialize()}]$nullableText";
  }

  @override
  String toString() {
    return serialize();
  }

  @override
  String toDartType(Map<String, String> typeMapping, bool forceNullable) {
    if (forceNullable) {
      return "List<${type.toDartType(typeMapping, false)}>?";
    }
    return "List<${type.toDartType(typeMapping, false)}>$nullableTextDart";
  }

  @override
  GQType get inlineType => type.inlineType;
}
