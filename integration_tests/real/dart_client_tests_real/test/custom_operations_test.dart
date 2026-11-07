import 'package:graphlink_client_integration_tests/generated/graphlink.dart';
import 'package:test/test.dart';

import 'real_server_adapter.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  group('named fragments', () {
    test('a fragment that spreads another fragment', () async {
      final u = (await client.queries.fragNested(id: 'user-1')).getUser;
      expect([u.id, u.name], ['user-1', 'Alice Smith']);
      expect(u.status, UserStatus.active);
    });

    test('one fragment reused by two operations', () async {
      final all = (await client.queries.fragReuseA()).listUsers;
      expect(all.map((u) => u.id), containsAll(['user-1', 'user-2']));
      final one = (await client.queries.fragReuseB(id: 'user-2')).getUser;
      expect([one.id, one.name], ['user-2', 'Bob Jones']);
      expect(one.email, isNotNull);
    });

    test('a fragment on an interface next to an inline fragment on a member', () async {
      final feed = (await client.queries.fragOnInterface()).feed;
      expect(feed, isNotEmpty);
      expect(feed.every((e) => e.id.isNotEmpty && e.createdBy.isNotEmpty), isTrue);
    });

    test('several root fields sharing one fragment', () async {
      final r = await client.queries.multiRoot();
      expect(r.first.name, 'Alice Smith');
      expect(r.second.name, 'Bob Jones');
      expect(r.all.map((u) => u.id), containsAll(['user-1', 'user-2']));
    });
  });

  group('variables', () {
    test('defaults apply when the variable is not given', () async {
      final r = (await client.queries.varsDefaults()).searchUsers;
      expect(r, hasLength(1));
    });

    test('an explicit value replaces the default', () async {
      expect((await client.queries.varsDefaults(name: 'Alice', limit: 5)).searchUsers.map((u) => u.id), ['user-1']);
    });

    test('list, nested list and enum variables', () async {
      final r = (await client.queries.varsLists(
        a: [1, 2], b: [1, null], c: [[1], [2, 3]], e: [Spelling.xY], f: [null, Spelling.v1],
      )).echoArgs;
      expect(r.a, [1, 2]);
      expect(r.b, [1, null]);
      expect(r.c, [[1], [2, 3]]);
      expect(r.e, [Spelling.xY]);
      expect(r.f, [null, Spelling.v1]);
    });

    test('a nullable enum variable', () async {
      expect((await client.queries.varsEnum(one: OnlyOne.only)).echoArgs.one, OnlyOne.only);
    });

    test('an input object variable', () async {
      final r = (await client.queries.varsInput(inner: const InnerInput(n: 4, label: 'x'))).echoInner;
      expect([r.n, r.label], [4, 'x']);
    });

    test('nullable versus non-null variables', () async {
      final given = (await client.queries.varsNullable(dollar: r'$d', quote: 'q')).echoNastyArgs;
      expect([given.dollar, given.quote], [r'$d', 'q']);
      final left = (await client.queries.varsNullable(quote: 'q')).echoNastyArgs;
      expect([left.dollar, left.quote], [null, 'q']);
    });
  });

  group('@include and @skip', () {
    test('with variables', () async {
      final both = (await client.queries.conditionalVars(withEmail: true, skipName: false)).getUser;
      expect([both.id, both.name, both.email], ['user-1', 'Alice Smith', 'alice@test.com']);
      final neither = (await client.queries.conditionalVars(withEmail: false, skipName: true)).getUser;
      expect([neither.id, neither.name, neither.email], ['user-1', null, null]);
    });

    test('with literals', () async {
      final u = (await client.queries.conditionalLiterals()).getUser;
      expect(u.name, 'Alice Smith');
      expect(u.email, isNull);
      expect(u.status, UserStatus.active);
      expect(u.priority, isNull);
    });
  });

  group('aliases', () {
    test('the same field twice with different arguments', () async {
      final r = await client.queries.aliasesSameField();
      expect([r.a.id, r.b.id], ['user-1', 'user-2']);
    });

    test('aliases named after keywords', () async {
      final r = (await client.queries.aliasKeywords()).class_;
      expect(r.default_, 'Alice Smith');
      expect(r.import_, 'user-1');
    });

    test('an alias with the name of another field', () async {
      final r = (await client.queries.aliasEqualsOtherField()).getUser;
      expect(r.name, 'alice@test.com');
    });
  });

  group('operation names that collide with something', () {
    test('with a type', () async {
      expect((await client.queries.user()).getUser.id, 'user-1');
      expect((await client.queries.photo2()).photo!.id, 'ph1');
    });

    test('with a keyword', () async {
      expect((await client.queries.return_()).listUsers, isNotEmpty);
    });

    test('with the name of an auto-generated operation, the custom one wins', () async {
      expect((await client.queries.shelf()).shelf.id, 's1');
    });

    test('with the name of a generated response type', () async {
      expect((await client.queries.getUserResponse()).getUser.id, 'user-1');
    });
  });

  group('field arguments of every shape', () {
    test('literals', () async {
      final s = (await client.queries.shelfItems()).shelf;
      expect(s.items, ['tags=[a, b]', 'kind=x__y', 'filter={n=3, label=L}', 'limit=5']);
    });

    test('variables', () async {
      final r = (await client.queries.shelfItemsVars(
        tags: ['t'], kind: Spelling.v1, filter: const InnerInput(n: 1, label: 'f'), limit: 7,
      )).shelf;
      expect(r.items, ['tags=[t]', 'kind=v1', 'filter={n=1, label=f, tags=[a]}', 'limit=7']);
    });

    test('server-side defaults of a field argument', () async {
      final r = (await client.queries.shelfItemsDefaults()).shelf;
      expect(r.items.last, 'limit=2');
    });
  });

  group('literal arguments', () {
    test('lists, nulls and enums', () async {
      final r = (await client.queries.literalLists()).echoArgs;
      expect(r.a, [1, 2, 3]);
      expect(r.b, [1, null]);
      expect(r.c, [[1], [2, 3]]);
      expect(r.e, [Spelling.a, Spelling.xY]);
      expect(r.f, [null, Spelling.v1]);
      expect(r.g, [Spelling.snakeCase2]);
      expect(r.one, OnlyOne.only);
    });

    test('an input object', () async {
      final r = (await client.queries.literalInput()).echoInput;
      expect(r.a, [4]);
      expect(r.b, [null, 5]);
      expect(r.c, [[6]]);
      expect(r.e, [Spelling.b2]);
      expect(r.f, [null]);
      expect(r.g, [Spelling.a]);
    });

    test('every scalar kind', () async {
      final r = (await client.queries.literalScalars()).echoEverything;
      expect([r.i, r.neg, r.big], [5, -3, 9]);
      expect([r.f, r.exp], [2.5, 100.0]);
      expect([r.b, r.bf], [false, true]);
      expect([r.s, r.id, r.e], ['lit', 'q', Spelling.v1]);
      expect(r.ints, [9]);
      expect(r.nested, [[1]]);
      expect([r.inner!.n, r.inner!.label], [2, 'L']);
      expect(r.nothing, isNull);
      expect(r.emptyList, isEmpty);
      expect(r.emptyObj!.n, isNull);
    });

    test('mixed with variables', () async {
      final r = (await client.queries.literalsMixed(a: [8], one: OnlyOne.only)).echoArgs;
      expect(r.a, [8]);
      expect(r.e, [Spelling.a, Spelling.b2]);
      expect(r.f, [Spelling.v1]);
      expect(r.one, OnlyOne.only);
    });
  });
}
