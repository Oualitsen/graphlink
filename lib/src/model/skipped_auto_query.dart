import 'package:graphlink/src/model/gl_queries.dart';

class SkippedAutoQuery {
  final String name;
  final GLQueryType type;
  final int count;
  final int cap;

  const SkippedAutoQuery({
    required this.name,
    required this.type,
    required this.count,
    required this.cap,
  });
}
