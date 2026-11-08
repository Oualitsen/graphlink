import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'flutter_inputs_draft_serializer.dart';
import 'flutter_inputs_type_helpers.dart';

enum StepType { scalar, subInput, inputList }

class StepBucket {
  final int index;
  final StepType type;
  final GLField? field;
  const StepBucket(this.index, this.type, this.field);
}

class FlutterInputsStepperSerializer {
  final DartCodeGenUtils _u;
  final FlutterConfig _config;
  final FlutterInputsTypeHelpers _types;
  final FlutterInputsDraftSerializer _drafts;

  FlutterInputsStepperSerializer(this._u, this._config, this._types, this._drafts);

  /// Builds the ordered list of step buckets at generator time.
  /// Scalar step first (if any scalar fields exist), then sub-inputs and
  /// list-of-inputs interleaved in schema declaration order.
  List<StepBucket> buildStepBuckets(
      List<GLField> fields, bool hasScalarFields,
      List<GLField> inputFields, List<GLField> inputListFields) {
    final buckets = <StepBucket>[];
    var idx = 0;
    if (hasScalarFields) buckets.add(StepBucket(idx++, StepType.scalar, null));
    for (final f in fields) {
      if (inputFields.contains(f)) {
        buckets.add(StepBucket(idx++, StepType.subInput, f));
      } else if (inputListFields.contains(f)) {
        buckets.add(StepBucket(idx++, StepType.inputList, f));
      }
    }
    return buckets;
  }

  String serializeBuildStepsMethod(
      String inputName, List<StepBucket> buckets, bool hasScalarFields) {
    final humanizedInputName = _humanizeInputName(inputName);
    final stepExprs = buckets.map((b) {
      final idx = b.index;
      final stateExpr =
          '_currentStep > $idx ? StepState.complete : _currentStep == $idx ? StepState.editing : StepState.indexed';

      if (b.type == StepType.scalar) {
        return _u.callExpression('Step', [
          'title: _form.stepConfig?.scalarFields?.title ?? const Text(\'$humanizedInputName\')',
          'subtitle: _form.stepConfig?.scalarFields?.subtitle',
          'isActive: _currentStep >= $idx',
          'state: $stateExpr',
          'content: ${_u.callExpression('Form', [
            'key: _formKey',
            'child: ${_u.callExpression('Column', [
              'mainAxisSize: MainAxisSize.min',
              'crossAxisAlignment: CrossAxisAlignment.stretch',
              'children: _intersperse(_scalarRows(), _form.gap)',
            ])}',
          ])}',
        ]);
      }

      final f = b.field!;
      final name = f.codeName;
      final humanLabel = _types.humanize(f.name.token);

      if (b.type == StepType.subInput) {
        final childType = _types.resolveTypeCodeName(f.type.firstType.token);
        final defaultChildForm = _u.callExpression('${childType}Form', [
          'key: _${name}Key',
          'strings: _form.strings',
          'initialValues: _form.initialValues?.$name',
          'requiredIndicator: _form.requiredIndicator',
          'requiredLabel: _form.requiredLabel',
          'optionalLabel: _form.optionalLabel',
          'labelPosition: ${childType}LabelPosition.values.byName(_form.labelPosition.name)',
          'labelWidth: _form.labelWidth',
          'gap: _form.gap',
          'onContextChange: (_) => _onFieldChanged()',
          if (_config.persistDrafts) ..._drafts.childArgs(name),
        ]);
        return _u.callExpression('Step', [
          'title: _form.stepConfig?.$name?.title ?? const Text(\'$humanLabel\')',
          'subtitle: _form.stepConfig?.$name?.subtitle',
          'isActive: _currentStep >= $idx',
          'state: $stateExpr',
          'content: _form.values?.$name?.call(_${name}Key) ?? $defaultChildForm',
        ]);
      }

      // inputList
      final lengthExpr = f.type.nullable ? '_$name?.length ?? 0' : '_$name.length';
      return _u.callExpression('Step', [
        'title: _form.stepConfig?.$name?.title ?? const Text(\'$humanLabel\')',
        'subtitle: _form.stepConfig?.$name?.subtitle',
        'isActive: _currentStep >= $idx',
        'state: $stateExpr',
        'content: _form.values?.$name?.call(_${name}OverrideKey) ?? Text(\'\${$lengthExpr} items\')',
      ]);
    }).toList();

    final stepsList = '[${stepExprs.map((e) => '\n  $e,').join('')}\n]';
    return _u.createMethod(
      returnType: 'List<Step>',
      methodName: '_buildSteps',
      arguments: [],
      namedArguments: false,
      statements: ['return $stepsList;'],
    );
  }

  String serializeValidateAndReadCurrentStepMethod(
      String inputName, List<StepBucket> buckets) {
    final cases = buckets.map((b) {
      final idx = b.index;
      List<String> validateStatements;
      if (b.type == StepType.scalar) {
        validateStatements = [
          'return _formKey.currentState?.validate() ?? false;',
        ];
      } else if (b.type == StepType.subInput) {
        validateStatements = [
          _u.tryCatchFinally(
            tryStatements: ['_${b.field!.name}Key.currentState!.read();', 'return true;'],
            catchVariable: '_',
            catchStatements: ['return false;'],
          ),
        ];
      } else {
        // inputList — only validate if a Values override is present
        validateStatements = [
          _u.ifStatement(
            condition: '_form.values?.${b.field!.name} != null',
            ifBlockStatements: [
              _u.tryCatchFinally(
                tryStatements: ['_${b.field!.name}OverrideKey.currentState!.read();', 'return true;'],
                catchVariable: '_',
                catchStatements: ['return false;'],
              ),
            ],
          ),
          'return true;',
        ];
      }

      return DartCaseStatement(
        caseValue: '$idx',
        statement: _u.block(validateStatements),
      );
    }).toList();

    return _u.createMethod(
      returnType: 'bool',
      methodName: '_validateAndReadCurrentStep',
      arguments: [],
      namedArguments: false,
      statements: [
        _u.switchStatement(
          expression: '_currentStep',
          cases: cases,
          defaultStatements: ['return true;'],
          generateBreaks: false,
        ),
      ],
    );
  }

  String serializeOnStepContinueMethod(int totalSteps) => _u.createMethod(
        returnType: 'void',
        methodName: '_onStepContinue',
        arguments: [],
        namedArguments: false,
        statements: [
          _u.ifStatement(
            condition: '_validateAndReadCurrentStep()',
            ifBlockStatements: [
              _u.ifStatement(
                condition: '_currentStep < ${totalSteps - 1}',
                ifBlockStatements: ['setState(() => _currentStep++);'],
              ),
            ],
          ),
        ],
      );

  String serializeOnStepCancelMethod() => _u.createMethod(
        returnType: 'void',
        methodName: '_onStepCancel',
        arguments: [],
        namedArguments: false,
        statements: [
          _u.ifStatement(
            condition: '_currentStep > 0',
            ifBlockStatements: ['setState(() => _currentStep--);'],
          ),
        ],
      );

  String serializeBuildStepControlsMethod(int totalSteps) => _u.createMethod(
        returnType: 'Widget',
        methodName: '_buildStepControls',
        namedArguments: false,
        arguments: ['BuildContext context', 'ControlsDetails details'],
        statements: [
          _u.constDecl('isFirst', 'details.stepIndex == 0'),
          _u.constDecl('isLast', 'details.stepIndex == ${totalSteps - 1}'),
          'return ${_u.callExpression('Row', [
            'mainAxisAlignment: _form.stepControlsAlignment',
            _u.listArg('children', [
              // Back — hidden on first step, always takes space to keep Next stable
              _u.callExpression('Visibility', [
                'visible: !isFirst',
                'maintainSize: true',
                'maintainAnimation: true',
                'maintainState: true',
                'child: ${_u.callExpression('TextButton', [
                  'onPressed: details.onStepCancel',
                  'child: Text(_form.stepperStrings.back)',
                ])}',
              ]),
              // Next / Submit
              _u.callExpression('ElevatedButton', [
                'onPressed: _submitting ? null : details.onStepContinue',
                'child: Text(isLast ? _form.stepperStrings.submit : _form.stepperStrings.next)',
              ]),
            ]),
          ])};',
        ],
      );

  String _humanizeInputName(String inputName) {
    final withoutSuffix = inputName.endsWith('Input')
        ? inputName.substring(0, inputName.length - 5)
        : inputName;
    return _types.humanize(withoutSuffix);
  }

}
