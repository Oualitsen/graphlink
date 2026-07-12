import 'package:test/test.dart';
import 'package:graphlink_server_integration_tests_dart_client/generated/graphlink.dart';
import 'fixtures.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  group('@glIntercept', () {
    test('greetIntercepted appends the runBefore marker to the name argument', () async {
      final res = await client.queries.greetIntercepted(name: 'Ada');
      expect(res.greetIntercepted.message, equals('Hello, Ada(runBefore)'));
    });

    test('greetPlain is not intercepted, no marker appended', () async {
      final res = await client.queries.greetPlain(name: 'Ada');
      expect(res.greetPlain.message, equals('Hello, Ada'));
    });

    test('greetingReceived (intercepted subscription) bakes the marker into every emitted greeting', () async {
      final eventFuture = client.subscriptions.greetingReceived().first.timeout(const Duration(seconds: 10));

      // give the subscription a moment to register (and runBefore to fire) before triggering the mutation
      await Future.delayed(const Duration(milliseconds: 300));

      await client.mutations.sendGreeting(name: 'Ada');

      final event = await eventFuture;
      expect(event.greetingReceived.message, equals('Hello, Ada(runBefore)'));
    });

    test('Team.members (intercepted batch mapping) allows role "auth"', () async {
      final res = await client.queries.listTeams(fieldArgs: const ListTeamsFieldArgs(membersRole: 'auth'));
      final members = res.listTeams.first.members.map((m) => m.name).toSet();
      expect(members, equals({'Ada', 'Grace'}));
    });

    test('Team.members (intercepted batch mapping) denies any other role', () async {
      final future = client.queries.listTeams(fieldArgs: const ListTeamsFieldArgs(membersRole: 'wrong'));
      await expectLater(future, throwsA(isA<List<GraphLinkError>>()));
    });
  });
}
