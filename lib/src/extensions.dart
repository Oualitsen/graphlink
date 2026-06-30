import 'package:graphlink/src/model/token_info.dart';

extension StringExt on String {
  String get firstUp {
    if (isEmpty) {
      return "";
    }
    var firstLetter = this[0].toUpperCase();
    var theRest = length == 1 ? "" : substring(1);
    return "$firstLetter$theRest";
  }

  String get firstLow {
    if (isEmpty) {
      return "";
    }
    var firstLetter = this[0].toLowerCase();
    var theRest = length == 1 ? "" : substring(1);
    return "$firstLetter$theRest";
  }

  String ident([int num = 1]) {
    String ident = " " * 3;
    final indentStr = ident * num;
    return split('\n').map((line) => line.isEmpty ? line : '$indentStr$line').join('\n');
  }

  String removeQuotes() {
    var trimed = trim();
    if (trimed.startsWith("'''") && trimed.endsWith("'''") ||
        trimed.startsWith('"""') && trimed.endsWith('"""')) {
      return trimed.substring(3, trimed.length - 3);
    }
    if (trimed.startsWith("'") && trimed.endsWith("'") ||
        trimed.startsWith('"') && trimed.endsWith('"')) {
      return trimed.substring(1, trimed.length - 1);
    }
    return this;
  }

  String quote({bool multiline = false}) {
    if (multiline) {
      return '"""${replaceAll('"', '\\"')}"""';
    } else {
      return '"${replaceAll('"', '\\"')}"';
    }
  }

  String toJavaString({bool noNewLines = false}) {
    var split =
        removeQuotes().trim().split(RegExp(r'[\r\n]+')).where((str) => str.isNotEmpty).toList();
    final result = split.map((str) {
      if (str == split.last) {
        return str.quote();
      }
      return "${str}\\n".quote();
    }).join(" + ${noNewLines ? '' : '\n'}");
    return result;
  }

  String dolarEscape() {
    return replaceFirst("\$", "\\\$");
  }

  /// Escapes `\`, `"`, and `$` so the string can be embedded safely inside a
  /// Kotlin double-quoted string literal where `$` triggers interpolation.
  String escapeForStringLiteral() {
    return replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll(r'$', r'\$');
  }

  /// Escapes `\` and `"` so the string can be embedded safely inside a
  /// Java double-quoted string literal.
  String escapeForJavaStringLiteral() {
    return replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  }

  TokenInfo toToken() => TokenInfo.ofString(this);

  /// Splits any identifier into lowercase word tokens.
  /// Handles PascalCase, camelCase, SCREAMING_SNAKE, snake_case, kebab-case,
  /// and mixed abbreviations (HTMLParser → [html, parser]).
  List<String> _splitIntoWords() {
    return replaceAll(RegExp(r'[-_]+'), ' ')
        .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAllMapped(RegExp(r'([A-Z]+)([A-Z][a-z])'), (m) => '${m[1]} ${m[2]}')
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  /// Any case → lowerCamelCase. Wire name is never touched.
  String toLowerCamelCase() {
    final words = _splitIntoWords();
    if (words.isEmpty) return this;
    return words.first + words.skip(1).map((w) => w[0].toUpperCase() + w.substring(1)).join();
  }

  /// Any case → PascalCase.
  String toPascalCase() {
    final words = _splitIntoWords();
    if (words.isEmpty) return this;
    return words.map((w) => w[0].toUpperCase() + w.substring(1)).join();
  }

  /// Any case → SCREAMING_SNAKE_CASE.
  String toScreamingSnakeCase() {
    final words = _splitIntoWords();
    if (words.isEmpty) return this;
    return words.join('_').toUpperCase();
  }

  String toSnakeCase() {
    final snake = replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (Match m) => '${m[1]}_${m[2]}',
    );
    return snake.toLowerCase();
  }

  String toKebabCase() {
    final kebab = replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (Match m) => '${m[1]}-${m[2]}',
    );
    return kebab.toLowerCase();
  }
}
