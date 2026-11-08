import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'flutter_inputs_draft_serializer.dart';
import 'flutter_inputs_type_helpers.dart';

class FlutterInputsResetSerializer {
  final DartCodeGenUtils _u;
  final FlutterConfig _config;
  final FlutterInputsTypeHelpers _types;

  FlutterInputsResetSerializer(this._u, this._config, this._types);

  String serializeResetMethod(
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
    List<GLField> listFields,
    List<GLField> inputFields,
    bool hasSubInputs,
  ) {
    final passwordFields = textFields.where(_types.isPasswordField).toList();
    final dateEligibleFields = textFields.where(
        (f) => _types.dartScalarType(f) == 'int' || _types.dartScalarType(f) == 'String').toList();

    // Helper: wraps a reset statement so it only runs when fields is null (full reset)
    // or when the named field is explicitly listed.
    String ifField(GLField f, String stmt) => _u.ifStatement(
          condition: "fields == null || fields.contains('${f.codeName}')",
          ifBlockStatements: [stmt],
        );

    final setStateBody = _u.block([
      ...textFields.map((f) => ifField(f, '_${f.codeName}Controller.text = ${_types.initialTextExpr(f)};')),
      // password and calendar are tied to their field — reset together with it
      ...passwordFields.map((f) => ifField(f, '_${f.codeName}Obscured = true;')),
      ...dateEligibleFields.map((f) => ifField(f, '_${f.codeName}CalendarOpen = false;')),
      ...enumFields.map((f) => ifField(f, '_${f.codeName} = _form.initialValues?.${f.codeName};')),
      ...boolFields.map((f) => ifField(f, '_${f.codeName} = ${_types.initialBoolExpr(f)};')),
      ...listFields.map((f) {
        final stmt = _types.isEnumListField(f) || _types.isScalarListField(f)
            ? '_${f.codeName} = List.of(_form.${f.codeName});'
            : f.type.nullable
                ? '_${f.codeName} = _form.${f.codeName} != null ? List.of(_form.${f.codeName}!) : null;'
                : '_${f.codeName} = List.of(_form.${f.codeName});';
        return ifField(f, stmt);
      }),
      // stepper position — full reset only
      if (hasSubInputs) _u.inlineIfStatement(condition: 'fields == null', statement: '_currentStep = 0;'),
    ]);

    // After setState: clear validation state and reset sub-forms.
    // Full reset → clear entire form validation + all sub-forms.
    // Partial reset → only reset explicitly listed sub-input keys; leave validation as-is
    //                 so errors on untouched fields remain visible.
    final validatableForReset = [...textFields, ...enumFields, ...boolFields];
    final postResetStatements = [
      '_debounceTimer?.cancel();',
      // Cancel any in-flight async validators and clear their shadow errors.
      ...validatableForReset.map((f) => '_${f.codeName}AsyncTimer?.cancel();'),
      ...validatableForReset.map((f) => '_${f.codeName}AsyncError = null;'),
      ...validatableForReset.map((f) => '_${f.codeName}Validating = false;'),
      _u.ifStatement(
        condition: 'fields == null',
        ifBlockStatements: [
          '_formKey.currentState?.reset();',
          ...inputFields.map((f) => '_${f.codeName}Key.currentState?.reset();'),
          if (_config.persistDrafts) FlutterInputsDraftSerializer.clearDraftStatement,
        ],
        elseBlockStatements: [
          if (_config.persistDrafts) '_scheduleDraftSave();',
          ...inputFields.map((f) => _u.inlineIfStatement(
                condition: "fields.contains('${f.codeName}')",
                statement: '_${f.codeName}Key.currentState?.reset();',
              )),
        ],
      ),
    ];

    return _u.createMethod(
      override: true,
      returnType: 'void',
      methodName: 'reset',
      namedArguments: true,
      arguments: ['List<String>? fields'],
      statements: [
        _u.tryCatchFinally(
          tryStatements: [
            '_isResetting = true;',
            'setState(() $setStateBody);',
            ...postResetStatements,
          ],
          finallyStatements: ['_isResetting = false;'],
        ),
      ],
    );
  }

  String serializeIsDirtyGetter(
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
    List<GLField> listFields,
    List<GLField> inputFields,
  ) {
    final checks = <String>[];

    for (final f in textFields) {
      checks.add(_returnTrueIf('_${f.codeName}Controller.text != (${_types.initialTextExpr(f)})'));
    }
    for (final f in enumFields) {
      checks.add(_returnTrueIf('_${f.codeName} != _form.initialValues?.${f.codeName}'));
    }
    for (final f in boolFields) {
      checks.add(_returnTrueIf('_${f.codeName} != (${_types.initialBoolExpr(f)})'));
    }
    for (final f in listFields) {
      if (_types.isEnumListField(f) || _types.isScalarListField(f)) {
        // Order-insensitive comparison — chips selections are unordered
        checks.add(_returnTrueIf(
          '_${f.codeName}.length != _form.${f.codeName}.length || !_${f.codeName}.toSet().containsAll(_form.${f.codeName})',
        ));
      } else if (_types.isInputListField(f)) {
        checks.add(_returnTrueIf('_${f.codeName}OverrideKey.currentState?.isDirty ?? false'));
      }
    }
    for (final f in inputFields) {
      checks.add(_returnTrueIf('_${f.codeName}Key.currentState?.isDirty ?? false'));
    }

    final body = _u.block([...checks, 'return false;']);
    return '@override\nbool get isDirty $body';
  }

  String _returnTrueIf(String condition) =>
      _u.inlineIfStatement(condition: condition, statement: 'return true;');
}
