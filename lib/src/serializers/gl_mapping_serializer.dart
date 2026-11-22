import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';

abstract class GLMappingSerializer {
  const GLMappingSerializer();

  /// The `to<Target>()` method of [def] → [target].
  String toMethod(GLTokenWithFields def, GLTokenWithFields target, ToMappingPlan plan);

  /// The `to<Target>(source)` function of the mapper class of [def] → [target].
  String mapperMethod(GLTokenWithFields def, GLTokenWithFields target, ToMappingPlan plan);

  /// The whole file of the mapper class of [def], holding [methods].
  String mapperFile(GLTokenWithFields def, List<String> methods, List<String> imports);

  /// The import line that brings the mapper class of [def] into another mapper file.
  String mapperImport(GLTokenWithFields def);

  String mapperFileName(GLTokenWithFields def);

  String mapperName(GLTokenWithFields def) => '${def.mappingCodeName}Mapper';
}
