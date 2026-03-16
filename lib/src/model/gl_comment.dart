class GLComment {
  final String value;

  GLComment(this.value);

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
