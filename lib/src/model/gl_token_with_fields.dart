import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/utils.dart';

const importList = "_list";

abstract class GLTokenWithFields extends GLExtensibleToken {
  final Map<String, GLField> _fieldMap = {};

  final _fieldNames = <String>{};

  List<GLField>? _skipOnClientFields;
  List<GLField>? _skipOnServerFields;

  GLTokenWithFields(super.tokenInfo, super.extension, List<GLField> allFields,
      {super.documentation}) {
    allFields.forEach(addField);
  }

  void addField(GLField field) {
    if (_fieldMap.containsKey(field.name.token)) {
      throw ParseException(
          "Duplicate field defition on type ${tokenInfo}, field: ${field.name}",
          info: field.name);
    }
    _fieldMap[field.name.token] = field;
  }

  void addOrMergeField(GLField field) {
    if (_fieldMap.containsKey(field.name.token)) {
      var current = _fieldMap[field.name.token]!;
      current.checkMerge(field);
      field.getDirectives().forEach(current.addDirective);
    } else {
      addField(field);
    }
  }

  void checkFields(GLField oroginal, GLField newField) {}

  bool hasField(String name) {
    return fieldNames.contains(name);
  }

  List<GLField> get fields {
    return _fieldMap.values.toList();
  }

  GLField? getFieldByName(String name) {
    return _fieldMap[name];
  }

  GLField findFieldByName(String fieldName, GLParser g) {
    var field = getFieldByName(fieldName);
    if (field == null) {
      if (fieldName == GLParser.typename) {
        return GLField(
          name: fieldName.toToken(),
          type: GLType("String".toToken(), false),
          arguments: [],
          directives: [],
        );
      } else {
        throw ParseException(
            "Could not find field '$fieldName' on type ${tokenInfo}",
            info: tokenInfo);
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

  List<GLField> getSerializableFields(CodeGenerationMode mode,
      {bool skipGenerated = false}) {
    return fields
        .where((f) => !shouldSkipSerialization(
            directives: f.getDirectives(skipGenerated: skipGenerated),
            mode: mode))
        .toList();
  }

  List<GLField> getSkipOnServerFields() {
    return _skipOnServerFields ??= fields.where((field) {
      return field
          .getDirectives()
          .where((d) => d.token == glSkipOnServer)
          .isNotEmpty;
    }).toList();
  }

  List<GLField> getSkipOnClientFields() {
    return _skipOnClientFields ??= fields.where((field) {
      return field
          .getDirectives()
          .where((d) => d.token == glSkipOnClient)
          .isNotEmpty;
    }).toList();
  }

  @override
  Set<GLToken> getImportDependecies(GLParser g) {
    var result = <String, GLToken>{};
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

  GLToken? _getMappedTo(GLToken? token, GLParser g) {
    if (token == null || token is! GLTypeDefinition) {
      return null;
    }
    var mapTo =
        token.getDirectiveByName(glSkipOnServer)?.getArgValueAsString(glMapTo);
    if (mapTo == null) {
      return null;
    }
    return g.types[mapTo];
  }

  @override
  Set<String> getImports(GLParser g) {
    var result = <String>{};
    if (this is GLDirectivesMixin) {
      result.addAll(extractImports(this as GLDirectivesMixin, g.mode));
    }
    for (var f in _fieldMap.values) {
      var token = g.getTokenByKey(f.type.token);
      result.addAll(extractImports(f, g.mode, skipOwnImports: false));
      if (f.type.isList) {
        result.add(importList);
      }
      if (token != null && token is GLDirectivesMixin) {
        result.addAll(extractImports(token as GLDirectivesMixin, g.mode,
            skipOwnImports: true));

        // handle arguments
        for (var arg in f.arguments) {
          if (arg.type.isList) {
            result.add(importList);
          }
          result.addAll(extractImports(arg as GLDirectivesMixin, g.mode,
              skipOwnImports: false));
          var argToken = g.getTokenByKey(arg.type.token);
          if (argToken != null && argToken is GLDirectivesMixin) {
            result.addAll(extractImports(argToken as GLDirectivesMixin, g.mode,
                skipOwnImports: true));
          }
        }
      }
    }
    result.addAll(staticImports);
    return result;
  }

  static Set<String> extractImports(
      GLDirectivesMixin dir, CodeGenerationMode mode,
      {bool skipOwnImports = false}) {
    var result = <String>{};
    // is it external ?
    var external = dir.getDirectiveByName(glExternal);
    if (external != null) {
      var externalImport = external.getArgValueAsString(glImport);
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
                return e.getArgValue(glOnClient) == true;
              case CodeGenerationMode.server:
                return e.getArgValue(glOnServer) == true;
            }
          })
          .map((d) => d.getArgValueAsString(glImport))
          .where((e) => e != null)
          .map((e) => e!)
          .forEach(result.add);
    }
    return result;
  }

  ///
  /// if returns true, then it is a legit dependecy
  ///

  bool filterDependecy(GLToken? token, GLParser g) {
    if (token == null) {
      return false;
    }
    if (g.scalars.containsKey(token.token)) {
      return false;
    }
    if (token is GLDirectivesMixin) {
      var dirMixin = token as GLDirectivesMixin;
      var exteneral = dirMixin.getDirectiveByName(glExternal);
      if (exteneral != null) {
        return false;
      }
      return !shouldSkip(dirMixin, g.mode);
    }
    return true;
  }
}
