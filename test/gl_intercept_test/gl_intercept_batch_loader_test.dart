import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/express_apollo_server_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';

// A `@glSkipOnServer(batch: true)` mapping field is resolved through a
// DataLoader (`context.loaders.<key>.load(parent)`) rather than a direct
// service call. @glIntercept there must call runBefore once per resolved
// parent, before the loader is enqueued — the batch function itself
// (createXxxLoader) only sees an already-collapsed array of parents, so it's
// the wrong place to attribute a single caller's check to.
const _schema = '''
type Query {
  getPublisher: Publisher
}

type Publisher {
  id: ID!
  books: [Book!] @glSkipOnServer(batch: true) @glIntercept(tag: "auth")
  authors: [Author!] @glSkipOnServer(batch: true)
}

type Book { id: ID! }
type Author { id: ID! }
''';

void main() {
  ExpressApolloServerSerializer serializer(GLParser g) => ExpressApolloServerSerializer(
        g,
        TypeScriptSerializer(g, importPrefix: ''),
        ExpressApolloServerConfig(),
      );

  test("intercepted batch field calls runBefore before the loader is enqueued", () {
    final g = GLParser(mode: CodeGenerationMode.server)..parse(_schema);
    final out = serializer(g).serializeResolvers().join('\n');

    final runBeforeIdx = out.indexOf('interceptor.runBefore(GlInterceptorTag.auth, "Publisher.books", [], context)');
    final loadIdx = out.indexOf('context.loaders.publisherBooks.load(parent)');
    expect(runBeforeIdx, greaterThanOrEqualTo(0));
    expect(loadIdx, greaterThan(runBeforeIdx));
  });

  test("non-intercepted batch field keeps the plain synchronous .then() form, no runBefore", () {
    final g = GLParser(mode: CodeGenerationMode.server)..parse(_schema);
    final out = serializer(g).serializeResolvers().join('\n');

    final authorsBlock = out.substring(out.indexOf('authors:'));
    expect(authorsBlock, isNot(contains('runBefore')));
    expect(authorsBlock, contains('.load(parent).then('));
  });
}
