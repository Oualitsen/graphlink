import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';

abstract class GLMappingSerializer {
  const GLMappingSerializer();

  /// The `to<Target>()` method of [def] → [target].
  String toMethod(GLTokenWithFields def, GLTokenWithFields target, ToMappingPlan plan);
}
