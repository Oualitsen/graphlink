import 'dart:core';
import 'package:petitparser/petitparser.dart';

class ParseException {
  final String message;
  final Parser? parser;
  final String? parserName;
  final String? fileName;
  final int? line;
  final int? column;

  ParseException(this.message,
      {this.parser, this.parserName, this.fileName, this.line, this.column});

  @override
  String toString() {
    return "$message ${parserName ?? ''}";
  }
}
