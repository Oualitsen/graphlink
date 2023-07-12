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
  GQTypeDefinition? superClass;

  ///
  /// Used only when generating type for interfaces.
  /// This will be a super class of one or more base types.
  ///
  final Set<GQTypeDefinition> subTypes = {};

  /// used to call super on
  final Set<GQField> _superFields = {};

  //common fields from subTypes
  final Set<GQField> _commonFields = {};

  bool _fiedsUpdated = false;

  String? _hash;

  GQTypeDefinition({
    required String name,
    required this.nameDeclared,
    required List<GQField> fields,
    required this.interfaceNames,
    required this.directives,
    required this.derivedFromType,
  }) : super(name, fields) {
    fields.sort((f1, f2) => f1.name.compareTo(f2.name));
  }

  ///
  ///check is the two definitions will produce the same object structure
  ///
  bool isSimilarTo(GQTypeDefinition other, GQGrammar g) {
    return getHash(g) == other.getHash(g);
  }

  String getHash(GQGrammar grammar) {
    _hash ??= serializeFields(grammar);
    return _hash!;
  }

  @override
  String toString() {
    return 'GraphqlType{name: $token, fields: $fields, interfaceNames: $interfaceNames}';
  }

  @override
  String toDart(GQGrammar grammar) {
    _updateFields();
    return """
      @JsonSerializable()
      class $token ${_serializeSuperClass()}{
        
          ${serializeListText(getFields().map((e) => e.toDart(grammar)).toList(), join: "\n\r          ", withParenthesis: false)}
          
          $token(${serializeContructorArgs(grammar)})${_serializeCallToSuper(grammar)};
          
          factory $token.fromJson(Map<String, dynamic> json) {
             ${_serilaizeFromJson()}
          }
          
          Map<String, dynamic> toJson() {
            ${_serilaizeToJson()}
          }
      }
    """;
  }

  String _serilaizeFromJson() {
    if (subTypes.isEmpty) {
      return "return _\$${token}FromJson(json);";
    } else {
      return """
      var typename = json["__typename"];
      switch(typename) {
        
        ${subTypes.map((st) => "case \"${st.derivedFromType?.token}\": return ${st.token}FromJson(json);").join("\n        ")}
      }
      return _\$${token}FromJson(json);
    """;
    }
  }

  String _serilaizeToJson() {
    return "return _\$${token}ToJson(this);";
  }

  void _updateFields() {
    if (_fiedsUpdated) {
      return;
    }
    _fiedsUpdated = true;
    _removeCommonFieldsFromFields();
    _addCommonFieldsFromSubTypes();
    var sc = superClass;
    if (sc != null) {
      _superFields.addAll(sc.getCommonFields());
    }
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

  void _removeCommonFieldsFromFields() {
    var sc = superClass;
    if (sc != null) {
      var scFields = sc.getCommonFields().toSet();
      fields.removeWhere((f) => scFields.contains(f));
    }
  }

  void _addCommonFieldsFromSubTypes() {
    if (subTypes.isNotEmpty) {
      fields.addAll(getCommonFields());
    }
  }

  Set<GQField> getCommonFields() {
    if (_commonFields.isNotEmpty) {
      return _commonFields;
    }
    if (subTypes.isNotEmpty) {
      //get the commont fields
      Map<GQField, int> occurenceMap = {};

      for (var typeDef in subTypes) {
        for (var field in typeDef.fields) {
          if (occurenceMap.containsKey(field)) {
            occurenceMap[field] = occurenceMap[field]! + 1;
          } else {
            occurenceMap[field] = 1;
          }
        }
      }

      occurenceMap.forEach((key, value) {
        if (value > 1) {
          _commonFields.add(key);
        }
      });
    }
    return _commonFields;
  }

  String _serializeSuperClass() {
    if (superClass == null) {
      return '';
    }
    return "extends ${superClass!.token} ";
  }

  String serializeFields(GQGrammar grammar) {
    return serializeListText(
        fields.map((e) => e.toDartNoFinal(grammar)).toList(),
        join: " ",
        withParenthesis: false);
  }

  String serializeContructorArgs(GQGrammar grammar) {
    if (fields.isEmpty && _superFields.isEmpty) {
      return "";
    }

    String commonFields = _superFields.isEmpty
        ? ""
        : _superFields
            .map((e) => e.toDartMethodDeclaration(grammar))
            .join(", ");
    String nonCommonFields = getFields().isEmpty
        ? ""
        : getFields()
            .map((e) => e.name)
            .map((e) => "required this.$e")
            .join(", ");
    var combined = [nonCommonFields, commonFields]
        .where((element) => element.isNotEmpty)
        .toSet();
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
