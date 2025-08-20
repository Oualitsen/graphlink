import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_has_directives.dart';
import 'package:retrofit_graphql/src/model/gq_interface.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';
import 'package:retrofit_graphql/src/serializers/graphq_serializer.dart';

class GQTypeDefinition extends GQTokenWithFields with GqDirectivesMixin {
  final Set<TokenInfo> interfaceNames;
  final Set<GQInterfaceDefinition> interfaces = {};
  final bool nameDeclared;
  final GQTypeDefinition? derivedFromType;

  final Set<String> originalTokens = <String>{};

  ///
  /// Used only when generating type for interfaces.
  /// This will be a super class of one or more base types.
  ///
  final Set<GQTypeDefinition> implementations = {};

  GQTypeDefinition({
    required TokenInfo name,
    required this.nameDeclared,
    required List<GQField> fields,
    required this.interfaceNames,
    required List<GQDirectiveValue> directives,
    required this.derivedFromType,
  }) : super(name, fields) {
    directives.forEach(addDirective);
    fields.sort((f1, f2) => f1.name.token.compareTo(f2.name.token));
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
    return interfaceNames.where((i) => i.token == interfaceName).isNotEmpty;
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
}
