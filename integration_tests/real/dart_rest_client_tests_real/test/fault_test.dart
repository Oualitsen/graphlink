import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:graphlink_rest_real_tests/generated/graphlink.dart';
import 'package:test/test.dart';

import 'support.dart';

class FaultCase {
  final String fault;
  final String ops;
  final String expected;
  const FaultCase(this.fault, this.ops, this.expected);
}

final faultCases = [
  for (final c in jsonDecode(File('../fault_server/cases.json').readAsStringSync()) as List)
    FaultCase(c['fault'] as String, c['ops'] as String, c['expect'] as String),
];

const knownDefects = <String, String>{
};

const opNames = {'g': 'GraphQL getCount', 'c': 'REST count', 'p': 'REST status'};

void main() {
  late GraphLinkClient client;
  late Map<String, Future<Object?> Function()> calls;
  late Map<String, Future<void> Function()> healthy;

  setUp(() async {
    await postFaultServer('/_reset');
    client = newFaultClient();
    calls = {
      'g': () => client.queries.getCount(),
      'c': () => client.queries.count(),
      'p': () => client.queries.status(code: 200),
    };
    healthy = {
      'g': () async => expect((await client.queries.getCount()).getCount, 19),
      'c': () async => expect(await client.queries.count(), 7),
      'p': () async => expect((await client.queries.status(code: 200))!.name, 'Pen'),
    };
  });

  for (final c in faultCases) {
    for (final op in c.ops.split('')) {
      final defect = knownDefects['${c.fault}:$op'];
      test('${c.fault}: ${opNames[op]} -> ${c.expected}, then the client still works', () async {
        await postFaultServer('/_arm?fault=${c.fault}');
        Object? result;
        Object? error;
        try {
          result = await calls[op]!().timeout(const Duration(seconds: 8));
        } on TimeoutException {
          fail('${c.fault} hung for 8 seconds');
        } catch (e) {
          error = e;
        }
        if (c.expected == 'value') expect(error, isNull, reason: 'unexpected failure: $error');
        if (c.expected == 'failure') expect(error, isNotNull, reason: 'decoded without a failure: $result');
        await healthy[op]!();
      }, skip: defect);
    }
  }

  test('a RestError carries the status and the body of a gateway page', () async {
    await postFaultServer('/_arm?fault=html-502');
    await expectLater(
      client.queries.count(),
      throwsA(isA<RestError>().having((e) => e.status, 'status', 502).having((e) => e.body, 'body', contains('Bad Gateway'))),
    );
  });

  test('a GraphQL error response reaches the caller with its message, path and extensions', () async {
    await postFaultServer('/_arm?fault=gql-errors-only');
    try {
      await client.queries.getCount();
      fail('expected a GraphQL error');
    } on List<GraphLinkError> catch (errors) {
      expect(errors.single.message, 'boom');
      expect(errors.single.path, ['getCount']);
      expect(errors.single.extensions?['code'], 'BAD');
    }
  });

  for (final entry in {'html-502': [502, 'Bad Gateway'], 'status-401-json': [401, 'unauthorized']}.entries) {
    test('a GraphQL call keeps the HTTP status and body of ${entry.key}', () async {
      await postFaultServer('/_arm?fault=${entry.key}');
      try {
        await client.queries.getCount();
        fail('expected a failure');
      } on List<GraphLinkError> catch (errors) {
        expect(errors.single.status, entry.value[0]);
        expect(errors.single.body, contains(entry.value[1] as String));
      }
    });
  }

  test('a response without data and without errors says so', () async {
    await postFaultServer('/_arm?fault=gql-empty-object');
    try {
      await client.queries.getCount();
      fail('expected a failure');
    } on List<GraphLinkError> catch (errors) {
      expect(errors.single.message, contains('no data'));
    }
  });
}
