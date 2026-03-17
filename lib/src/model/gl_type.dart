import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/token_info.dart';

class GLType extends GLToken {
  final bool nullable;

  GLType(super.tokenInfo, this.nullable);

  @override
  bool operator ==(Object other) {
    if (other is GLType) {
      return tokenInfo.token == other.tokenInfo.token && nullable == other.nullable;
    }
    return false;
  }

  GLType get inlineType => this;
  GLType get firstType => this;

  bool get isList => this is GLListType;

  bool get isNotList => !isList;

  @override
  int get hashCode => Object.hash(tokenInfo.token, nullable);

  GLType ofNewName(TokenInfo name) {
    return GLType(name, nullable);
  }
}

class GLListType extends GLType {
  ///this could be an instance of GQListType
  final GLType type;
  GLListType(this.type, bool nullable) : super(type.tokenInfo, nullable);

  @override
  GLType get inlineType => type;

  @override
  GLType ofNewName(TokenInfo name) {
    return GLListType(type.ofNewName(name), nullable);
  }

  ///
  /// a recursive way to find the first TYPE even if this is a list of list of list .... of list of TYPE
  ///
  @override
  GLType get firstType => type.firstType;

  @override
  int get hashCode => Object.hash(tokenInfo.token, type, nullable);

  @override
  bool operator ==(Object other) {
    if (other is GLListType) {
      return type == other.type && nullable == other.nullable;
    }
    return false;
  }
}
