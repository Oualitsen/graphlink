import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

extension GLQueryCaptureErrors on GLQueryDefinition {
  bool isCaptureErrors(GLParser parser) =>
      parser.captureErrors ||
      (elements.isNotEmpty && elements.first.hasDirective(glCaptureErrors));
}
