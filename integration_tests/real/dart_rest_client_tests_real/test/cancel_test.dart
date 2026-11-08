import 'dart:async';

import 'package:graphlink_rest_real_tests/generated/graphlink.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  Future<Object?> call(GraphLinkClient client, String op) {
    switch (op) {
      case 'g':
        return client.queries.getCount();
      case 'c':
        return client.queries.count();
      case 'k':
        return client.queries.cachedStatus(code: 200);
    }
    return client.queries.status(code: 200);
  }

  group('a call that the caller gives up on', () {
    for (final op in 'gcpk'.split('')) {
      test('$op: the timeout fires promptly and the client still works', () async {
        await postFaultServer('/_reset');
        final client = newFaultClient();
        await postFaultServer('/_arm?fault=slow');
        final started = Stopwatch()..start();
        await expectLater(call(client, op).timeout(const Duration(milliseconds: 200)), throwsA(isA<TimeoutException>()));
        expect(started.elapsedMilliseconds, lessThan(700));
        await call(client, op).timeout(const Duration(seconds: 5));
      });
    }
  });
}
