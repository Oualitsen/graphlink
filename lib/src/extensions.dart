import 'package:retrofit_graphql/src/model/token_info.dart';

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
    final indentStr = '\t' * num;
    return split('\n').map((line) => line.isEmpty ? line : '$indentStr$line').join('\n');
  }

  String removeQuotes() {
    var trimed = trim();
    if (trimed.startsWith("'''") && trimed.endsWith("'''") ||
        trimed.startsWith('"""') && trimed.endsWith('"""')) {
      return trimed.substring(3, trimed.length - 3);
    }
    if (trimed.startsWith("'") && trimed.endsWith("'") || trimed.startsWith('"') && trimed.endsWith('"')) {
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
    var split = removeQuotes().trim().split(RegExp(r'[\r\n]+')).where((str) => str.isNotEmpty).toList();
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

  TokenInfo toToken() => TokenInfo.ofString(this);
}
