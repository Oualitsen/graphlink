import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/member_field_conflict.dart';

class SkippedAutoQuery {
  final String name;
  final GLQueryType type;
  final int count;
  final int cap;
  final MemberFieldConflict? conflict;

  const SkippedAutoQuery({
    required this.name,
    required this.type,
    this.count = 0,
    this.cap = 0,
    this.conflict,
  });
}
