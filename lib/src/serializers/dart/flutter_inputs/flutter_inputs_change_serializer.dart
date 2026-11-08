import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_field.dart';

class FlutterInputsChangeSerializer {
  final DartCodeGenUtils _u;
  final FlutterConfig _config;

  FlutterInputsChangeSerializer(this._u, this._config);

  String onFieldChangedMethod() => _u.createMethod(
        returnType: 'void',
        methodName: '_onFieldChanged',
        arguments: [],
        namedArguments: false,
        statements: [
          _u.inlineIfStatement(condition: '!mounted', statement: 'return;'),
          '_notifyContextChange();',
          '_scheduleOnChange();',
          if (_config.persistDrafts) '_scheduleDraftSave();',
          _u.inlineIfStatement(condition: '!_asyncNotifying', statement: '_scheduleAllAsyncValidations();'),
          '_updateErrorsNotifier();',
        ],
      );

  String notifyContextChangeMethod() => _u.createMethod(
        returnType: 'void',
        methodName: '_notifyContextChange',
        arguments: [],
        namedArguments: false,
        statements: ['_form.onContextChange?.call(_buildContext());'],
      );

  String scheduleOnChangeMethod() => _u.createMethod(
        returnType: 'void',
        methodName: '_scheduleOnChange',
        arguments: [],
        namedArguments: false,
        statements: [
          _u.inlineIfStatement(condition: '_form.onChange == null', statement: 'return;'),
          '_debounceTimer?.cancel();',
          '_debounceTimer = Timer(_form.debounceDuration, () ${_u.block([
            _u.inlineIfStatement(condition: 'mounted', statement: '_form.onChange?.call(tryRead());'),
          ])});',
        ],
      );

  String scheduleAllAsyncValidationsMethod(List<GLField> validatableFields) =>
      _u.createMethod(
        returnType: 'void',
        methodName: '_scheduleAllAsyncValidations',
        arguments: [],
        namedArguments: false,
        statements: validatableFields.map((f) {
          final cap = '${f.codeName[0].toUpperCase()}${f.codeName.substring(1)}';
          return '_schedule${cap}AsyncValidation();';
        }).toList(),
      );

  List<String> asyncSchedulerMethods(List<GLField> validatableFields, List<GLField> textFields) =>
      validatableFields.map((f) {
        final name = f.codeName;
        final cap = '${name[0].toUpperCase()}${name.substring(1)}';
        final valueExpr = textFields.contains(f) ? '_${name}Controller.text' : '_$name';
        return _u.createMethod(
          returnType: 'void',
          methodName: '_schedule${cap}AsyncValidation',
          arguments: [],
          namedArguments: false,
          statements: [
            '_${name}AsyncTimer?.cancel();',
            _u.inlineIfStatement(condition: '_form.validations?.$name == null', statement: 'return;'),
            '_${name}AsyncTimer = Timer(_form.debounceDuration, () async ${_u.block([
              _u.inlineIfStatement(condition: '!mounted', statement: 'return;'),
              '_asyncNotifying = true;',
              'setState(() { _${name}Validating = true; _${name}AsyncError = null; });',
              '_asyncNotifying = false;',
              'final r = await _form.validations!.$name!($valueExpr, _buildContext());',
              _u.inlineIfStatement(condition: '!mounted', statement: 'return;'),
              '_asyncNotifying = true;',
              'setState(() { _${name}Validating = false; _${name}AsyncError = r; });',
              '_asyncNotifying = false;',
              '_${name}FieldKey.currentState?.validate();',
              '_updateErrorsNotifier();',
            ])});',
          ],
        );
      }).toList();

}
