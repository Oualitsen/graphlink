import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/java_spring_server_serializer.dart';
import 'package:test/test.dart';

// Blocking Java Spring controllers call `runBefore` as a plain leading
// statement inside the `CompletableFuture` lambda — mirrors the Kotlin/TS
// coverage in this folder: one root-handler resolver, one batch-mapping
// field, plus an un-intercepted sibling of each to prove the directive is
// opt-in, not blanket coverage.
const _schema = '''
type Query {
  getSecretArticle(id: ID!): Article! @glIntercept(tag: "auth")
  getInternalHealth: Boolean!
  getPublisher: Publisher
}

type Article {
  id: ID!
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
  JavaSpringServerSerializer serializer(GLParser g) =>
      JavaSpringServerSerializer(g, packageName: 'dev.graphlink.test');

  test("intercepted root handler calls runBefore before the service call", () {
    final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server)..parse(_schema);
    final s = serializer(g);
    final tagMember = g.enums['GlInterceptorTag']!.values.firstWhere((v) => v.token == 'auth').codeName;
    final ctrl = g.controllers.values.firstWhere((c) => c.fields.any((f) => f.name.token == 'getSecretArticle'));
    final out = s.serializeController(ctrl);

    final runBeforeIdx = out.indexOf(
        'interceptor.runBefore(GlInterceptorTag.$tagMember, "getSecretArticle", Arrays.asList(id), graphQLContext)');
    final serviceCallIdx = out.indexOf('.getSecretArticle(');
    expect(runBeforeIdx, greaterThanOrEqualTo(0));
    expect(serviceCallIdx, greaterThan(runBeforeIdx));

    // un-intercepted root field lives in its own controller, with no
    // runBefore call at all.
    final healthCtrl =
        g.controllers.values.firstWhere((c) => c.fields.any((f) => f.name.token == 'getInternalHealth'));
    expect(s.serializeController(healthCtrl), isNot(contains('runBefore')));
  });

  test("intercepted batch mapping field calls runBefore before the service call", () {
    final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server)..parse(_schema);
    final s = serializer(g);
    final tagMember = g.enums['GlInterceptorTag']!.values.firstWhere((v) => v.token == 'auth').codeName;
    final ctrl = g.controllers.values.firstWhere((c) => c.mappings.any((m) => m.key == 'publisherBooks'));
    final out = s.serializeController(ctrl);

    final runBeforeIdx = out
        .indexOf('interceptor.runBefore(GlInterceptorTag.$tagMember, "Publisher.books", Arrays.asList(), graphQLContext)');
    final serviceCallIdx = out.indexOf('.publisherBooks(');
    expect(runBeforeIdx, greaterThanOrEqualTo(0));
    expect(serviceCallIdx, greaterThan(runBeforeIdx));

    // un-intercepted sibling batch field has no runBefore call at all.
    final authorsBlock = out.substring(out.indexOf('publisherAuthors'));
    expect(authorsBlock, isNot(contains('runBefore')));
  });
}
