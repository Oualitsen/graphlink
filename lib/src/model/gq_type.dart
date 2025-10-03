import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';

class GQType extends GQToken {
  final bool nullable;

  ///
  ///used to check if the type is a scalar or an object
  ///This is mainly used for fragments and queries
  ///
  bool isScalar;

  GQType(super.tokenInfo, this.nullable, {this.isScalar = true});

  @override
  bool operator ==(Object other) {
    if (other is GQType) {
      return tokenInfo == other.tokenInfo && nullable == other.nullable;
    }
    return false;
  }

  GQType get inlineType => this;

  bool get isList => this is GQListType;

  bool get isNotList => !isList;

  @override
  int get hashCode => tokenInfo.hashCode;

  GQType ofNewName(TokenInfo name) {
    return GQType(name, nullable, isScalar: isScalar);
  }
}

class GQListType extends GQType {
  ///this could be an instance of GQListType
  final GQType type;
  GQListType(this.type, bool nullable) : super(type.tokenInfo, nullable, isScalar: false);

  @override
  GQType get inlineType => type;

  @override
  GQType ofNewName(TokenInfo name) {
    return GQListType(type.ofNewName(name), nullable);
  }
}
