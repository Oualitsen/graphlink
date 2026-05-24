import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

export 'package:graphlink/src/serializers/server_serializer_utils.dart';

abstract class ServerSerializer {
  final GLParser grammar;

  ServerSerializer(this.grammar);

  String serializeService(GLService service);
  String? serializeGuard(GLService service);
  List<String> serializeResolvers();
  String serializeTypeDefs();
  String serializeContext() => '';
  String serializeEntryPoint() => '';
}
