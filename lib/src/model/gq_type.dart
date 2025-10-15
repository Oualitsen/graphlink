import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';

class GQType extends GQToken {
  final bool nullable;

  GQType(super.tokenInfo, this.nullable);

  @override
  bool operator ==(Object other) {
    if (other is GQType) {
      return tokenInfo == other.tokenInfo && nullable == other.nullable;
    }
    return false;
  }

  GQType get inlineType => this;
  GQType get firstType => this;

  bool get isList => this is GQListType;

  bool get isNotList => !isList;

  @override
  int get hashCode => tokenInfo.hashCode;

  GQType ofNewName(TokenInfo name) {
    return GQType(name, nullable);
  }
}

class GQListType extends GQType {
  ///this could be an instance of GQListType
  final GQType type;
  GQListType(this.type, bool nullable) : super(type.tokenInfo, nullable);

  @override
  GQType get inlineType => type;

  @override
  GQType ofNewName(TokenInfo name) {
    return GQListType(type.ofNewName(name), nullable);
  }

  ///
  /// a recursive way to find the first TYPE even if this is a list of list of list .... of list of TYPE
  ///
  @override
  GQType get firstType => type.firstType;
}
