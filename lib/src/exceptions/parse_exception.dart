import 'dart:core';
import 'package:graphlink/src/model/token_info.dart';

class ParseException {
  final String message;
  final TokenInfo? info;

  ParseException(this.message, { this.info});

  @override
  String toString() {
    return errorMessage;
  }

  String get errorMessage {
    final info = this.info;
    if (info == null) return message;

    final buffer = StringBuffer('Parse error: $message');

    final location = info.fileName != null
        ? '${info.fileName}:${info.line}:${info.column}'
        : 'line ${info.line}, column ${info.column}';
    buffer.write('\n  --> $location');

    final sourceLine = info.sourceLine;
    if (sourceLine != null && info.line > 0) {
      final lineNum = '${info.line}';
      final pad = lineNum.length;
      final caretCol = (info.column - 1).clamp(0, sourceLine.length);
      buffer.write('\n${' ' * pad} |');
      buffer.write('\n$lineNum | $sourceLine');
      buffer.write('\n${' ' * pad} | ${' ' * caretCol}^');
    }

    return buffer.toString();
  }
}
