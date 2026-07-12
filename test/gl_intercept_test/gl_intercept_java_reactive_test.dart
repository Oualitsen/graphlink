import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/java_spring_server_serializer.dart';
import 'package:test/test.dart';

// Reactive Java Spring controllers can't call `runBefore` as a blocking
// statement — it returns `Mono<Void>` and must be chained via
// `.then(Mono.defer(() -> …))` ahead of the real (lazily-built) service call,
// so denial short-circuits before that call is ever constructed. Mirrors the
// Kotlin/blocking-Java/TS coverage in this folder.
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
      JavaSpringServerSerializer(g, packageName: 'dev.graphlink.test', reactive: true);

  test("intercepted root handler chains runBefore before the reactive service call", () {
    final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server)..parse(_schema);
    final s = serializer(g);
    final tagMember = g.enums['GlInterceptorTag']!.values.firstWhere((v) => v.token == 'auth').codeName;
    final ctrl = g.controllers.values.firstWhere((c) => c.fields.any((f) => f.name.token == 'getSecretArticle'));
    final out = s.serializeController(ctrl);

    final runBeforeIdx = out.indexOf(
        'interceptor.runBefore(GlInterceptorTag.$tagMember, "getSecretArticle", Arrays.asList(id), graphQLContext)');
    final thenDeferIdx = out.indexOf('.then(Mono.defer(() -> articleService.getSecretArticle(');
    expect(runBeforeIdx, greaterThanOrEqualTo(0));
    expect(thenDeferIdx, greaterThan(runBeforeIdx));

    // un-intercepted root field lives in its own controller, with no
    // runBefore call at all.
    final healthCtrl =
        g.controllers.values.firstWhere((c) => c.fields.any((f) => f.name.token == 'getInternalHealth'));
    expect(s.serializeController(healthCtrl), isNot(contains('runBefore')));
  });

  test("intercepted batch mapping field chains runBefore before the reactive service call", () {
    final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server)..parse(_schema);
    final s = serializer(g);
    final tagMember = g.enums['GlInterceptorTag']!.values.firstWhere((v) => v.token == 'auth').codeName;
    final ctrl = g.controllers.values.firstWhere((c) => c.mappings.any((m) => m.key == 'publisherBooks'));
    final out = s.serializeController(ctrl);

    final runBeforeIdx = out
        .indexOf('interceptor.runBefore(GlInterceptorTag.$tagMember, "Publisher.books", Arrays.asList(), graphQLContext)');
    final thenDeferIdx = out.indexOf('.then(Mono.defer(() -> publisherSchemaMappingsService.publisherBooks(');
    expect(runBeforeIdx, greaterThanOrEqualTo(0));
    expect(thenDeferIdx, greaterThan(runBeforeIdx));

    // un-intercepted sibling batch field has no runBefore call at all.
    final authorsBlock = out.substring(out.indexOf('publisherAuthors'));
    expect(authorsBlock, isNot(contains('runBefore')));
  });
}
