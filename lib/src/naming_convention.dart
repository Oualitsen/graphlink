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

  NamingConvention({required this.field, required this.enumValue});

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
}
