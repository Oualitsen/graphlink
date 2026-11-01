import 'package:graphlink/src/extensions.dart';

/// Defines how raw GraphQL identifiers are mapped to target-language identifiers.
///
/// Two separate transforms are needed because field and enum-value casing follow
/// different conventions in some languages (Java: lowerCamelCase fields vs
/// SCREAMING_SNAKE enum values).
///
/// Use the pre-built static instances ([dart], [java], [kotlin], [typescript])
/// in generators. In tests you can supply anonymous instances directly.
class NamingConvention {
  final String Function(String) field;
  final String Function(String) enumValue;

  /// Converts a raw GraphQL type / input / union / enum definition name to the
  /// target-language class name.  All supported languages use PascalCase for
  /// class names, so this defaults to [String.toPascalCase] and rarely needs
  /// to be overridden.
  final String Function(String) typeName;

  /// Derives the `<stem>Response` / `<stem>FullResponse` name stem from an
  /// operation's code name. Null keeps the default (first letter upper-cased),
  /// which is only right when operation names are already camelCase.
  final String Function(String)? generatedTypeStem;

  NamingConvention({
    required this.field,
    required this.enumValue,
    String Function(String)? typeName,
    this.generatedTypeStem,
  }) : typeName = typeName ?? ((s) => s.toPascalCase());

  /// Dart/Flutter: lowerCamelCase for both fields and enum values.
  static final NamingConvention dart = NamingConvention(
    field: (s) => s.toLowerCamelCase(),
    enumValue: (s) => s.toLowerCamelCase(),
  );

  /// Java: lowerCamelCase fields, SCREAMING_SNAKE enum values.
  static final NamingConvention java = NamingConvention(
    field: (s) => s.toLowerCamelCase(),
    enumValue: (s) => s.toScreamingSnakeCase(),
  );

  /// Kotlin: lowerCamelCase fields, SCREAMING_SNAKE enum values.
  static final NamingConvention kotlin = NamingConvention(
    field: (s) => s.toLowerCamelCase(),
    enumValue: (s) => s.toScreamingSnakeCase(),
  );

  /// TypeScript: lowerCamelCase fields, PascalCase enum values.
  static final NamingConvention typescript = NamingConvention(
    field: (s) => s.toLowerCamelCase(),
    enumValue: (s) => s.toPascalCase(),
  );

  /// Swift: lowerCamelCase for both fields and enum `case` names — Swift's
  /// own convention for enum cases is lowerCamelCase (`case admin`), unlike
  /// Kotlin/Java's SCREAMING_SNAKE or TypeScript's PascalCase.
  static final NamingConvention swift = NamingConvention(
    field: (s) => s.toLowerCamelCase(),
    enumValue: (s) => s.toLowerCamelCase(),
  );

  /// Python: snake_case fields (the wire name is kept as the pydantic alias),
  /// SCREAMING_SNAKE enum members.
  static final NamingConvention python = NamingConvention(
    field: (s) => s.toSnakeCaseWords(),
    enumValue: (s) => s.toScreamingSnakeCase(),
    generatedTypeStem: (s) => s.toPascalCase(),
  );

  /// Go: every field, operation and enum member is exported (PascalCase);
  /// encoding/json needs exported fields and the wire name travels in the struct tag.
  static final NamingConvention go = NamingConvention(
    field: (s) => s.toPascalCase(),
    enumValue: (s) => s.toPascalCase(),
    generatedTypeStem: (s) => s.toPascalCase(),
  );
}
