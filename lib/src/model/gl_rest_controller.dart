import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

/// The REST adapter of one service: the REST operations of [service], bound to the same service interface the GraphQL controller uses.
class GLRestController extends GLToken {
  final GLService service;
  final List<GLRestOperation> operations;
  final GLParser parser;

  GLRestController({required this.service, required this.operations, required this.parser})
      : super('${service.token}RestController'.toToken());

  String get serviceName => service.token;

  @override
  Set<GLToken> getImportDependecies(GLParser g) => {...super.getImportDependecies(g), service};
}
