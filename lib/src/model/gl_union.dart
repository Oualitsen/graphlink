import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/code_name_mixin.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/token_info.dart';

class GLUnionDefinition extends GLExtensibleToken with GLDirectivesMixin, CodeNameMixin {
  @override
  String get wireName => token;
  final Map<String, TokenInfo> _typeNames = {};
  GLUnionDefinition(super.name, super.extension, List<TokenInfo> typeNames, List<GLDirectiveValue> directives, {super.documentation}) {
    typeNames.forEach(addTypeName);
    directives.forEach(addDirective);
  }

  void addTypeName(TokenInfo info) {
    if (_typeNames.containsKey(info.token)) {
      throw ParseException("${info} already declared for union ${token}");
    }
    _typeNames[info.token] = info;
  }

  List<TokenInfo> get typeNames => _typeNames.values.toList();

  @override
  void merge<T extends GLExtensibleToken>(T other) {
    if (other is GLUnionDefinition) {
      other.typeNames.forEach(addTypeName);
      other.getDirectives().forEach(addDirective);
    }
  }
}
