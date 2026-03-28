import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/token_info.dart';
import 'package:graphlink/src/serializers/graphq_serializer.dart';

class GLTypeDefinition extends GLTokenWithFields with GLDirectivesMixin {
  final Set<TokenInfo> _interfaceNames = {};
  final Set<GLInterfaceDefinition> _interfaces = {};
  final bool nameDeclared;
  final GLTypeDefinition? derivedFromType;

  final Set<String> _originalTokens = <String>{};

  GLTypeDefinition({
    required TokenInfo name,
    required this.nameDeclared,
    required List<GLField> fields,
    required Set<TokenInfo> interfaceNames,
    required List<GLDirectiveValue> directives,
    required this.derivedFromType,
    required bool extension,
    String? documentation,
  }) : super(name, extension, fields, documentation: documentation) {
    directives.forEach(addDirective);
    fields.sort((f1, f2) => f1.name.token.compareTo(f2.name.token));
    interfaceNames.forEach(addInterfaceName);
  }

  Set<GLInterfaceDefinition> get interfaces => Set.unmodifiable(_interfaces);
  Set<TokenInfo> get interfaceNames => Set.unmodifiable(_interfaceNames);
  Set<String> get originalTokens => Set.unmodifiable(_originalTokens);

  void addInterfaceName(TokenInfo token) {
    _interfaceNames.add(token);
  }

  void addInterface(GLInterfaceDefinition iface) {
    _interfaces.add(iface);
    addInterfaceName(iface.tokenInfo);
  }

  void addOriginalToken(String token) {
    _originalTokens.add(token);
  }

  ///
  ///check is the two definitions will produce the same object structure
  ///
  bool isSimilarTo(GLTypeDefinition other, GLParser g) {
    var dft = derivedFromType;
    var otherDft = other.derivedFromType;
    if (otherDft != null) {
      if ((dft?.tokenInfo ?? tokenInfo) != otherDft.tokenInfo) {
        return false;
      }
    }
    return getHash(g) == other.getHash(g);
  }

  bool implements(String interfaceName) {
    return _interfaceNames.where((i) => i.token == interfaceName).isNotEmpty;
  }

  String getHash(GLParser g) {
    var serilaize = GLGraphqSerializer(g);
    return getSerializableFields(g.mode)
        .map((f) =>
            "${f.name}:${serilaize.serializeType(f.type, forceNullable: f.hasInculeOrSkipDiretives)}")
        .join(",");
  }

  Set<String> getIdentityFields(GLParser g) {
    var directive = getDirectiveByName(glEqualsHashcode);
    if (directive != null) {
      var directiveFields = (directive.getArguments().first.value as List)
          .map((e) => e as String)
          .map((e) => e.replaceAll('"', '').replaceAll("'", ""))
          .toSet();
      return directiveFields.where((e) => fieldNames.contains(e)).toSet();
    }
    return g.identityFields.where((e) => fieldNames.contains(e)).toSet();
  }

  @override
  String toString() {
    return 'GraphqlType{name: $tokenInfo, fields: $fields, interfaceNames: $interfaceNames}';
  }

  List<GLField> getFields() {
    return [...fields];
  }

  bool containsInteface(String interfaceName) =>
      interfaceNames.where((e) => e.token == interfaceName).isNotEmpty;

  Set<String> getInterfaceNames() => interfaceNames.map((e) => e.token).toSet();

  @override
  Set<GLToken> getImportDependecies(GLParser g) {
    var result = {...super.getImportDependecies(g)};

    for (var iface in _interfaces) {
      var token = g.getTokenByKey(iface.token);
      if (filterDependecy(token, g)) {
        result.add(token!);
      }
    }
    return result;
  }

  @override
  void merge<T extends GLExtensibleToken>(T other) {
    if (other is GLTypeDefinition) {
      other.getDirectives().forEach(addDirective);
      other.fields.forEach(addOrMergeField);
    }
  }
}
