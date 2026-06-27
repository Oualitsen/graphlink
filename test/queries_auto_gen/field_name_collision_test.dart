import 'package:test/test.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

/// Reproduction + guard for the GitLab-schema variable collision.
///
/// Two *unrelated* types (`Commit`, `Ref`) each declare a field with the SAME
/// name (`associatedItems`) taking an arg with the SAME name (`orderBy`) but of
/// INCOMPATIBLE input types (`PullRequestOrder` vs `IssueOrder`). When both are
/// reachable from one operation, the clean `$<field><Arg>` variable name would
/// map to two incompatible types and the parser used to throw:
///
///   Variable $associatedItemsOrderBy is used for arguments of incompatible
///   types (PullRequestOrder vs IssueOrder).
///
/// The fix escalates ONLY ambiguous arguments to `$<field><Arg><Type>`, while
/// unambiguous arguments keep the clean `$<field><Arg>` name. This mirrors the
/// real failure: Commit.associatedPullRequests vs Ref.associatedPullRequests.
const _autoGenSchema = '''
input PullRequestOrder { field: String }
input IssueOrder { field: String }

type Commit {
  sha: String!
  associatedItems(orderBy: PullRequestOrder): String
}

type Ref {
  name: String!
  associatedItems(orderBy: IssueOrder): String
}

type Repository {
  commit: Commit
  ref: Ref
  users(filter: String): String
  posts(filter: String): String
}

type Query {
  repository: Repository
}
''';

/// Same conflict, but reached through an explicitly-declared multi-root
/// operation (`getBoth { commit … ref … }`) that spreads the `_all_fields`
/// macro. The nested ambiguous args must still escalate so the operation can
/// declare both variables without colliding.
const _explicitMultiRootSchema = '''
input PullRequestOrder { field: String }
input IssueOrder { field: String }

type Commit {
  sha: String!
  associatedItems(orderBy: PullRequestOrder): String
  files(filter: String): String
}

type Ref {
  name: String!
  associatedItems(orderBy: IssueOrder): String
}

type Query {
  getCommit(id: ID!): Commit
  getRef(name: String!): Ref
}

query getBoth(\$commitId: ID!, \$refName: String!) {
  commit: getCommit(id: \$commitId) { ..._all_fields }
  ref: getRef(name: \$refName) { ..._all_fields }
}
''';

void main() {
  test('ambiguous arg escalates with its type; unambiguous args keep clean name',
      () {
    final g = GLParser(
        generateAllFieldsFragments: true, autoGenerateQueries: true);

    g.parse(_autoGenSchema);

    // `repository` has no declared args, so every propagated arg is grouped into
    // the synthesized RepositoryFieldArgs input (fields keyed by bare name, no $).
    final byName = {
      for (final f in g.inputs['RepositoryFieldArgs']!.fields)
        f.name.token: f.type.token
    };

    // Ambiguous: associatedItems.orderBy resolves to two incompatible input
    // types, so each variant is escalated to a distinct, type-qualified name.
    expect(byName['associatedItemsOrderByPullRequestOrder'],
        equals('PullRequestOrder'),
        reason: 'Commit.associatedItems(orderBy: PullRequestOrder) escalates');
    expect(byName['associatedItemsOrderByIssueOrder'], equals('IssueOrder'),
        reason: 'Ref.associatedItems(orderBy: IssueOrder) escalates');

    // No conflict: users.filter / posts.filter stay on the clean <field><Arg>
    // name — no type suffix.
    expect(byName['usersFilter'], equals('String'),
        reason: 'unambiguous users(filter:) keeps the clean name');
    expect(byName['postsFilter'], equals('String'),
        reason: 'unambiguous posts(filter:) keeps the clean name');
    expect(byName.keys.where((k) => k.startsWith('filter')), isEmpty,
        reason: 'clean filter args must not be type-suffixed');
  });

  test('explicit multi-root operation declares both escalated variables', () {
    final g = GLParser(generateAllFieldsFragments: true);

    g.parse(_explicitMultiRootSchema);

    final query = g.queries[GLOperationKey('getBoth', GLQueryType.query)]!;
    final declared = {for (var a in query.arguments) a.token: a.type.token};

    // Author-declared root variables stay DIRECT arguments, untouched.
    expect(declared[r'$commitId'], equals('ID'));
    expect(declared[r'$refName'], equals('String'));

    // The propagated nested args are grouped into the synthesized input
    // (fields keyed by bare name, no $).
    final fieldArgs = {
      for (final f in g.inputs['GetBothFieldArgs']!.fields)
        f.name.token: f.type.token
    };

    // Both ambiguous nested args are escalated and both reach the input.
    expect(fieldArgs['associatedItemsOrderByPullRequestOrder'],
        equals('PullRequestOrder'));
    expect(fieldArgs['associatedItemsOrderByIssueOrder'], equals('IssueOrder'));

    // The unambiguous nested arg keeps its clean name.
    expect(fieldArgs['filesFilter'], equals('String'));
  });
}
