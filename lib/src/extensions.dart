extension StringExt on String {
  String get firstUp {
    if(isEmpty) {
      return "";
    }
    var firstLetter = this[0].toUpperCase();
    var theRest = length == 1 ? "": substring(1);
    return "$firstLetter$theRest";
  }

  String get firstLow {
    if(isEmpty) {
      return "";
    }
    var firstLetter = this[0].toLowerCase();
    var theRest = length == 1 ? "": substring(1);
    return "$firstLetter$theRest";
  }
}