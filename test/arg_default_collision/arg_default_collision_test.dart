import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
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

    // `provisioningStepsRunnerToken` is a propagated field arg, now grouped into
    // the synthesized GetDataFieldArgs input. The merge across the two union
    // members must pick the stricter (non-null) type AND drop the incompatible
    // `= null` default — otherwise the generated input field would be
    // `String provisioningStepsRunnerToken = null`, a compile error.
    final field = g.inputs['GetDataFieldArgs']!.fields
        .firstWhere((f) => f.name.token == 'provisioningStepsRunnerToken');

    expect(field.type.nullable, isFalse,
        reason: 'stricter (non-null) String! type wins over the nullable variant');
    expect(field.initialValue, isNull,
        reason: 'the incompatible null default must be dropped, not leaked onto '
            'the non-null field');
  });
}
