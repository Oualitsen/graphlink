import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_directives_mixin.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:retrofit_graphql/src/utils.dart';

const importList = "_list";

abstract class GQTokenWithFields extends GQToken {
  final Map<String, GQField> _fieldMap = {};

  final _fieldNames = <String>{};

  List<GQField>? _skipOnClientFields;
  List<GQField>? _skipOnServerFields;

  GQTokenWithFields(super.tokenInfo, List<GQField> allFields) {
    allFields.forEach(addField);
  }

  void addField(GQField field) {
    if (_fieldMap.containsKey(field.name.token)) {
      throw ParseException("Duplicate field defition on type ${tokenInfo}, field: ${field.name}", info: field.name);
    }
    _fieldMap[field.name.token] = field;
  }

  bool hasField(String name) {
    return fieldNames.contains(name);
  }

  List<GQField> get fields {
    return _fieldMap.values.toList();
  }

  GQField? getFieldByName(String name) {
    return _fieldMap[name];
  }

  GQField findFieldByName(String fieldName, GQGrammar g) {
    var field = getFieldByName(fieldName);
    if (field == null) {
      if (fieldName == GQGrammar.typename) {
        return GQField(
          name: fieldName.toToken(),
          type: GQType(g.getLangType("String").toToken(), false),
          arguments: [],
          directives: [],
        );
      } else {
        throw ParseException("Could not find field '$fieldName' on type ${tokenInfo}", info: tokenInfo);
      }
    }
    return field;
  }

  Set<String> get fieldNames {
    if (fields.isEmpty) {
      return {};
    }
    if (_fieldNames.isEmpty) {
      _fieldNames.addAll(fields.map((e) => e.name.token));
    }
    return _fieldNames;
  }

  List<GQField> getSerializableFields(CodeGenerationMode mode, {bool skipGenerated = false}) {
    return fields
        .where((f) => !shouldSkipSerialization(directives: f.getDirectives(skipGenerated: skipGenerated), mode: mode))
        .toList();
  }

  List<GQField> getSkipOnServerFields() {
    return _skipOnServerFields ??= fields.where((field) {
      return field.getDirectives().where((d) => d.token == gqSkipOnServer).isNotEmpty;
    }).toList();
  }

  List<GQField> getSkipOnClientFields() {
    return _skipOnClientFields ??= fields.where((field) {
      return field.getDirectives().where((d) => d.token == gqSkipOnClient).isNotEmpty;
    }).toList();
  }

  @override
  Set<GQToken> getImportDependecies(GQGrammar g) {
    var result = <String, GQToken>{};
    var fields = getSerializableFields(g.mode);
    for (var f in fields) {
      var token = g.getTokenByKey(f.type.token);
      if (filterDependecy(token, g)) {
        result[token!.token] = token;
      } else {
        var mappedTo = _getMappedTo(token, g);
        if (mappedTo != null) {
          result[mappedTo.token] = mappedTo;
        }
      }
      for (var arg in f.arguments) {
        var argToken = g.getTokenByKey(arg.type.token);
        if (filterDependecy(argToken, g)) {
          result[argToken!.token] = argToken;
        }
      }
    }
    return Set.unmodifiable(result.values);
  }

  GQToken? _getMappedTo(GQToken? token, GQGrammar g) {
    if (token == null || token is! GQTypeDefinition) {
      return null;
    }
    var mapTo = token.getDirectiveByName(gqSkipOnServer)?.getArgValueAsString(gqMapTo);
    if (mapTo == null) {
      return null;
    }
    return g.types[mapTo];
  }

  @override
  Set<String> getImports(GQGrammar g) {
    var result = <String>{};
    if (this is GQDirectivesMixin) {
      result.addAll(extractImports(this as GQDirectivesMixin, g.mode));
    }
    for (var f in _fieldMap.values) {
      var token = g.getTokenByKey(f.type.token);
      result.addAll(extractImports(f, g.mode, skipOwnImports: false));
      if (f.type.isList) {
        result.add(importList);
      }
      if (token != null && token is GQDirectivesMixin) {
        result.addAll(extractImports(token as GQDirectivesMixin, g.mode, skipOwnImports: true));

        // handle arguments
        for (var arg in f.arguments) {
          if (arg.type.isList) {
            result.add(importList);
          }
          var argToken = g.getTokenByKey(arg.type.token);
          if (argToken != null && argToken is GQDirectivesMixin) {
            result.addAll(extractImports(argToken as GQDirectivesMixin, g.mode, skipOwnImports: true));
          }
        }
      }
    }
    result.addAll(staticImports);
    return result;
  }

  static Set<String> extractImports(GQDirectivesMixin dir, CodeGenerationMode mode, {bool skipOwnImports = false}) {
    var result = <String>{};
    // is it external ?
    var external = dir.getDirectiveByName(gqExternal);
    if (external != null) {
      var externalImport = external.getArgValueAsString(gqImport);
      if (externalImport != null) {
        result.add(externalImport);
      }
    }
    if (!skipOwnImports) {
      // does it have imports
      dir
          .getDirectives()
          .where((e) {
            switch (mode) {
              case CodeGenerationMode.client:
                return e.getArgValue(gqOnClient) == true;
              case CodeGenerationMode.server:
                return e.getArgValue(gqOnServer) == true;
            }
          })
          .map((d) => d.getArgValueAsString(gqImport))
          .where((e) => e != null)
          .map((e) => e!)
          .forEach(result.add);
    }
    return result;
  }

  ///
  /// if returns true, then it is a legit dependecy
  ///

  bool filterDependecy(GQToken? token, GQGrammar g) {
    if (token == null) {
      return false;
    }
    if (g.scalars.containsKey(token.token)) {
      return false;
    }
    if (token is GQDirectivesMixin) {
      var dirMixin = token as GQDirectivesMixin;
      var exteneral = dirMixin.getDirectiveByName(gqExternal);
      if (exteneral != null) {
        return false;
      }
      return !shouldSkip(dirMixin, g.mode);
    }
    return true;
  }
}
