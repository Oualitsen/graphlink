import 'package:graphlink/src/kotlin_code_gen_utils.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';

/// Bundles shared infrastructure for [KotlinClientSerializer] and its helpers.
/// Generated variable name constants live in [kotlin_client_vars.dart].
class KotlinClientContext {
  final GLParser grammar;
  final KotlinCodeGenUtils codeGenUtils;
  final GLGraphqlSerializer gqlSerializer;
  final GLSerializer serializer;

  const KotlinClientContext(this.grammar, this.codeGenUtils, this.gqlSerializer, this.serializer);
}
