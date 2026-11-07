import 'package:graphlink/src/model/new_parser/gl_parser.dart';

extension GLGrammarDefaultsExtension on GLParser {
  /// A default object value (`= {n: 9}`) with the members it leaves out taken from
  /// the declared defaults of the input type, in declaration order. A server
  /// applies those itself, a client that sends the value as is must not drop them.
  Map<String, Object?> completeInputDefault(String inputToken, Map value) {
    final input = inputs[inputToken];
    if (input == null) return {for (final e in value.entries) '${e.key}': e.value};
    final completed = <String, Object?>{};
    for (final field in input.fields) {
      final name = field.name.token;
      if (value.containsKey(name)) {
        completed[name] = value[name];
      } else if (field.initialValue != null) {
        completed[name] = field.initialValue;
      }
    }
    return completed;
  }
}
