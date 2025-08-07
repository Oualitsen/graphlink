import 'dart:core';
import 'package:retrofit_graphql/src/model/token_info.dart';

class ParseException {
  final String message;
  final TokenInfo? info;

  ParseException(this.message, { this.info});

  @override
  String toString() {
    return errorMessage;
  }

  String get errorMessage {
    var info = this.info;
    if(info == null) {
      return message;
    }
    var buffer = StringBuffer(message);
    if(info.fileName != null) {
      buffer.write(" at file: ${info.fileName ?? ''}");
    }
    buffer.write(' line: ${info.line + 1} column: ${info.column}');
    return buffer.toString();
  }
}
