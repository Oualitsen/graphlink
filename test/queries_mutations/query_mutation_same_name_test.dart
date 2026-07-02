import 'package:test/test.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

// A money-transfer API: you can look up an existing transfer (query) and you
// can initiate a new transfer (mutation). Both operations are naturally named
// `transfer` and both return a `Transfer`.
const schema = '''
type Query {
  transfer(id: ID!): Transfer
}

type Mutation {
  transfer(input: TransferInput!): Transfer
}

input TransferInput {
  fromAccount: ID!
  toAccount: ID!
  amountCents: Int!
}

type Transfer {
  id: ID!
  fromAccount: ID!
  toAccount: ID!
  amountCents: Int!
  status: String!
}
''';

void main() {
  test(
      'a query and a mutation can share the same field name (`transfer`) '
      'without one overwriting the other', () {
    final g = GLParser(
      generateAllFieldsFragments: true,
      autoGenerateQueries: true,
      defaultAlias: 'data',
    );

    g.parse(schema);

    // Both operations must survive parsing — neither should clobber the other.
    final operations =
        g.queries.values.where((q) => q.tokenInfo.token == 'transfer').toList();

    final queryOp = operations
        .where((q) => q.type == GLQueryType.query)
        .toList();
    final mutationOp = operations
        .where((q) => q.type == GLQueryType.mutation)
        .toList();

    expect(queryOp, hasLength(1),
        reason: 'the `transfer` query should be present');
    expect(mutationOp, hasLength(1),
        reason: 'the `transfer` mutation should be present');

    // Their auto-generated response wrappers must not collide either.
    final queryWrapper = queryOp.single.getGeneratedTypeDefinition().token;
    final mutationWrapper = mutationOp.single.getGeneratedTypeDefinition().token;

    expect(queryWrapper, isNot(equals(mutationWrapper)),
        reason: 'query and mutation response wrappers must have distinct names');
  });

  test(
      'a query, a mutation AND a subscription can all share the same field '
      'name (`message`) and coexist', () {
    // A chat API: fetch a message by id (query), send a message (mutation),
    // and stream new messages (subscription) — all naturally named `message`.
    const chatSchema = '''
type Query {
  message(id: ID!): Message
}

type Mutation {
  message(input: SendMessageInput!): Message
}

type Subscription {
  message: Message
}

input SendMessageInput {
  channelId: ID!
  body: String!
}

type Message {
  id: ID!
  body: String!
}
''';

    final g = GLParser(
      generateAllFieldsFragments: true,
      autoGenerateQueries: true,
      defaultAlias: 'data',
    );

    g.parse(chatSchema);

    final query = g.queries[const GLOperationKey('message', GLQueryType.query)];
    final mutation = g.queries[const GLOperationKey('message', GLQueryType.mutation)];
    final subscription =
        g.queries[const GLOperationKey('message', GLQueryType.subscription)];

    // All three operations survive — none clobbers another.
    expect(query, isNotNull, reason: 'the `message` query should be present');
    expect(mutation, isNotNull,
        reason: 'the `message` mutation should be present');
    expect(subscription, isNotNull,
        reason: 'the `message` subscription should be present');

    // And their auto-generated response wrappers are all distinct.
    final wrappers = {
      query!.getGeneratedTypeDefinition().token,
      mutation!.getGeneratedTypeDefinition().token,
      subscription!.getGeneratedTypeDefinition().token,
    };
    expect(wrappers, hasLength(3),
        reason: 'all three response wrappers must have distinct names');
  });
}
