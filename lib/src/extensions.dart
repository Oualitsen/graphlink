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
}
