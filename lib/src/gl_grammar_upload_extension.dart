import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type.dart';

extension GLGrammarUploadExtension on GLParser {
  /// Returns the names of all scalars marked with @glUpload.
  Set<String> get uploadScalarNames => scalars.entries
      .where((e) => e.value.hasDirective(glUpload))
      .map((e) => e.key)
      .toSet();

  /// True when at least one mutation uses an upload scalar as a direct argument.
  bool get hasUploadMutations =>
      uploadScalarNames.isNotEmpty &&
      queries.values.any((q) =>
          q.type == GLQueryType.mutation && mutationHasUploads(q));

  /// True when [def] has at least one upload scalar argument.
  bool mutationHasUploads(GLQueryDefinition def) => def.arguments
      .any((a) => uploadScalarNames.contains(a.type.firstType.token));

  /// @glUpload is only valid on scalar definitions.
  /// Throws if it is found on a type, input, field, field argument, or operation.
  void checkUploadDirectivePlacement() {
    for (final type in types.values) {
      if (type.hasDirective(glUpload)) {
        throw ParseException(
          "$glUpload is not allowed on type definitions — place it on a scalar only",
          info: type.tokenInfo,
        );
      }
      for (final field in type.fields) {
        if (field.hasDirective(glUpload)) {
          throw ParseException(
            "$glUpload is not allowed on fields",
            info: field.name,
          );
        }
        for (final arg in field.arguments) {
          if (arg.hasDirective(glUpload)) {
            throw ParseException(
              "$glUpload is not allowed on field arguments",
              info: arg.tokenInfo,
            );
          }
        }
      }
    }

    for (final input in inputs.values) {
      if (input.hasDirective(glUpload)) {
        throw ParseException(
          "$glUpload is not allowed on input types — place it on a scalar only",
          info: input.tokenInfo,
        );
      }
      for (final field in input.fields) {
        if (field.hasDirective(glUpload)) {
          throw ParseException(
            "$glUpload is not allowed on input fields",
            info: field.name,
          );
        }
      }
    }

    for (final query in queries.values) {
      if (query.hasDirective(glUpload)) {
        throw ParseException(
          "$glUpload is not allowed on operations",
          info: query.tokenInfo,
        );
      }
    }
  }

  /// Upload scalars may only appear as direct arguments on mutations.
  /// Throws if an upload scalar is used in an input field, type field,
  /// field argument, query argument, or subscription argument.
  void checkUploadScalarUsage() {
    final uploadNames = uploadScalarNames;
    if (uploadNames.isEmpty) return;

    // Not in input fields
    for (final input in inputs.values) {
      for (final field in input.fields) {
        if (_isUploadType(field.type, uploadNames)) {
          throw ParseException(
            "$glUpload scalar '${field.type.firstType.token}' is not allowed in input types — "
            "use it as a direct mutation argument only",
            info: field.name,
          );
        }
      }
    }

    // Not in type fields or their arguments.
    // Exception: the schema Mutation type may have upload args on its fields —
    // that is the intended declaration site. Query and Subscription may not.
    final mutationTypeName = schema.getByQueryType(GLQueryType.mutation);
    final queryTypeName = schema.getByQueryType(GLQueryType.query);
    final subscriptionTypeName = schema.getByQueryType(GLQueryType.subscription);
    final operationTypeNames = {queryTypeName, mutationTypeName, subscriptionTypeName};

    for (final type in types.values) {
      final isMutationType = type.token == mutationTypeName;

      for (final field in type.fields) {
        if (_isUploadType(field.type, uploadNames)) {
          throw ParseException(
            "$glUpload scalar '${field.type.firstType.token}' is not allowed as a field type",
            info: field.name,
          );
        }
        // Skip argument checks for Mutation type fields — those are valid.
        // For Query/Subscription fields and all regular type fields, uploads are forbidden.
        if (isMutationType) continue;

        for (final arg in field.arguments) {
          if (_isUploadType(arg.type, uploadNames)) {
            final context = operationTypeNames.contains(type.token)
                ? 'use it on mutation fields only'
                : 'use it as a direct mutation argument only';
            throw ParseException(
              "$glUpload scalar '${arg.type.firstType.token}' is not allowed as a field argument — $context",
              info: arg.tokenInfo,
            );
          }
        }
      }
    }

    // Not in queries or subscriptions
    for (final query in queries.values.where((q) => q.type != GLQueryType.mutation)) {
      for (final arg in query.arguments) {
        if (_isUploadType(arg.type, uploadNames)) {
          final opType = query.type == GLQueryType.query ? 'queries' : 'subscriptions';
          throw ParseException(
            "$glUpload scalar '${arg.type.firstType.token}' is not allowed on $opType — "
            "use it on mutations only",
            info: arg.tokenInfo,
          );
        }
      }
    }
  }

  /// Throws if any mutation upload argument is a list of lists (e.g. [[Upload!]!]).
  /// Only scalar or single-list upload types are allowed.
  void checkUploadListDepth() {
    final uploadNames = uploadScalarNames;
    if (uploadNames.isEmpty) return;

    for (final query in queries.values.where((q) => q.type == GLQueryType.mutation)) {
      for (final arg in query.arguments) {
        if (!_isUploadType(arg.type, uploadNames)) continue;
        final inner = arg.type is GLListType ? (arg.type as GLListType).type : null;
        if (inner is GLListType) {
          throw ParseException(
            "$glUpload scalar '${arg.type.firstType.token}' argument '${arg.tokenInfo.token}' "
            "must be a scalar or a single-level list — nested lists are not supported",
            info: arg.tokenInfo,
          );
        }
      }
    }
  }

  bool _isUploadType(GLType type, Set<String> uploadNames) =>
      uploadNames.contains(type.firstType.token);
}
