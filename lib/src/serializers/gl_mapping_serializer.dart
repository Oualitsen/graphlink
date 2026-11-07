import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';

abstract class GLMappingSerializer {
  const GLMappingSerializer();

  /// The `toXxx()` method of [def] → [targetType].
  String toMethod(GLInputDefinition def, String targetType, ToMappingPlan plan);

  /// The `fromXxx()` method of [targetType] → [def].
  String fromMethod(GLInputDefinition def, String targetType, FromMappingPlan plan);
}
