import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/utils.dart';

abstract class GLTokenWithFields extends GLExtensibleToken {
  final Map<String, GLField> _fieldMap = {};

  final _fieldNames = <String>{};

  List<GLField>? _cachedFields;
  List<GLField>? _cachedSerializableClient;
  List<GLField>? _cachedSerializableServer;
  List<GLField>? _skipOnClientFields;
  List<GLField>? _skipOnServerFields;

  GLTokenWithFields(super.tokenInfo, super.extension, List<GLField> allFields, {super.documentation}) {
    allFields.forEach(addField);
  }

  void _invalidateFieldCaches() {
    _cachedFields = null;
    _cachedSerializableClient = null;
    _cachedSerializableServer = null;
    _skipOnClientFields = null;
    _skipOnServerFields = null;
    _fieldNames.clear();
  }

  void addField(GLField field) {
    if (_fieldMap.containsKey(field.name.token)) {
      throw ParseException("Duplicate field defition on type ${tokenInfo}, field: ${field.name}", info: field.name);
    }
    _fieldMap[field.name.token] = field;
    _invalidateFieldCaches();
  }

  void addOrMergeField(GLField field) {
    if (_fieldMap.containsKey(field.name.token)) {
      var current = _fieldMap[field.name.token]!;
      current.checkMerge(field);
      field.getDirectives().forEach(current.addDirectiveIfAbsent);
    } else {
      addField(field);
    }
    _invalidateFieldCaches();
  }

  void checkFields(GLField oroginal, GLField newField) {}

  bool hasField(String name) {
    return _fieldMap.containsKey(name);
  }

  List<GLField> get fields {
    return _cachedFields ??= _fieldMap.values.toList();
  }

  GLField? getFieldByName(String name) {
    return _fieldMap[name];
  }

  GLField findFieldByName(String fieldName, GLParser g) {
    final field = _fieldMap[fieldName];
    if (field == null) {
      if (fieldName == GLParser.typename) {
        return GLField(
          name: fieldName.toToken(),
          type: GLType("String".toToken(), false),
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
    if (_fieldMap.isEmpty) return {};
    if (_fieldNames.isEmpty) {
      _fieldNames.addAll(_fieldMap.keys);
    }
    return _fieldNames;
  }

  /// Resolves a target-language-safe identifier for [name].
  ///
  /// Two transformations are applied (only when [reservedWords] is non-empty):
  ///
  /// 1. **Leading underscore** — if [name] starts with `_`, the underscore is
  ///    moved to the end (`_links` → `links_`). This avoids emitting private
  ///    identifiers in languages where `_` is a visibility modifier (Dart).
  /// 2. **Reserved keyword** — if the resulting name is a reserved word, an
  ///    underscore is appended (`default` → `default_`).
  ///
  /// When the candidate clashes with another field on the type, a numeric suffix
  /// is added (`links_2`, `default_2`, …) until the result is unique among
  /// [fieldNames].
  String resolveCodeName(String name, Set<String> reservedWords) {
    // Step 1: strip leading underscore (Dart privacy convention).
    var codeName = name.startsWith('_') ? '${name.substring(1)}_' : name;

    // Step 2: if the name is unchanged and not reserved, return as-is.
    if (codeName == name && !reservedWords.contains(name)) return name;

    // Step 3: the name was changed or is reserved — check for collisions.
    if (!reservedWords.contains(codeName) && !fieldNames.contains(codeName)) {
      return codeName;
    }

    // Step 4: disambiguate.
    if (reservedWords.contains(codeName)) {
      codeName = '${codeName}_';
    }
    var counter = 2;
    var candidate = codeName;
    while (fieldNames.contains(candidate)) {
      candidate = '$codeName$counter';
      counter++;
    }
    return candidate;
  }

  /// Applies [convention] to every field, normalizing identifier casing.
  ///
  /// Collision with a sibling wire name or an already-assigned code name on
  /// this type is resolved with an index suffix (`user`, `user2`, `user3`, …).
  /// Must run before [assignCodeNames] so that keyword-safe operates on the
  /// already-normalized name.
  void applyFieldNaming(NamingConvention convention) {
    // Seed the taken set with every wire name so we never produce a code name
    // that shadows a sibling's original GraphQL identifier.
    final taken = fieldNames.toSet();

    for (final field in fields) {
      final raw = field.name.token;
      final normalized = convention.field(raw);
      if (normalized == raw) continue; // already canonical

      var code = normalized;
      if (taken.contains(code)) {
        var counter = 2;
        while (taken.contains('$code$counter')) {
          counter++;
        }
        code = '$code$counter';
      }
      field.codeName = code;
      taken.add(code);
    }
  }

  /// Populates [GLField.codeName] for every field, rewriting any field whose
  /// name collides with a reserved keyword in the target language.
  ///
  /// Starts from [GLField.codeName] (not the raw wire name) so that a prior
  /// [applyFieldNaming] pass is respected — keyword-safe fires on the
  /// already-normalized identifier.
  void assignCodeNames(Set<String> reservedWords) {
    if (reservedWords.isEmpty) return;
    for (var field in fields) {
      field.codeName = resolveCodeName(field.codeName, reservedWords);
    }
  }

  // Caches the two common cases (client/server, skipGenerated=false).
  // The rare skipGenerated=true path (used during Java annotation emission)
  // is not cached since it is never on the hot path.
  List<GLField> getSerializableFields(CodeGenerationMode mode, {bool skipGenerated = false}) {
    if (!skipGenerated) {
      switch (mode) {
        case CodeGenerationMode.client:
          return _cachedSerializableClient ??= _buildSerializableFields(mode);
        case CodeGenerationMode.server:
          return _cachedSerializableServer ??= _buildSerializableFields(mode);
      }
    }
    return _buildSerializableFields(mode, skipGenerated: skipGenerated);
  }

  void invalidateSerializableCacheFields(CodeGenerationMode mode) {
    switch (mode) {
      case CodeGenerationMode.client:
        _cachedSerializableClient = null;
        break;
      case CodeGenerationMode.server:
        _cachedSerializableServer = null;
        break;
    }
  }

  List<GLField> _buildSerializableFields(CodeGenerationMode mode, {bool skipGenerated = false}) {
    return _fieldMap.values.where((f) => !shouldSkipSerialization(directives: f.getDirectives(skipGenerated: skipGenerated), mode: mode)).toList();
  }

  List<GLField> getSkipOnServerFields() {
    return _skipOnServerFields ??= _fieldMap.values.where((field) {
      return field.getDirectives().where((d) => d.token == glSkipOnServer).isNotEmpty;
    }).toList();
  }

  List<GLField> getSkipOnClientFields() {
    return _skipOnClientFields ??= _fieldMap.values.where((field) {
      return field.getDirectives().where((d) => d.token == glSkipOnClient).isNotEmpty;
    }).toList();
  }

  @override
  Set<GLToken> getImportDependecies(GLParser g) {
    var result = <String, GLToken>{};
    super.getImportDependecies(g).forEach((dep) {
      result[dep.token] = dep;
    });
    var fields = getSerializableFields(g.mode);
    for (var f in fields) {
      _collectTypeDependencies(f.type, g, result);
      for (var arg in f.arguments) {
        _collectTypeDependencies(arg.type, g, result);
      }
    }
    return Set.unmodifiable(result.values);
  }

  /// Walks [type] down to every leaf (recursing through `GLListType.type` and
  /// both sides of `GLMapType`, at any nesting depth) and registers each
  /// leaf's resolved token as an import dependency when [filterDependecy]
  /// allows it.
  void _collectTypeDependencies(GLType type, GLParser g, Map<String, GLToken> result) {
    if (type is GLMapType) {
      _collectTypeDependencies(type.keyType, g, result);
      _collectTypeDependencies(type.valueType, g, result);
      return;
    }
    if (type is GLListType) {
      _collectTypeDependencies(type.type, g, result);
      return;
    }
    var token = g.getTokenByKey(type.token);
    if (token is GLTypeDefinition) {
      final mappedTo = token.mappedToType;
      if (mappedTo != null) {
        result[mappedTo.token] = mappedTo;
      }
    }
    if (filterDependecy(token, g)) {
      result[token!.token] = token;
    }
  }

  void replaceField(GLField field) {
    _fieldMap[field.name.token] = field;
    _invalidateFieldCaches();
  }

  @override
  Set<String> getImports(GLParser g) {
    var result = <String>{};
    if (this is GLDirectivesMixin) {
      result.addAll(extractImports(this as GLDirectivesMixin, g.mode));
    }
    for (var field in _fieldMap.values) {
      var token = g.getTokenByKey(field.type.token);
      result.addAll(extractImports(field, g.mode, skipOwnImports: false));
      result.addAll(collectionImportsOf(field.type));

      if (token != null && token is GLDirectivesMixin) {
        result.addAll(extractImports(token as GLDirectivesMixin, g.mode, skipOwnImports: true));
      }

      for (var arg in field.arguments) {
        result.addAll(
          [
            arg.type.externalImport,
            arg.type.wrapperImport,
          ].whereType(),
        );
        result.addAll(extractImports(arg as GLDirectivesMixin, g.mode, skipOwnImports: false));
        var argToken = g.getTokenByKey(arg.type.token);
        if (argToken != null && argToken is GLDirectivesMixin) {
          result.addAll(extractImports(argToken as GLDirectivesMixin, g.mode, skipOwnImports: true));
        }
      }
      for (var arg in field.arguments) {
        result.addAll(arg.getAnnotations().map((e) => e.getArgValueAsString(glImport)).where((imp) => imp != null).map((e) => e!));
        result.addAll(arg.getImports(g));
      }
    }
    result.addAll(super.getImports(g));
    return result;
  }

  static Set<String> extractImports(GLDirectivesMixin dir, CodeGenerationMode mode, {bool skipOwnImports = false}) {
    var result = <String>{};
    final externalImport = dir.externalImport;
    if (externalImport != null) {
      result.add(externalImport);
    }
    if (!skipOwnImports) {
      // does it have imports
      dir
          .getDirectives()
          .where((e) {
            switch (mode) {
              case CodeGenerationMode.client:
                return e.getArgValueAsBool(glOnClient);
              case CodeGenerationMode.server:
                return e.getArgValueAsBool(glOnServer);
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
    if (token == null || g.scalars.containsKey(token.token)) {
      return false;
    }
    if (token is GLDirectivesMixin) {
      final dirMixin = token as GLDirectivesMixin;
      return !dirMixin.isExternal && !shouldSkip(dirMixin, g.mode);
    }
    return true;
  }
}
