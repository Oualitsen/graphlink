import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/dart_serializable.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/utils.dart';

class GQTypeDefinition extends GQTokenWithFields implements DartSerializable {
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

  /// used to call super on
  final Set<GQField> _superFields = {};

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
  bool isSimilarTo(GQTypeDefinition other, GQGrammar g) {
    var dft = derivedFromType;
    var otherDft = other.derivedFromType;
    if (otherDft != null) {
      if ((dft?.token ?? token) != otherDft.token) {
        return false;
      }
    }
    return getHash(g) == other.getHash(g);
  }

  String getHash(GQGrammar grammar) {
    return serializeFields(grammar);
  }

  Set<String> getIdentityFields(GQGrammar g) {
    var directive = _directiveValues[GQGrammar.gqEqualsHashcode];
    if (directive != null) {
      var directiveFields = ((directive.arguments.first.value as List)[1] as List)
          .map((e) => e as String)
          .map((e) => e.replaceAll('"', '').replaceAll("'", ""))
          .toSet();
      return directiveFields.where((e) => fieldNames.contains(e)).toSet();
    }
    return g.identityFields.where((e) => fieldNames.contains(e)).toSet();
  }

  String generateEqualsAndHashCode(GQGrammar g) {
    var fieldsToInclude = getIdentityFields(g);
    if (fieldsToInclude.isNotEmpty) {
      return equalsHascodeCode(fieldsToInclude.toList());
    }
    return "";
  }

  String equalsHascodeCode(List<String> fields) {
    return """\n\n
    @override
    bool operator ==(Object other) {
      if (identical(this, other)) return true;

      return other is $token &&
          ${fields.map((e) => "$e == other.$e").join(" && ")};
    }

    @override
    int get hashCode => Object.hashAll([${fields.join(", ")}]);
  """;
  }

  @override
  String toString() {
    return 'GraphqlType{name: $token, fields: $fields, interfaceNames: $interfaceNames}';
  }

  @override
  String toDart(GQGrammar grammar) {
    return """
      @JsonSerializable(explicitToJson: true)
      class $token ${_serializeSuperClass()}{
        
          ${serializeListText(getFields().map((e) => e.toDart(grammar)).toList(), join: "\n\r          ", withParenthesis: false)}
          
          $token(${serializeContructorArgs(grammar)})${_serializeCallToSuper(grammar)};
          
          ${generateEqualsAndHashCode(grammar)}
          
          factory $token.fromJson(Map<String, dynamic> json) {
             ${_serializeFromJson()}
          }
          ${interfaceNames.isNotEmpty ? '\n${"\t" * 5}@override' : ''}
          Map<String, dynamic> toJson() {
            ${_serializeToJson()}
          }
      }
    """;
  }

  String _serializeFromJson() {
    if (subTypes.isEmpty) {
      return "return _\$${token}FromJson(json);";
    } else {
      return """
      var typename = json["__typename"];
      switch(typename) {
        
        ${subTypes.map((st) => "case \"${st.derivedFromType?.token ?? st.token}\": return _\$${st.token}FromJson(json);").join("\n        ")}
      }
      return _\$${token}FromJson(json);
    """;
    }
  }

  String _serializeToJson() {
    return "return _\$${token}ToJson(this);";
  }

  String _serializeCallToSuper(GQGrammar grammar) {
    if (_superFields.isEmpty) {
      return "";
    }
    return ": super(${serializeListText(
      _superFields.map((e) => "${e.name}: ${e.name}").toList(),
      withParenthesis: false,
    )})";
  }

  List<GQField> getFields() {
    return fields;
  }

  String _serializeSuperClass() {
    if (interfaceNames.isEmpty) {
      return '';
    }
    return "implements ${interfaceNames.join(", ")} ";
  }

  String serializeFields(GQGrammar grammar) {
    return serializeListText(fields.map((e) => e.createHash(grammar)).toList(),
        join: " ", withParenthesis: false);
  }

  String serializeContructorArgs(GQGrammar grammar) {
    if (fields.isEmpty && _superFields.isEmpty) {
      return "";
    }

    String commonFields =
        _superFields.isEmpty ? "" : _superFields.map((e) => e.toDartMethodDeclaration(grammar)).join(", ");
    String nonCommonFields =
        getFields().isEmpty ? "" : getFields().map((e) => grammar.toConstructorDeclaration(e)).join(", ");
    var combined = [nonCommonFields, commonFields].where((element) => element.isNotEmpty).toSet();
    if (combined.isEmpty) {
      return "";
    } else if (combined.length == 1) {
      return "{${combined.first}}";
    }
    return "{${[nonCommonFields, commonFields].join(", ")}}";
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
}
