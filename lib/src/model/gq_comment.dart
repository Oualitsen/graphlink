class GQComment {
  final String value;

  GQComment(this.value);

  @override
  String toString() {
    return value;
  }
}

class GQDocumentation {
  final String value;
  final bool singleLine;

  GQDocumentation(this.value, this.singleLine);
}
