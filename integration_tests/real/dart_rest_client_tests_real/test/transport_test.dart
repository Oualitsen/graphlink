import 'package:graphlink_rest_real_tests/generated/graphlink.dart';
import 'support.dart';
import 'package:test/test.dart';

void main() {
  setUp(resetServer);

  group('base URL', () {
    test('a path prefix is kept in front of the operation path', () async {
      final e = await newClient(baseUrl: '$serverUrl/api').queries.eScalars(id: 'p');
      expect(e.path, '/api/echo/scalars/p');
    });

    test('a trailing slash does not double the separator', () async {
      final e = await newClient(baseUrl: '$serverUrl/api/').queries.eScalars(id: 'p');
      expect(e.path, '/api/echo/scalars/p');
    });

    test('a base URL without a path works', () async {
      final e = await newClient(baseUrl: '$serverUrl/').queries.eScalars(id: 'p');
      expect(e.path, '/echo/scalars/p');
    });
  });

  group('transport errors', () {
    test('an unreachable server is not a RestError', () async {
      final c = newClient(baseUrl: 'http://127.0.0.1:1');
      await expectLater(c.queries.eAccept(), throwsA(isNot(isA<RestError>())));
    });

    test('a client keeps working after a transport error', () async {
      final c = newClient();
      final dead = newClient(baseUrl: 'http://127.0.0.1:1');
      await expectLater(dead.queries.eAccept(), throwsA(anything));
      expect((await c.queries.eAccept()).method, 'GET');
    });
  });

  group('adapter', () {
    test('concurrent requests do not mix their data', () async {
      final c = newClient();
      final results = await Future.wait([
        for (var i = 0; i < 60; i++) c.queries.eScalars(id: 'id$i', i: i),
      ]);
      for (var i = 0; i < 60; i++) {
        expect(results[i].path, '/echo/scalars/id$i');
        expect(results[i].queryValue('i'), '$i');
      }
    });

    test('mixed request kinds in parallel', () async {
      final c = newClient();
      final out = await Future.wait<Object>([
        c.queries.eAccept(),
        c.mutations.eJson(body: ProductIn(name: 'x')),
        c.mutations.eForm(name: 'f'),
        c.mutations.eMultipart(title: 't'),
        c.mutations.eRaw(file: uploadOf(pattern(1000))),
        c.queries.blob(size: 2000).then((d) => d.bytes()),
      ]);
      expect((out[0] as Echo).method, 'GET');
      expect((out[1] as Echo).contentType, startsWith('application/json'));
      expect((out[2] as Echo).formValue('name'), 'f');
      expect((out[3] as Echo).part('title').text, 't');
      expect((out[4] as Echo).bodySize, 1000);
      expect((out[5] as List).length, 2000);
    });
  });
}
