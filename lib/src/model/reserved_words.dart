/// Target-language reserved words. A GraphQL field/input-field may legally be
/// named after one of these (GraphQL has no global reserved words), but the
/// generated identifier must be sanitized so the output compiles. See
/// [GLTokenWithFields.assignCodeNames].

/// Dart reserved words and built-in identifiers that cannot be used as a plain
/// field/parameter name.
const Set<String> dartReservedWords = {
  // Reserved words (cannot be identifiers at all).
  'assert', 'break', 'case', 'catch', 'class', 'const', 'continue', 'default',
  'do', 'else', 'enum', 'extends', 'false', 'final', 'finally', 'for', 'if',
  'in', 'is', 'new', 'null', 'rethrow', 'return', 'super', 'switch', 'this',
  'throw', 'true', 'try', 'var', 'void', 'while', 'with',
  // Built-in identifiers / contextual words that are unsafe as field names.
  'abstract', 'as', 'covariant', 'deferred', 'dynamic', 'export', 'external',
  'factory', 'function', 'get', 'implements', 'import', 'interface', 'late',
  'library', 'mixin', 'operator', 'part', 'required', 'set', 'static',
  'typedef',
};

/// Java reserved words (and literals) that cannot be used as a field name,
/// parameter name, or local variable.
const Set<String> javaReservedWords = {
  'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char',
  'class', 'const', 'continue', 'default', 'do', 'double', 'else', 'enum',
  'extends', 'final', 'finally', 'float', 'for', 'goto', 'if', 'implements',
  'import', 'instanceof', 'int', 'interface', 'long', 'native', 'new',
  'package', 'private', 'protected', 'public', 'return', 'short', 'static',
  'strictfp', 'super', 'switch', 'synchronized', 'this', 'throw', 'throws',
  'transient', 'try', 'void', 'volatile', 'while',
  'true', 'false', 'null',
};

/// Kotlin hard keywords. Note `default` is NOT reserved in Kotlin (only used
/// inside annotations); `object`, `is`, `in`, `fun`, `val`, `when`, etc. are.
const Set<String> kotlinReservedWords = {
  'as', 'break', 'class', 'continue', 'do', 'else', 'false', 'for', 'fun',
  'if', 'in', 'interface', 'is', 'null', 'object', 'package', 'return',
  'super', 'this', 'throw', 'true', 'try', 'typealias', 'typeof', 'val',
  'var', 'when', 'while',
};

/// TypeScript intentionally has NO reserved set: it accesses both fields and
/// arguments as object properties (`{ default: T }`, `args.default`), and
/// reserved words are legal as property names / in member access. So neither
/// fields nor query arguments need sanitizing for TypeScript.
const Set<String> typescriptReservedWords = <String>{};
