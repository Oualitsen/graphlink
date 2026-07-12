import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';

const glInterceptorTagEnumName = "GlInterceptorTag";
const glInterceptorInterfaceName = "GraphLinkInterceptor";
const glInterceptorRunBeforeMethod = "runBefore";

const glInterceptorTagArgName = "tag";
const glInterceptorOperationArgName = "operation";
const glInterceptorArgsArgName = "args";

extension GLGrammarInterceptExtension on GLParser {
  /// True when [field] itself, or (for a root field) its declaring
  /// `type`/`extend type` block, carries `@glIntercept`.
  bool isIntercepted(GLField field, [GLQueryType? type]) {
    if (field.hasDirective(glIntercept)) return true;
    if (type == null) return false;
    return _declaringBlockDirective(field, type) != null;
  }

  /// Resolved tag for an intercepted [field] — the field's own `tag` wins over
  /// the declaring block's. Only meaningful when [isIntercepted] is true.
  String? interceptTag(GLField field, [GLQueryType? type]) {
    final fieldDirective = field.getDirectiveByName(glIntercept);
    if (fieldDirective != null) {
      return fieldDirective.getArgValueAsString(glInterceptTagArg);
    }
    if (type == null) return null;
    return _declaringBlockDirective(field, type)
        ?.getArgValueAsString(glInterceptTagArg);
  }

  /// The `@glIntercept` directive on the `type`/`extend type` block that
  /// lexically declared [field], or `null`.
  GLDirectiveValue? _declaringBlockDirective(GLField field, GLQueryType type) {
    final typeName = schema.getByQueryType(type);
    return interceptBlockDirectiveCache['$typeName.${field.name.token}'];
  }

  /// Snapshots each `@glIntercept`-carrying block's directive per field before
  /// `mergeTokens()` runs, so merging extend blocks doesn't leak one block's
  /// directive onto a sibling block's fields.
  void captureInterceptBlockScopes() {
    for (final type in GLQueryType.values) {
      final typeName = schema.getByQueryType(type);
      final blocks = extensibleTokens[typeName]?.data ?? const [];
      for (final block in blocks) {
        if (block is! GLTypeDefinition) continue;
        final blockDirective = block.getDirectiveByName(glIntercept);
        if (blockDirective == null) continue;
        for (final field in block.fields) {
          interceptBlockDirectiveCache['$typeName.${field.name.token}'] =
              blockDirective;
        }
      }
    }
  }

  /// True when the schema uses `@glIntercept` anywhere.
  bool get usesInterceptor =>
      directiveValues.any((d) => d.token == glIntercept);

  /// Distinct, non-null raw tag strings used across every `@glIntercept`
  /// usage, in first-seen order.
  List<String> get distinctInterceptTags {
    final seen = <String>{};
    final result = <String>[];
    for (final directive in directiveValues) {
      if (directive.token != glIntercept) continue;
      final tag = directive.getArgValueAsString(glInterceptTagArg);
      if (tag == null) continue;
      if (seen.add(tag)) result.add(tag);
    }
    return result;
  }

  /// Raw tag string -> sanitized `GlInterceptTag` enum member name.
  Map<String, String> get interceptTagEnumMembers {
    final sanitize = naming?.enumValue ?? (String s) => s.toPascalCase();
    return {for (final tag in distinctInterceptTags) tag: sanitize(tag)};
  }

  /// Validates every `@glIntercept(tag: ...)` usage: the tag must be a
  /// non-blank string, and no two distinct tags may sanitize to the same enum
  /// member.
  void validateInterceptTagValues() {
    for (final directive in directiveValues) {
      if (directive.token != glIntercept) continue;
      final rawValue = directive.getArgValue(glInterceptTagArg);
      if (rawValue == null) continue;
      if (rawValue is! String) {
        throw ParseException(
          "$glInterceptTagArg on $glIntercept must be a string! found: $rawValue",
          info: directive.tokenInfo,
        );
      }
      if (rawValue.removeQuotes().trim().isEmpty) {
        throw ParseException(
          "$glInterceptTagArg on $glIntercept must not be blank",
          info: directive.tokenInfo,
        );
      }
    }

    final membersByTag = interceptTagEnumMembers;
    final tagsByMember = <String, List<String>>{};
    membersByTag.forEach((tag, member) {
      tagsByMember.putIfAbsent(member, () => []).add(tag);
    });
    for (final entry in tagsByMember.entries) {
      if (entry.value.length > 1) {
        throw ParseException(
          "Distinct $glIntercept tags ${entry.value.map((t) => '"$t"').join(', ')} "
          "all sanitize to the same GlInterceptTag enum member '${entry.key}' — "
          "rename one of them so each tag maps to a distinct member.",
        );
      }
    }
  }

  /// `@glIntercept` is only meaningful on a field with a resolver to guard —
  /// a root Query/Mutation/Subscription field or a `@glSkipOnServer` mapping
  /// field. Rejects any other placement (plain object/input fields).
  void validateInterceptPlacement() {
    final rootTypeNames =
        GLQueryType.values.map((t) => schema.getByQueryType(t)).toSet();

    for (final entry in extensibleTokens.entries) {
      final isRootType = rootTypeNames.contains(entry.key);
      for (final block in entry.value.data) {
        if (block is GLTypeDefinition) {
          final blockDirective = block.getDirectiveByName(glIntercept);
          if (blockDirective != null && !isRootType) {
            throw ParseException(
              "$glIntercept can only be applied to a Query/Mutation/Subscription "
              "root type, found on '${entry.key}'",
              info: blockDirective.tokenInfo,
            );
          }
          for (final field in block.fields) {
            final fieldDirective = field.getDirectiveByName(glIntercept);
            if (fieldDirective == null || isRootType) continue;
            if (field.hasDirective(glSkipOnServer)) continue;
            throw ParseException(
              "$glIntercept can only be applied to a Query/Mutation/Subscription "
              "root field, found on '${entry.key}.${field.name.token}' — it has no resolver to guard",
              info: fieldDirective.tokenInfo,
            );
          }
        } else if (block is GLInputDefinition) {
          for (final field in block.fields) {
            final fieldDirective = field.getDirectiveByName(glIntercept);
            if (fieldDirective == null) continue;
            throw ParseException(
              "$glIntercept cannot be applied to input field '${entry.key}.${field.name.token}' — "
              "it is a resolver-only directive",
              info: fieldDirective.tokenInfo,
            );
          }
        }
      }
    }
  }

  /// Registers the `GlInterceptorTag` enum (one member per distinct tag used
  /// in the schema). Server mode only; skipped if no tag was ever declared.
  void registerInterceptorTagEnum() {
    if (mode != CodeGenerationMode.server) return;
    final tags = distinctInterceptTags;
    if (tags.isEmpty) return;
    addEnumDefinition(GLEnumDefinition(
      token: glInterceptorTagEnumName.toToken(),
      values: tags.map((tag) => GLEnumValue(
            value: tag.toToken(),
            documentation: null,
            directives: [],
          )),
      directives: [],
      extension: false,
      skipOnGraphqlSerialization: true,
    ));
  }

  /// Registers the `GraphLinkInterceptor` interface (a single `runBefore`
  /// method). `context`/`info` are appended per-target by each server
  /// serializer instead, not modeled here.
  void registerInterceptorInterface() {
    if (mode != CodeGenerationMode.server) return;
    if (!usesInterceptor) return;

    final tagEnumRegistered = enums.containsKey(glInterceptorTagEnumName);
    final arguments = <GLArgumentDefinition>[
      if (tagEnumRegistered)
        GLArgumentDefinition(
          glInterceptorTagArgName.toToken(),
          GLType(glInterceptorTagEnumName.toToken(), true),
          [],
        ),
      GLArgumentDefinition(
        glInterceptorOperationArgName.toToken(),
        GLType("String".toToken(), false),
        [],
      ),
      GLArgumentDefinition(
        glInterceptorArgsArgName.toToken(),
        GLListType(GLType("dynamicValue".toToken(), false), false),
        [],
      ),
    ];

    final runBefore = GLField(
      name: glInterceptorRunBeforeMethod.toToken(),
      type: GLVoidType(),
      arguments: arguments,
      directives: [],
    );

    addInterfaceDefinition(GLInterfaceDefinition(
      name: glInterceptorInterfaceName.toToken(),
      nameDeclared: false,
      fields: [runBefore],
      directives: [],
      interfaceNames: {},
      extension: false,
      fieldAsMethods: true,
      skipJsonMethods: true,
      skipOnGraphqlSerialization: true,
    ));
  }
}
