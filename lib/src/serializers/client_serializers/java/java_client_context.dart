import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_reactive_flavor.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';

/// Bundles shared infrastructure for [JavaClientSerializer] and its helpers.
/// Generated variable name constants live in [java_client_vars.dart].
class JavaClientContext {
  final GLParser grammar;
  final JavaCodeGenUtils codeGenUtils;
  final GLGraphqlSerializer gqlSerializer;
  final GLSerializer serializer;
  final JavaReactiveFlavor flavor;

  const JavaClientContext(
    this.grammar,
    this.codeGenUtils,
    this.gqlSerializer,
    this.serializer, {
    this.flavor = JavaReactiveFlavor.blocking,
  });
}
