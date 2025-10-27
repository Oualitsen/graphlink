import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_directives_mixin.dart';
import 'package:retrofit_graphql/src/model/gq_interface_definition.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/gq_token_with_fields.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';
import 'package:retrofit_graphql/src/serializers/graphq_serializer.dart';

class GQTypeDefinition extends GQTokenWithFields with GQDirectivesMixin {
  final Set<TokenInfo> _interfaceNames = {};
  final Set<GQInterfaceDefinition> _interfaces = {};
  final bool nameDeclared;
  final GQTypeDefinition? derivedFromType;

  final Set<String> _originalTokens = <String>{};

  GQTypeDefinition({
    required TokenInfo name,
    required this.nameDeclared,
    required List<GQField> fields,
    required Set<TokenInfo> interfaceNames,
    required List<GQDirectiveValue> directives,
    required this.derivedFromType,
  }) : super(name, fields) {
    directives.forEach(addDirective);
    fields.sort((f1, f2) => f1.name.token.compareTo(f2.name.token));
    interfaceNames.forEach(addInterfaceName);
  }

  Set<GQInterfaceDefinition> get interfaces => Set.unmodifiable(_interfaces);
  Set<TokenInfo> get interfaceNames => Set.unmodifiable(_interfaceNames);
  Set<String> get originalTokens => Set.unmodifiable(_originalTokens);

  void addInterfaceName(TokenInfo token) {
    _interfaceNames.add(token);
  }

  void addInterface(GQInterfaceDefinition iface) {
    _interfaces.add(iface);
    addInterfaceName(iface.tokenInfo);
  }

  void addOriginalToken(String token) {
    _originalTokens.add(token);
  }

  ///
  ///check is the two definitions will produce the same object structure
  ///
  bool isSimilarTo(GQTypeDefinition other, GQGrammar g) {
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

  String getHash(GQGrammar g) {
    var serilaize = GraphqSerializer(g);
    return getSerializableFields(g.mode)
        .map((f) => "${f.name}:${serilaize.serializeType(f.type, forceNullable: f.hasInculeOrSkipDiretives)}")
        .join(",");
  }

  Set<String> getIdentityFields(GQGrammar g) {
    var directive = getDirectiveByName(gqEqualsHashcode);
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

  List<GQField> getFields() {
    return [...fields];
  }

  bool containsInteface(String interfaceName) => interfaceNames.where((e) => e.token == interfaceName).isNotEmpty;

  Set<String> getInterfaceNames() => interfaceNames.map((e) => e.token).toSet();

  @override
  Set<GQToken> getImportDependecies(GQGrammar g) {
    var result = {...super.getImportDependecies(g)};

    for (var iface in _interfaces) {
      var token = g.getTokenByKey(iface.token);
      if (filterDependecy(token, g)) {
        result.add(token!);
      }
    }
    return result;
  }
}
