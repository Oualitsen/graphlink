import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';

class GQType extends GQToken {
  final bool nullable;

  ///
  ///used to check if the type is a scalar or an object
  ///This is mainly used for fragments and queries
  ///
  bool isScalar;

  GQType(super.name, this.nullable, {this.isScalar = true});

  @override
  bool operator ==(Object other) {
    if (other is GQType) {
      return token == other.token && nullable == other.nullable;
    }
    return false;
  }

  @override
  String toString() {
    return serialize();
  }

  String toDartType(GQGrammar grammar, bool forceNullable) {
    var dartTpe =
        grammar.typeMap[token] ?? grammar.projectedTypes[token]?.token ?? token;
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

  @override
  int get hashCode => token.hashCode;
}

class GQListType extends GQType {
  ///this could be an instance of GQListType
  final GQType type;
  GQListType(this.type, bool nullable)
      : super(type.token, nullable, isScalar: false);

  @override
  String serialize() {
    return "[${type.serialize()}]$nullableText";
  }

  @override
  String toString() {
    return serialize();
  }

  @override
  String toDartType(GQGrammar grammar, bool forceNullable) {
    if (forceNullable) {
      return "List<${type.toDartType(grammar, false)}>?";
    }
    return "List<${type.toDartType(grammar, false)}>$nullableTextDart";
  }

  @override
  GQType get inlineType => type.inlineType;
}
