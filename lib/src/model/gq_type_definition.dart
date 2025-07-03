import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_has_directives.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';

class GQTypeDefinition extends GQTokenWithFields with GqHasDirectives {
  final Set<String> interfaceNames;
  final List<GQDirectiveValue> directives;
  final bool nameDeclared;
  final GQTypeDefinition? derivedFromType;

  final Set<String> originalTokens = <String>{};

  ///
  /// Used only when generating type for interfaces.
  /// This will be a super class of one or more base types.
  ///
  final Set<GQTypeDefinition> subTypes = {};

  final _directiveValues = <String, GQDirectiveValue>{};

  GQTypeDefinition({
    required String name,
    required this.nameDeclared,
    required List<GQField> fields,
    required this.interfaceNames,
    required this.directives,
    required this.derivedFromType,
  }) : super(name, fields) {
    fields.sort((f1, f2) => f1.name.compareTo(f2.name));
    for (var d in directives) {
      _directiveValues.putIfAbsent(d.token, () => d);
    }
  }

  ///
  ///check is the two definitions will produce the same object structure
  ///
  bool isSimilarTo(GQTypeDefinition other) {
    var dft = derivedFromType;
    var otherDft = other.derivedFromType;
    if (otherDft != null) {
      if ((dft?.token ?? token) != otherDft.token) {
        return false;
      }
    }
    return getHash() == other.getHash();
  }

  String getHash() {
    return fields.map((f) => "${f.name}:${f.type.serializeForceNullable(f.hasInculeOrSkipDiretives)}").join(",");
  }

  Set<String> getIdentityFields(GQGrammar g) {
    var directive = _directiveValues[GQGrammar.gqEqualsHashcode];
    if (directive != null) {
      var directiveFields =
          ((directive.arguments.first.value as List)[1] as List)
              .map((e) => e as String)
              .map((e) => e.replaceAll('"', '').replaceAll("'", ""))
              .toSet();
      return directiveFields.where((e) => fieldNames.contains(e)).toSet();
    }
    return g.identityFields.where((e) => fieldNames.contains(e)).toSet();
  }



  

  @override
  String toString() {
    return 'GraphqlType{name: $token, fields: $fields, interfaceNames: $interfaceNames}';
  }

  List<GQField> getFields() {
    return [...fields];
  }

  String serializeContructorArgs(GQGrammar grammar) {
    if (fields.isEmpty) {
      return "";
    }
    String nonCommonFields = getFields().isEmpty
        ? ""
        : getFields()
            .map((e) => grammar.toConstructorDeclaration(e))
            .join(", ");
    var combined =
        [nonCommonFields].where((element) => element.isNotEmpty).toSet();
    if (combined.isEmpty) {
      return "";
    } else if (combined.length == 1) {
      return "{${combined.first}}";
    }
    return "{${[nonCommonFields].join(", ")}}";
  }

  @override
  String serialize() {
    throw UnimplementedError();
  }

  GQTypeDefinition clone(String newName) {
    return GQTypeDefinition(
      name: newName,
      nameDeclared: nameDeclared,
      fields: fields.toList(),
      interfaceNames: interfaceNames,
      directives: [],
      derivedFromType: derivedFromType,
    );
  }

  @override
  List<GQDirectiveValue> getDirectives() {
    return [...directives];
  }
}
