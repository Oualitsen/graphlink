import 'package:graphlink_dart_errors_real_tests/generated/graphlink.dart';
import 'package:test/test.dart';

const _url = 'http://127.0.0.1:9930/graphql';

void main() {
  late GraphLinkClient client;

  setUp(() => client = GraphLinkClient.withHttp(url: _url));

  Future<Object> thrownBy(Future<Object?> Function() call) async {
    try {
      await call();
    } catch (e) {
      return e;
    }
    fail('expected an exception');
  }

  group('queries', () {
    test('a successful call returns its data', () async {
      final res = await client.queries.article(id: '1');
      expect(res.article!.id, '1');
    });

    test('a declared error is thrown as its class and carries its fields', () async {
      final e = await thrownBy(() => client.queries.article(id: 'missing'));
      expect(e, isA<ArticleNotFound>());
      expect((e as ArticleNotFound).id, 'missing');
      expect(e.message, 'Article missing not found');
      expect(e, isA<GraphLinkDomainError>());
    });

    test('it can be caught by type', () async {
      var caught = '';
      try {
        await client.queries.article(id: 'missing');
      } on ArticleNotFound catch (e) {
        caught = e.id;
      }
      expect(caught, 'missing');
    });

    test('an error matched on a custom field and value', () async {
      final e = await thrownBy(() => client.queries.article(id: 'forbidden'));
      expect(e, isA<Forbidden>());
      expect((e as Forbidden).message, 'No access');
    });

    test('an error of another root field', () async {
      expect(await thrownBy(() => client.queries.secret()), isA<Forbidden>());
    });

    test('an unknown code keeps the original errors list', () async {
      final e = await thrownBy(() => client.queries.article(id: 'other-code'));
      expect(e, isA<List<GraphLinkError>>());
      expect((e as List<GraphLinkError>).single.message, 'A new error');
    });

    test('a missing required field falls back to the errors list', () async {
      expect(await thrownBy(() => client.queries.article(id: 'no-field')), isA<List<GraphLinkError>>());
    });

    test('an entry without a path falls back to the errors list', () async {
      expect(await thrownBy(() => client.queries.article(id: 'no-path')), isA<List<GraphLinkError>>());
    });

    test('an entry without extensions falls back to the errors list', () async {
      expect(await thrownBy(() => client.queries.article(id: 'no-extensions')), isA<List<GraphLinkError>>());
    });

    test('an operation without @glThrows keeps the errors list', () async {
      final e = await thrownBy(() => client.queries.plain(id: '1'));
      expect(e, isA<List<GraphLinkError>>());
      expect(e, isNot(isA<GraphLinkDomainError>()));
    });

    test('a combined query keeps the errors list', () async {
      final e = await thrownBy(() => client.queries.pair());
      expect(e, isA<List<GraphLinkError>>());
      expect((e as List<GraphLinkError>).single.path, ['first']);
    });

    test('a capture-errors operation returns the errors and throws nothing', () async {
      final res = await client.queries.captured();
      expect(res.errors!.single.extensions!['code'], 'ArticleNotFound');
    });
  });

  group('mutations', () {
    test('a successful call returns its data', () async {
      final res = await client.mutations.createArticle(input: ArticleInput(title: 'fresh'));
      expect(res.createArticle!.id, 'fresh');
    });

    test('a declared error carries a list field', () async {
      final e = await thrownBy(() => client.mutations.createArticle(input: ArticleInput(title: 'taken')));
      expect(e, isA<TitleTaken>());
      expect((e as TitleTaken).title, 'taken');
      expect(e.suggestions, ['taken-2']);
    });

    test('an error with its own value, an enum and an optional field', () async {
      final e = await thrownBy(() => client.mutations.createArticle(input: ArticleInput(title: 'banned')));
      expect(e, isA<Banned>());
      expect((e as Banned).reason, Reason.spam);
      expect(e.until, 5);
    });
  });
}
