import 'package:graphlink/src/serializers/client_serializers/typescript_client_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

TypeScriptClientSerializer _makeSerializer(GLParser parser,
    {bool observables = false}) {
  final serializer = TypeScriptSerializer(parser);
  return TypeScriptClientSerializer(parser, serializer, observables: observables);
}

String _client(GLParser parser, {bool observables = false}) =>
    _makeSerializer(parser, observables: observables)
        .generateClient('')
        .toFileContent();

void main() {
  const schema = '''
    type Person {
      id: ID!
      name: String!
    }

    type Query {
      getPerson(id: ID!): Person!
    }

    type Mutation {
      deletePerson(id: ID!): Person!
    }

    type Subscription {
      personCreated: Person!
    }

    query getPersonQuery(\$id: ID!) {
      getPerson(id: \$id) { id name }
    }

    mutation deletePersonMutation(\$id: ID!) {
      deletePerson(id: \$id) { id name }
    }

    subscription onPersonCreated {
      personCreated { id name }
    }
  ''';

  group('observables: false (default)', () {
    late String client;

    setUp(() {
      final parser = GLParser(autoGenerateQueries: false);
      parser.parse(schema);
      client = _client(parser, observables: false);
    });

    test('query returns Promise', () {
      expect(client, contains('async getPersonQuery('));
      expect(client, isNot(contains('Observable<')));
    });

    test('mutation returns Promise', () {
      expect(client, contains('async deletePersonMutation('));
      expect(client, isNot(contains('Observable<')));
    });

    test('subscription uses onEvent callback', () {
      expect(client, contains('onEvent:'));
      expect(client, contains('onError?:'));
      expect(client, isNot(contains('Observable<')));
    });

    test('does not import rxjs', () {
      expect(client, isNot(contains("from 'rxjs'")));
    });
  });

  group('observables: true', () {
    late String client;

    setUp(() {
      final parser = GLParser(autoGenerateQueries: false);
      parser.parse(schema);
      client = _client(parser, observables: true);
    });

    test('imports Observable from rxjs', () {
      expect(client, contains("import { Observable } from 'rxjs';"));
    });

    test('query returns Observable and is not async', () {
      expect(client, contains('Observable<GetPersonQueryResponse>'));

      expect(client, contains('new Observable<GetPersonQueryResponse>(subscriber =>'));

      expect(client, isNot(contains('async getPersonQuery(')));
    });

    test('mutation returns Observable and is not async', () {
      expect(client, contains('Observable<DeletePersonMutationResponse>'));
      expect(client, contains('new Observable<DeletePersonMutationResponse>(subscriber =>'));
      expect(client, isNot(contains('async deletePersonMutation(')));
    });

    test('subscription returns Observable without onEvent/onError args', () {
      expect(client, contains('Observable<OnPersonCreatedResponse>'));
      expect(client, isNot(contains('onEvent:')));
      expect(client, isNot(contains('onError?:')));
    });

    test('subscription teardown is returned from Observable', () {
      expect(client, contains('return () =>'));
      expect(client, contains('subscriber.next('));
      expect(client, contains('subscriber.complete()'));
      expect(client, contains('subscriber.error('));
    });

    test('errors route to subscriber.error', () {
      // query, mutation, and subscription errors must reach subscriber.error
      final errorCount = 'subscriber.error('.allMatches(client).length;
      expect(errorCount, greaterThanOrEqualTo(3));
    });
  });
}
