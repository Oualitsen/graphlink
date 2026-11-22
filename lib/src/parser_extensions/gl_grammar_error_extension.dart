import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_error.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/token_info.dart';

/// Names every target's exception base already uses, compared without case and underscores.
const _baseMembers = {
  'message',
  'path',
  'extensions',
  'cause',
  'stack',
  'stacktrace',
  'args',
  'name',
  'localizedmessage',
  'localizeddescription',
  'suppressed',
  'hashcode',
  'runtimetype',
  'error',
  'unwrap',
};

extension GLGrammarErrorExtension on GLParser {
  /// Moves every `@glError` type out of [GLParser.types] into [GLParser.errors], after checking it is used
  /// nowhere as a normal type. Runs right after the directives are validated so no later pass sees them.
  void extractErrorTypes() {
    final declared = {
      for (final type in types.values)
        if (_declaresError(type)) type.token: type,
    };
    if (declared.isEmpty) return;
    declared.values.forEach(_mergeExtensions);
    _rejectUsesAsNormalType(declared);
    for (final type in declared.values) {
      errors[type.token] = _definitionOf(type);
      types.remove(type.token);
    }
  }

  Iterable<GLTypeDefinition> _declarations(GLTypeDefinition type) =>
      (extensibleTokens[type.token]?.data ?? const []).whereType<GLTypeDefinition>();

  bool _declaresError(GLTypeDefinition type) => type.hasDirective(glError) || _declarations(type).any((d) => d.hasDirective(glError));

  void _mergeExtensions(GLTypeDefinition type) {
    for (final extension in _declarations(type).where((d) => d != type)) {
      type.merge(extension);
    }
  }

  void _rejectUsesAsNormalType(Map<String, GLTypeDefinition> declared) {
    void check(String used, String where, TokenInfo info) {
      if (!declared.containsKey(used)) return;
      throw ParseException("'$used' is an $glError type and cannot be used as $where", info: info);
    }

    for (final owner in [...types.values.where((t) => !declared.containsKey(t.token)), ...interfaces.values]) {
      for (final field in owner.fields) {
        final at = '${owner.token}.${field.name.token}';
        check(field.type.firstType.token, 'a field type ($at)', field.name);
        for (final argument in field.arguments) {
          check(argument.type.firstType.token, 'an argument type ($at)', field.name);
        }
      }
    }
    for (final input in inputs.values) {
      for (final field in input.fields) {
        check(field.type.firstType.token, 'an input field type (${input.token}.${field.name.token})', field.name);
      }
    }
    for (final union in unions.values) {
      for (final member in union.typeNames) {
        check(member.token, 'a member of union ${union.token}', member);
      }
    }
    for (final type in declared.values) {
      if (type.interfaceNames.isNotEmpty) {
        throw ParseException("$glError type '${type.token}' cannot implement an interface", info: type.tokenInfo);
      }
    }
  }

  GLErrorDefinition _definitionOf(GLTypeDefinition type) {
    final directive = type.getDirectiveByName(glError)!;
    _validateFields(type);
    return GLErrorDefinition(
      type: type,
      field: _discriminatorPath(directive),
      value: _discriminatorValue(directive, type),
      status: _status(directive),
    );
  }

  void _validateFields(GLTypeDefinition type) {
    for (final field in type.fields) {
      final name = field.name.token;
      final at = '${type.token}.$name';
      if (_baseMembers.contains(name.replaceAll('_', '').toLowerCase())) {
        throw ParseException(
            "Field '$name' of $glError type ${type.token} clashes with a member of the generated exception base",
            info: field.name);
      }
      if (field.arguments.isNotEmpty) {
        throw ParseException("Field $at of an $glError type cannot have arguments", info: field.name);
      }
      if (field.initialValue != null) {
        throw ParseException("Field $at of an $glError type cannot have a default value", info: field.name);
      }
      final used = field.type.firstType.token;
      if (scalars.containsKey(used) || enums.containsKey(used)) continue;
      final known = types.containsKey(used) || interfaces.containsKey(used) || unions.containsKey(used);
      throw ParseException(
          known
              ? "Field $at of an $glError type must be a scalar, an enum or a list of them, not '$used'"
              : "$at: $used is not a scalar or enum",
          info: field.name);
    }
  }

  List<String> _discriminatorPath(GLDirectiveValue directive) {
    final text = directive.getArgValueAsString(glErrorFieldArg);
    if (text == null) return GLErrorDefinition.defaultField;
    final path = text.split('.');
    if (path.any((segment) => segment.trim().isEmpty)) {
      throw ParseException("Argument 'field' of $glError must be a dotted path without empty segments, got '$text'",
          info: directive.tokenInfo);
    }
    return path;
  }

  String _discriminatorValue(GLDirectiveValue directive, GLTypeDefinition type) {
    final text = directive.getArgValueAsString(glErrorValueArg);
    if (text == null) return type.token;
    if (text.isEmpty) throw ParseException("Argument 'value' of $glError must not be empty", info: directive.tokenInfo);
    return text;
  }

  int? _status(GLDirectiveValue directive) {
    final status = directive.getArgValue(glErrorStatusArg);
    if (status == null) return null;
    if (status is! int || status < 100 || status > 599) {
      throw ParseException("Argument 'status' of $glError must be an HTTP status between 100 and 599, got '$status'",
          info: directive.tokenInfo);
    }
    return status;
  }
}
