import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';

/// Wraps a [GLInputDefinition] and resolves its Flutter widget import dependencies.
class GlInputEntity {
  final GLInputDefinition input;
  final GLParser _parser;

  GlInputEntity(this.input, this._parser);

  String get name => input.codeName;

  List<GLField> get fields =>
      input.getSerializableFields(CodeGenerationMode.client);

  /// Enum data imports: scalar enum fields + list fields whose item type is an enum.
  Set<String> enumDataImports(String prefix) {
    final result = <String>{};
    for (final f in fields) {
      if (!f.type.isList) {
        final wireToken = f.type.firstType.token;
        if (_parser.enums.containsKey(wireToken)) {
          final codeName = _parser.enums[wireToken]!.codeName;
          result.add("import '$prefix/enums/${codeName.toSnakeCase()}.dart';");
        }
      } else {
        final itemToken = f.type.inlineType.firstType.token;
        if (_parser.enums.containsKey(itemToken)) {
          final codeName = _parser.enums[itemToken]!.codeName;
          result.add("import '$prefix/enums/${codeName.toSnakeCase()}.dart';");
        }
      }
    }
    return result;
  }

  /// Label imports: scalar enum fields + list-of-enum fields (chips/checkboxes need labels).
  Set<String> enumLabelImports(String prefix) {
    final result = <String>{};
    for (final f in fields) {
      if (!f.type.isList && _parser.enums.containsKey(f.type.firstType.token)) {
        final codeName = _parser.enums[f.type.firstType.token]!.codeName;
        result.add("import '$prefix/widgets/enums/${codeName.toSnakeCase()}_labels.dart';");
      } else if (f.type.isList) {
        final itemToken = f.type.inlineType.firstType.token;
        if (_parser.enums.containsKey(itemToken)) {
          final codeName = _parser.enums[itemToken]!.codeName;
          result.add("import '$prefix/widgets/enums/${codeName.toSnakeCase()}_labels.dart';");
        }
      }
    }
    return result;
  }
}

/// Wraps a [GLTypeDefinition] and resolves its Flutter widget import dependencies.
class GlTypeEntity {
  final GLTypeDefinition type;
  final GLParser _parser;

  GlTypeEntity(this.type, this._parser);

  String get name => type.codeName;

  List<GLField> get fields => type.getSerializableFields(_parser.mode);

  /// Enum data imports: scalar enum fields + list-of-enum fields.
  Set<String> enumDataImports(String prefix) {
    final result = <String>{};
    for (final f in fields) {
      if (!f.type.isList) {
        final wireToken = f.type.firstType.token;
        if (_parser.enums.containsKey(wireToken)) {
          final codeName = _parser.enums[wireToken]!.codeName;
          result.add("import '$prefix/enums/${codeName.toSnakeCase()}.dart';");
        }
      } else {
        final itemToken = f.type.inlineType.firstType.token;
        if (_parser.enums.containsKey(itemToken)) {
          final codeName = _parser.enums[itemToken]!.codeName;
          result.add("import '$prefix/enums/${codeName.toSnakeCase()}.dart';");
        }
      }
    }
    return result;
  }

  /// Label imports: scalar enum fields + list-of-enum fields.
  Set<String> enumLabelImports(String prefix) {
    final result = <String>{};
    for (final f in fields) {
      if (!f.type.isList && _parser.enums.containsKey(f.type.firstType.token)) {
        final codeName = _parser.enums[f.type.firstType.token]!.codeName;
        result.add("import '$prefix/widgets/enums/${codeName.toSnakeCase()}_labels.dart';");
      } else if (f.type.isList) {
        final itemToken = f.type.inlineType.firstType.token;
        if (_parser.enums.containsKey(itemToken)) {
          final codeName = _parser.enums[itemToken]!.codeName;
          result.add("import '$prefix/widgets/enums/${codeName.toSnakeCase()}_labels.dart';");
        }
      }
    }
    return result;
  }
}
