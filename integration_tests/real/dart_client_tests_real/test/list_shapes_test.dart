import 'package:graphlink_client_integration_tests/generated/graphlink.dart';
import 'package:test/test.dart';

import 'real_server_adapter.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  Future<ListShapes> shapes(String mode) async => (await client.queries.listShapes(mode: mode)).listShapes;

  group('list shapes with real null elements', () {
    test('scalars', () async {
      final s = await shapes('full');
      expect(s.a, [1, 2, 3]);
      expect(s.b, [1, 2, 3]);
      expect(s.c, [1, null, 3]);
      expect(s.d, [null]);
    });

    test('nested lists', () async {
      final s = await shapes('full');
      expect(s.e, [[1, 2], [3]]);
      expect(s.f, [[1, null], null]);
    });

    test('enums', () async {
      expect((await shapes('full')).g, [Spelling.a, null, Spelling.b2]);
    });

    test('objects', () async {
      final h = (await shapes('full')).h;
      expect(h, hasLength(2));
      expect(h[0]!.width, 640);
      expect(h[1], isNull);
    });

    test('union members', () async {
      final i = (await shapes('full')).i;
      expect(i, hasLength(3));
      expect(i[0], isA<Photo>());
      expect(i[1], isNull);
      expect(i[2], isA<Video>());
    });

    test('interface implementers', () async {
      final j = (await shapes('full')).j;
      expect(j, hasLength(2));
      expect(j[0], isA<Comment>());
      expect(j[1], isNull);
    });
  });

  group('empty list versus null list', () {
    test('empty lists stay empty', () async {
      final s = await shapes('empty');
      expect(s.b, isEmpty);
      expect(s.d, isEmpty);
      expect(s.f, isEmpty);
      expect(s.e, isEmpty);
    });

    test('null lists stay null while the required ones are empty', () async {
      final s = await shapes('null');
      expect(s.b, isNull);
      expect(s.d, isNull);
      expect(s.f, isNull);
      expect(s.a, isEmpty);
      expect(s.g, isEmpty);
      expect(s.i, isEmpty);
    });
  });

  group('list arguments', () {
    test('every shape round trips', () async {
      final r = (await client.queries.echoArgs(
        a: [1, 2],
        b: [1, null],
        c: [[1], [], [2, 3]],
        e: [Spelling.xY, Spelling.http2Ok],
        f: [null, Spelling.v1],
      )).echoArgs;
      expect(r.a, [1, 2]);
      expect(r.b, [1, null]);
      expect(r.c, [[1], [], [2, 3]]);
      expect(r.e, [Spelling.xY, Spelling.http2Ok]);
      expect(r.f, [null, Spelling.v1]);
    });

    test('omitted lists come back null, defaults are applied', () async {
      final r = (await client.queries.echoArgs(a: [], e: [])).echoArgs;
      expect(r.a, isEmpty);
      expect(r.b, isNull);
      expect(r.c, isNull);
      expect(r.e, isEmpty);
      expect(r.f, isNull);
      expect(r.g, [Spelling.a, Spelling.b2]);
      expect(r.one, OnlyOne.only);
    });

    test('an explicitly empty default-bearing list is not replaced by the default', () async {
      final r = (await client.queries.echoArgs(a: [], e: [], g: [])).echoArgs;
      expect(r.g, isEmpty);
    });

    test('explicit null overrides the default', () async {
      final r = (await client.queries.echoArgs(a: [], e: [], g: null)).echoArgs;
      expect(r.g, isNull);
    });
  });

  group('list input fields', () {
    test('every shape round trips', () async {
      final r = (await client.queries.echoInput(
        input: const ListsInput(
          a: [3, 4],
          b: [null, 5],
          c: [[1, 2], []],
          e: [Spelling.snakeCase2],
          f: [Spelling.a, null],
          g: [Spelling.v1],
        ),
      )).echoInput;
      expect(r.a, [3, 4]);
      expect(r.b, [null, 5]);
      expect(r.c, [[1, 2], []]);
      expect(r.e, [Spelling.snakeCase2]);
      expect(r.f, [Spelling.a, null]);
      expect(r.g, [Spelling.v1]);
    });

    test('input defaults reach the server', () async {
      final r = (await client.queries.echoInput(input: const ListsInput(a: [], e: []))).echoInput;
      expect(r.g, [Spelling.a, Spelling.b2]);
      expect(r.one, OnlyOne.only);
    });
  });

  group('large lists', () {
    test('50000 scalars', () async {
      final r = (await client.queries.bigInts(n: 50000)).bigInts;
      expect(r, hasLength(50000));
      expect(r.last, 49999);
    });

    test('20000 objects', () async {
      final r = (await client.queries.bigPhotos(n: 20000)).bigPhotos;
      expect(r, hasLength(20000));
      expect(r[19999].id, 'p19999');
      expect(r[19999].width, 19999);
    });
  });
}
