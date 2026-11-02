import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/internal_directive_declarations.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

const _annotationArguments = {glClass, glImport, 'glOnClient', 'glOnServer', 'glAnnotation', 'glApplyOnFields'};

const _valueKindsCheckedElsewhere = {glCache, glCacheInvalidate};

extension GLGrammarDirectiveValidationExtension on GLParser {
  void validateDirectives() {
    final internal = InternalDirectives.instance;
    _checkRedeclarations(internal);
    for (final directive in directiveValues) {
      if (directive.generated) continue;
      final definition = internal.definitions[directive.token] ?? directiveDefinitions[directive.token];
      if (definition == null) {
        throw ParseException(
            "Directive ${directive.token} is not declared: add 'directive ${directive.token} on ...' to your schema",
            info: directive.tokenInfo);
      }
      _checkLocation(directive, definition);
      _checkArguments(directive, definition, internal);
    }
  }

  void _checkLocation(GLDirectiveValue directive, GLDirectiveDefinition definition) {
    if (directive.locations.isEmpty || definition.scopes.isEmpty) return;
    final location = directive.locations.first;
    if (definition.scopes.contains(location)) return;
    final allowed = definition.scopes.map((s) => s.name).join(', ');
    throw ParseException('${directive.token} cannot be used on ${location.name} (allowed: $allowed)',
        info: directive.tokenInfo);
  }

  void _checkRedeclarations(InternalDirectives internal) {
    for (final declared in directiveDefinitions.values) {
      final canonical = internal.definitions[declared.name.token];
      if (canonical == null) continue;
      final known = canonical.arguments.map((a) => a.token).toSet();
      for (final argument in declared.arguments) {
        if (!known.contains(argument.token) && !_annotationArguments.contains(argument.token)) {
          throw ParseException(
              "${declared.name.token} is built in and has no argument '${argument.token}' (valid: ${_names(canonical)})",
              info: argument.tokenInfo);
        }
      }
    }
  }

  void _checkArguments(GLDirectiveValue directive, GLDirectiveDefinition definition, InternalDirectives internal) {
    final byName = {for (final a in definition.arguments) a.token: a};
    final given = directive.getArguments();
    for (final value in given) {
      final declared = byName[value.token];
      if (declared == null) {
        throw ParseException(
            "Unknown argument '${value.token}' of ${directive.token}${_validHint(definition)}",
            info: value.tokenInfo);
      }
      final problem = _valueKindsCheckedElsewhere.contains(directive.token)
          ? null
          : _valueProblem(value.value, declared.type, internal);
      if (problem != null) {
        throw ParseException(
            "Argument '${value.token}' of ${directive.token} $problem", info: value.tokenInfo);
      }
    }
    final present = given.map((a) => a.token).toSet();
    for (final declared in definition.arguments) {
      if (!declared.type.nullable && declared.defaultValue == null && !present.contains(declared.token)) {
        throw ParseException(
            "Missing required argument '${declared.token}' of ${directive.token}", info: directive.tokenInfo);
      }
    }
  }

  String _validHint(GLDirectiveDefinition definition) =>
      definition.arguments.isEmpty ? ' (it takes no arguments)' : ' (valid: ${_names(definition)})';

  String _names(GLDirectiveDefinition definition) => definition.arguments.map((a) => a.token).join(', ');

  String? _valueProblem(Object? value, GLType type, InternalDirectives internal) {
    if (value is String && value.startsWith(r'$')) return null;
    if (value == null) return type.nullable ? null : 'must not be null';
    if (type is GLListType) {
      if (value is! List) return 'must be a list';
      for (final item in value) {
        final problem = _valueProblem(item, type.type, internal);
        if (problem != null) return problem;
      }
      return null;
    }
    final name = type.token;
    switch (name) {
      case 'String':
      case 'ID':
        return value is String ? null : 'must be a string';
      case 'Int':
        return value is int ? null : 'must be an Int';
      case 'Float':
        return value is num ? null : 'must be a number';
      case 'Boolean':
        return value is bool ? null : 'must be true or false';
      case internalDurationScalar:
        return value is int || value is String ? null : 'must be a number of seconds or a duration string such as "30s"';
      case internalMapScalar:
        return value is Map ? null : 'must be an object';
    }
    final enumDefinition = internal.enums[name] ?? enums[name];
    if (enumDefinition != null) {
      final allowed = enumDefinition.values.map((v) => v.value.token).toSet();
      final text = value is String ? value.replaceAll('"', '') : null;
      if (text == null || !allowed.contains(text)) return 'must be one of ${allowed.join(', ')}';
    }
    return null;
  }
}
