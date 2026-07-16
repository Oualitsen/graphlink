import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/express_apollo_server_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';

void main() {
  final g = GLParser()..parse('type Query { noop: String }');
  final ts = TypeScriptSerializer(g, importPrefix: 'test');
  final serializer = ExpressApolloServerSerializer(g, ts);
  print(serializer.serializeContextStub('lib/generated'));
}
