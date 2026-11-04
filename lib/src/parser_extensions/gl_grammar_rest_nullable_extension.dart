import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_rest_discriminator.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/token_info.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_projection_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_response_extension.dart';

extension GLGrammarRestNullableExtension on GLParser {
  List<GLDirectiveValue> pushRestNullableToFields(
      TokenInfo typeName, List<GLDirectiveValue> typeDirectives, List<GLField> fields) {
    final directive = typeDirectives.where((d) => d.token == glRestNullable).firstOrNull;
    if (directive == null) return typeDirectives;
    restNullableTypes.putIfAbsent(typeName.token, () => directive.tokenInfo);
    for (final field in fields) {
      final isRest = field.hasDirective(glRest) || field.hasDirective(glRestPrefix);
      if (isRest && !field.hasDirective(glRestNullable)) field.addDirective(_restNullableDirective());
    }
    return typeDirectives.where((d) => d.token != glRestNullable).toList();
  }

  void rejectRestNullableOnNonRootTypes(Set<String> operationRoots) {
    for (final entry in restNullableTypes.entries) {
      if (operationRoots.contains(entry.key)) continue;
      throw ParseException(
          "$glRestNullable is only allowed on the Query or Mutation type, but it is on '${entry.key}'",
          info: entry.value);
    }
  }

  GLDirectiveValue _restNullableDirective() =>
      GLDirectiveValue(glRestNullable.toToken(), [GLDirectiveScope.FIELD_DEFINITION], [], generated: true);

  void settleRestNullableDefaults() {
    for (final op in restOperations.values) {
      final inherited = op.field.getDirectiveByName(glRestNullable)?.generated ?? false;
      final obstructed = restNullableObstacle(op) != null;
      if (inherited && obstructed) {
        op.field.removeDirectiveByName(glRestNullable);
      } else if (restNullable && !obstructed && !op.field.hasDirective(glRestNullable)) {
        op.field.addDirective(_restNullableDirective());
      }
    }
  }

  String? restNullableObstacle(GLRestOperation op) {
    const withoutFields = {
      RestResponseKind.text: 'text',
      RestResponseKind.binary: 'binary',
      RestResponseKind.none: 'void',
    };
    final kind = withoutFields[op.responseKind];
    if (kind != null) return 'a $kind response has no fields to make nullable';
    final target = op.field.type.firstType.token;
    if (!types.containsKey(target) && !interfaces.containsKey(target)) {
      return 'it returns a scalar or enum, there is nothing to copy';
    }
    return null;
  }

  void createRestNullableCopies() {
    final optedIn = restOperations.values.where((op) => op.field.hasDirective(glRestNullable)).toList();
    if (optedIn.isEmpty) return;

    final originals = restReachableTypeNamesFrom(optedIn)
        .map((name) => interfaces[name] ?? types[name])
        .whereType<GLTypeDefinition>()
        .toList();
    final copied = {for (final original in originals) original.token};
    _rejectNameCollisions(originals);

    final copies = {for (final original in originals) original.token: _copyOf(original, copied)};
    _linkInterfaces(originals, copies);
    copies.values.forEach((copy) => addToProjectedTypes(copy, similarityCheck: false));
    _copyDiscriminators(originals, copied);

    for (final operation in optedIn) {
      final field = operation.field.ofType(_renamed(operation.field.type, copied));
      _ownerOf(operation).replaceField(field);
      restOperations[operation.key] = operation.withField(field);
    }
  }

  GLTypeDefinition _ownerOf(GLRestOperation operation) =>
      types.values.firstWhere((type) => type.fields.any((field) => identical(field, operation.field)));

  String _copyName(String token) => '$token$restNullableSuffix';

  void _rejectNameCollisions(List<GLTypeDefinition> originals) {
    for (final original in originals) {
      final name = _copyName(original.token);
      final existing = types[name] ??
          interfaces[name] ??
          inputs[name] ??
          enums[name] ??
          scalars[name] ??
          unions[name] ??
          projectedTypes[name] ??
          projectedInterfaces[name];
      if (existing != null) {
        throw ParseException(
            "$glRestNullable needs the name '$name' for the copy of '${original.token}', but '$name' already exists: rename it or change the restNullableSuffix option",
            info: existing.tokenInfo);
      }
    }
  }

  GLType _renamed(GLType type, Set<String> copied) {
    final target = type.firstType;
    if (!copied.contains(target.token)) return type;
    return type.ofNewName(target.tokenInfo.ofNewName(_copyName(target.token)));
  }

  GLType _nullable(GLType type, Set<String> copied) => GLType.makeNullable(_renamed(type, copied));

  GLTypeDefinition _copyOf(GLTypeDefinition original, Set<String> copied) {
    final name = original.tokenInfo.ofNewName(_copyName(original.token));
    final fields = [for (final field in original.fields) field.ofType(_nullable(field.type, copied))];
    if (original is GLInterfaceDefinition) {
      return GLInterfaceDefinition(
        name: name,
        nameDeclared: true,
        fields: fields,
        directives: [],
        interfaceNames: {},
        fieldAsMethods: original.fieldAsMethods,
        extension: false,
        skipJsonMethods: original.skipJsonMethods,
        skipOnGraphqlSerialization: original.skipOnGraphqlSerialization,
        documentation: original.documentation,
      );
    }
    return GLTypeDefinition(
      name: name,
      nameDeclared: true,
      fields: fields,
      directives: [],
      interfaceNames: {},
      derivedFromType: null,
      extension: false,
      skipJsonMethods: original.skipJsonMethods,
      skipOnGraphqlSerialization: original.skipOnGraphqlSerialization,
      documentation: original.documentation,
    );
  }

  void _linkInterfaces(List<GLTypeDefinition> originals, Map<String, GLTypeDefinition> copies) {
    for (final original in originals) {
      for (final interfaceName in original.interfaceNames) {
        final target = copies[interfaceName.token];
        if (target is GLInterfaceDefinition) copies[original.token]!.addInterface(target);
      }
    }
  }

  void _copyDiscriminators(List<GLTypeDefinition> originals, Set<String> copied) {
    for (final original in originals.whereType<GLInterfaceDefinition>()) {
      final discriminator = restDiscriminators[original.token];
      if (discriminator == null) continue;
      final name = _copyName(original.token);
      restDiscriminators[name] = GLRestDiscriminator(
        parent: name,
        field: discriminator.field,
        valueByType: {
          for (final entry in discriminator.valueByType.entries)
            if (copied.contains(entry.key)) _copyName(entry.key): entry.value,
        },
      );
    }
  }
}
