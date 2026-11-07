import 'package:graphlink_client_integration_tests/generated/graphlink.dart';
import 'package:test/test.dart';

import 'real_server_adapter.dart';

const _dollar = r'cost $5 and ${x} and $$';
const _quote = 'say "hi" it\'s';
const _backslash = r'C:\dir\file\n';
const _newline = 'line1\nline2\ttab';
const _percent = '100% {braces} {{x}} %s %d';
const _comments = 'a */ b // c /* d';
const _triple = '""" \'\'\' ```';
const _unicode = 'café 中 😀';
const _nonAscii = 'é中😀';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  void expectNasty(dynamic r) {
    expect(r.dollar, _dollar);
    expect(r.quote, _quote);
    expect(r.backslash, _backslash);
    expect(r.newline, _newline);
    expect(r.percent, _percent);
    expect(r.comments, _comments);
    expect(r.triple, _triple);
    expect(r.unicode, _unicode);
    expect(r.nonAscii, _nonAscii);
  }

  group('string defaults with special characters', () {
    test('on operation arguments', () async {
      expectNasty((await client.queries.echoNastyArgs()).echoNastyArgs);
    });

    test('on input fields, through an input argument that defaults to {}', () async {
      expectNasty((await client.queries.echoNasty()).echoNasty);
    });

    test('an explicit value replaces the default', () async {
      final r = (await client.queries.echoNastyArgs(dollar: r'$y')).echoNastyArgs;
      expect(r.dollar, r'$y');
      expect(r.quote, _quote);
    });
  });

  test('string literals written inline in an operation', () async {
    final r = (await client.queries.nastyLiteral()).echoNastyArgs;
    expect(r.dollar, r'cost $5 ${x}');
    expect(r.quote, 'say "hi"');
    expect(r.backslash, r'C:\dir');
    expect(r.newline, 'a\nb');
    expect(r.unicode, 'é😀');
    expect(r.triple, 'block "x" ');
  });

  group('defaults of every kind', () {
    test('scalars, enum, lists, nested input, null', () async {
      final r = (await client.queries.echoEverything(input: const EverythingInput())).echoEverything;
      expect(r.i, 42);
      expect(r.neg, -7);
      expect(r.big, 2147483647);
      expect(r.f, 3.14);
      expect(r.exp, 1000.0);
      expect(r.b, true);
      expect(r.bf, false);
      expect(r.s, 'x');
      expect(r.id, 'abc');
      expect(r.e, Spelling.xY);
      expect(r.ints, [1, 2, 3]);
      expect(r.nested, [[1], [2, 3]]);
      expect(r.inner!.n, 5);
      expect(r.inner!.label, 'inner');
      expect(r.nothing, isNull);
      expect(r.emptyList, isEmpty);
      expect(r.emptyObj!.n, 1);
      expect(r.emptyObj!.label, 'dflt');
    });

    test('an argument whose input type has its own defaults', () async {
      final r = (await client.queries.echoInner()).echoInner;
      expect(r.n, 9);
      expect(r.label, 'dflt');
      expect(r.tags, ['a']);
    });
  });

  group('recursive inputs', () {
    test('a tree', () async {
      final r = (await client.queries.treeStats(
        tree: const Tree(value: 1, children: [
          Tree(value: 2, children: [Tree(value: 4)]),
          Tree(value: 3),
        ]),
      )).treeStats;
      expect(r.flat, [1, 2, 4, 3]);
      expect(r.depth, 3);
    });

    test('mutually recursive inputs', () async {
      final r = (await client.queries.pingLength(
        ping: const Ping(n: 1, pong: Pong(n: 2, ping: Ping(n: 3))),
      )).pingLength;
      expect(r, 3);
    });
  });

  group('@oneOf input', () {
    test('the first member', () async {
      expect((await client.queries.describePet(pet: const Pet(cat: 'Tom'))).describePet, 'cat:Tom');
    });

    test('the second member', () async {
      expect((await client.queries.describePet(pet: const Pet(dog: 3))).describePet, 'dog:3');
    });
  });

  group('@deprecated', () {
    test('deprecated fields, arguments and enum values still work', () async {
      final r = (await client.queries.legacy(withReason: 'a', plain: 'b')).legacy;
      expect(r.old, 'a');
      expect(r.older, 'b');
      expect(r.mood, Mood.calm);
    });
  });
}
