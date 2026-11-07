import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

extension GLGrammarRecursionExtension on GLParser {
  /// True when [field] holds a value of an object or input type that can contain
  /// [owner] again without going through a list, so a language that stores such
  /// members inline (a Swift struct) needs an indirection to give the owner a
  /// finite size. Interfaces and unions are existential and lists are
  /// heap-allocated, so neither closes a cycle.
  bool isRecursiveField(GLTokenWithFields owner, GLField field) {
    final target = _directTarget(field);
    return target != null && _reaches(target, owner.token, {});
  }

  String? _directTarget(GLField field) {
    if (field.type.isList) return null;
    final token = field.type.token;
    return types.containsKey(token) || inputs.containsKey(token) ? token : null;
  }

  bool _reaches(String from, String goal, Set<String> seen) {
    if (from == goal) return true;
    if (!seen.add(from)) return false;
    final node = types[from] ?? inputs[from];
    if (node == null) return false;
    for (final field in node.fields) {
      final next = _directTarget(field);
      if (next != null && _reaches(next, goal, seen)) return true;
    }
    return false;
  }
}
