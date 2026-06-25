import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';
import 'package:test/test.dart';

/// Bug: when two types in a union share a field with the same argument name
/// but different nullability/defaults, the null default leaks to the non-null
/// argument after the merge.
///
/// CiRunnerGoogleCloudProvisioning.provisioningSteps(runnerToken: String = null)
/// CiRunnerGkeProvisioning.provisioningSteps(runnerToken: String!)
///
/// Both map to variable `\$provisioningStepsRunnerToken`. The merge correctly
/// picks the stricter type (String!) but incorrectly retains the `= null`
/// default from the nullable variant.

const _schema = '''
schema { query: Query }

type Query {
  getData(id: ID!): CiRunnerCloudProvisioning
}

union CiRunnerCloudProvisioning = CiRunnerGkeProvisioning | CiRunnerGoogleCloudProvisioning

type CiRunnerGoogleCloudProvisioning {
  projectSetupShellScript: String
  provisioningSteps(runnerToken: String = null): [CiRunnerGoogleCloudProvisioning!]
}

type CiRunnerGkeProvisioning {
  projectSetupShellScript: String
  provisioningSteps(runnerToken: String!): [CiRunnerGkeProvisioning!]
}
''';

void main() {
  test('non-null arg does not get null default from same-named arg on sibling type', () {
    final g = GLParser(
      identityFields: ['id'],
      mode: CodeGenerationMode.client,
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
    );
    g.parse(_schema);
    final s = DartSerializer(g, importPrefix: '');
    final out =
        DartClientSerializer(g, s).getQueriesClass()?.toFileContent() ?? '';
    print('=== Dart client ===\n$out');

    // BUG: The generated Dart code is `String provisioningStepsRunnerToken = null`
    // which is a COMPILE ERROR — non-nullable String cannot have null default.
    // The String! type is correct (from the merge), but the = null default
    // leaked from the CiRunnerGoogleCloudProvisioning variant.
    expect(out, isNot(contains('String provisioningStepsRunnerToken = null')),
        reason: 'non-null String arg must not get a null default from '
            'a same-named nullable arg on a sibling union member type');

    // It should be: required (non-null) with NO default, or nullable with default.
    // Expected correct output: `required String provisioningStepsRunnerToken`
    // since the stricter type wins.
    expect(out, contains('required String provisioningStepsRunnerToken'),
        reason: 'when merging same-named args, the stricter (non-null) type '
            'should win AND any incompatible default value should be dropped');
  });
}
