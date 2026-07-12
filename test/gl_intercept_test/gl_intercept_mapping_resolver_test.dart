import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/express_apollo_server_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';

// A non-batch `@glSkipOnServer` mapping field (calls a service method with
// `parent` as its synthetic `value` arg) is the "general" branch of
// `_mappingResolver` — @glIntercept there must call runBefore before the
// service call, same as a root resolver does before its own service call.
const _schema = '''
type Query {
  getUser: User
}

type User {
  id: ID!
  owner: Owner! @glSkipOnServer(batch: false) @glIntercept(tag: "auth")
  pet: Pet! @glSkipOnServer(batch: false)
}

type Owner { id: ID! }
type Pet { id: ID! }
''';

void main() {
  ExpressApolloServerSerializer serializer(GLParser g) => ExpressApolloServerSerializer(
        g,
        TypeScriptSerializer(g, importPrefix: ''),
        ExpressApolloServerConfig(),
      );

  test("intercepted non-batch mapping field calls runBefore before the service call", () {
    final g = GLParser(mode: CodeGenerationMode.server)..parse(_schema);
    final out = serializer(g).serializeResolvers().join('\n');

    final runBeforeIdx = out.indexOf('interceptor.runBefore(GlInterceptorTag.auth, "User.owner", [], context)');
    final serviceCallIdx = out.indexOf('userOwner(');
    expect(runBeforeIdx, greaterThanOrEqualTo(0));
    expect(serviceCallIdx, greaterThan(runBeforeIdx));
  });

  test("non-intercepted non-batch mapping field has no runBefore call", () {
    final g = GLParser(mode: CodeGenerationMode.server)..parse(_schema);
    final out = serializer(g).serializeResolvers().join('\n');

    final petBlock = out.substring(out.indexOf('pet:'));
    expect(petBlock, isNot(contains('runBefore')));
  });
}
