import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'flutter_inputs_type_helpers.dart';

class FlutterInputsCompanionSerializer {
  final DartCodeGenUtils _u;
  final FlutterInputsTypeHelpers _types;

  FlutterInputsCompanionSerializer(this._u, this._types);

  String serializeDropdownLabelsClass(
      String inputName, List<GLField> enumFields, List<GLField> boolFields, List<GLField> enumListFields) {
    if (enumFields.isEmpty && boolFields.isEmpty && enumListFields.isEmpty) {
      return _u.createClass(
        className: '${inputName}DropdownLabels',
        statements: [
          _u.createMethod(isConst: true, methodName: '${inputName}DropdownLabels', arguments: []),
        ],
      );
    }
    return _u.createClass(
      className: '${inputName}DropdownLabels',
      statements: [
        ...enumFields.map((f) => 'final ${_types.resolveTypeCodeName(f.type.firstType.token)}Labels? ${f.codeName};'),
        ...boolFields.map((f) => 'final BooleanLabels? ${f.codeName};'),
        ...enumListFields.map((f) => 'final ${_types.resolveTypeCodeName(f.type.inlineType.firstType.token)}Labels? ${f.codeName};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}DropdownLabels',
          namedArguments: true,
          arguments: [
            ...enumFields.map((f) => 'this.${f.codeName}'),
            ...boolFields.map((f) => 'this.${f.codeName}'),
            ...enumListFields.map((f) => 'this.${f.codeName}'),
          ],
        ),
      ],
    );
  }

  String serializeLabelsClass(String inputName, List<GLField> fields) {
    return _u.createClass(
      className: '${inputName}Labels',
      statements: [
        ...fields.expand((f) => ['final Widget? ${f.codeName};', 'final String? ${f.codeName}Info;']),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}Labels',
          namedArguments: true,
          arguments: fields.expand((f) => ['this.${f.codeName}', 'this.${f.codeName}Info']).toList(),
        ),
      ],
    );
  }

  String serializeValuesClass(String inputName, List<GLField> fields) {
    // Input fields are excluded — they're handled by their own nested key pattern.
    final valueFields = fields.where((f) => !_types.isInputField(f)).toList();
    return _u.createClass(
      className: '${inputName}Values',
      statements: [
        ...valueFields.map((f) =>
            'final InputFormWidget<${_types.valuesFieldType(f)}> Function(Key)? ${f.codeName};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}Values',
          namedArguments: true,
          arguments: valueFields.map((f) => 'this.${f.codeName}').toList(),
        ),
      ],
    );
  }

  String serializeVisibilityClass(String inputName, List<GLField> fields) {
    final ctx = '${inputName}FormContext';
    return _u.createClass(
      className: '${inputName}Visibility',
      statements: [
        ...fields.map((f) => 'final FieldVisibility Function($ctx)? ${f.codeName};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}Visibility',
          namedArguments: true,
          arguments: fields.map((f) => 'this.${f.codeName}').toList(),
        ),
      ],
    );
  }

  String serializeFormContextClass(String inputName, List<GLField> contextFields) {
    return _u.createClass(
      className: '${inputName}FormContext',
      statements: [
        ...contextFields.map((f) => 'final ${_types.formContextFieldType(f)} ${f.codeName};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}FormContext',
          namedArguments: true,
          arguments: contextFields.map((f) {
            final type = _types.formContextFieldType(f);
            return type.endsWith('?') ? 'this.${f.codeName}' : 'required this.${f.codeName}';
          }).toList(),
        ),
      ],
    );
  }

  String serializeDefaultsClass(String inputName, List<GLField> formFields) {
    return _u.createClass(
      className: '${inputName}Defaults',
      statements: [
        ...formFields.map((f) => 'final ${_types.defaultsFieldType(f)} ${f.codeName};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}Defaults',
          namedArguments: true,
          arguments: formFields.map((f) => 'this.${f.codeName}').toList(),
        ),
      ],
    );
  }

  String serializeOrderClass(String inputName, List<GLField> fields) {
    return _u.createClass(
      className: '${inputName}Order',
      statements: [
        ...fields.map((f) => 'final int? ${f.codeName};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}Order',
          namedArguments: true,
          arguments: fields.map((f) => 'this.${f.codeName}').toList(),
        ),
      ],
    );
  }

  String serializeWidgetsClass(String inputName, List<GLField> enumFields, List<GLField> boolFields) {
    return _u.createClass(
      className: '${inputName}Widgets',
      statements: [
        ...enumFields.map((f) => 'final SelectWidget? ${f.codeName};'),
        ...enumFields.map((f) => 'final Widget? Function(${_types.resolveTypeCodeName(f.type.firstType.token)})? ${f.codeName}Avatar;'),
        ...boolFields.map((f) => 'final BoolFieldWidget? ${f.codeName};'),
        ...boolFields.map((f) => 'final Widget? Function(bool)? ${f.codeName}Avatar;'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}Widgets',
          namedArguments: true,
          arguments: [
            ...enumFields.expand((f) => ['this.${f.codeName}', 'this.${f.codeName}Avatar']),
            ...boolFields.expand((f) => ['this.${f.codeName}', 'this.${f.codeName}Avatar']),
          ],
        ),
      ],
    );
  }

  String serializeFieldIconsClass(String inputName, List<GLField> textFields, List<GLField> enumFields) {
    final iconFields = [...textFields, ...enumFields];
    if (iconFields.isEmpty) return '';
    return _u.createClass(
      className: '${inputName}FieldIcons',
      statements: [
        ...iconFields.map((f) => 'final Widget? ${f.codeName};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}FieldIcons',
          namedArguments: true,
          arguments: iconFields.map((f) => 'this.${f.codeName}').toList(),
        ),
      ],
    );
  }

  String serializeTextConfigClass(String inputName, List<GLField> textFields) {
    return _u.createClass(
      className: '${inputName}TextConfig',
      statements: [
        ...textFields.map((f) => 'final TextFieldOptions? ${f.codeName};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}TextConfig',
          namedArguments: true,
          arguments: textFields.map((f) => 'this.${f.codeName}').toList(),
        ),
      ],
    );
  }

  String serializeDateConfigClass(String inputName, List<GLField> dateEligibleFields) {
    return _u.createClass(
      className: '${inputName}DateConfig',
      statements: [
        ...dateEligibleFields.map((f) => 'final DateInputConfig? ${f.codeName};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}DateConfig',
          namedArguments: true,
          arguments: dateEligibleFields.map((f) {
            final h = _heuristicDateConfig(f);
            return h != null ? 'this.${f.codeName} = $h' : 'this.${f.codeName}';
          }).toList(),
        ),
      ],
    );
  }

  String serializeValidationsClass(String inputName, List<GLField> formFields,
      List<GLField> enumFields, List<GLField> boolFields) {
    return _u.createClass(
      className: '${inputName}Validations',
      statements: [
        ...formFields.map((f) => 'final ${_types.validatorType(f, enumFields, boolFields, inputName)} ${f.codeName};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}Validations',
          namedArguments: true,
          arguments: formFields.map((f) => 'this.${f.codeName}').toList(),
        ),
      ],
    );
  }

  String serializeStepConfigClass(
      String inputName,
      bool hasScalarFields,
      List<GLField> inputFields,
      List<GLField> inputListFields) {
    final stepFields = [...inputFields, ...inputListFields];
    return _u.createClass(
      className: '${inputName}StepConfig',
      statements: [
        if (hasScalarFields) 'final InputStepOptions? scalarFields;',
        ...stepFields.map((f) => 'final InputStepOptions? ${f.codeName};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}StepConfig',
          namedArguments: true,
          arguments: [
            if (hasScalarFields) 'this.scalarFields',
            ...stepFields.map((f) => 'this.${f.codeName}'),
          ],
        ),
      ],
    );
  }

  String serializeSelectConfigClass(String inputName, List<GLField> textFields) {
    return _u.createClass(
      className: '${inputName}SelectConfig',
      statements: [
        ...textFields.map((f) => 'final SelectFieldConfig<${_types.dartScalarType(f)}>? ${f.codeName};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}SelectConfig',
          namedArguments: true,
          arguments: textFields.map((f) => 'this.${f.codeName}').toList(),
        ),
      ],
    );
  }

  String serializeFocusNodesClass(String inputName, List<GLField> textFields) {
    return _u.createClass(
      className: '${inputName}FocusNodes',
      statements: [
        ...textFields.map((f) => 'final FocusNode? ${f.codeName};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}FocusNodes',
          namedArguments: true,
          arguments: textFields.map((f) => 'this.${f.codeName}').toList(),
        ),
      ],
    );
  }

  String? _heuristicDateConfig(GLField f) {
    final n = f.name.token.toLowerCase();
    if (n.endsWith('at')) return 'const DateInputConfig(type: DateType.dateTime)';
    if (n.endsWith('time')) return 'const DateInputConfig(type: DateType.dateTime)';
    if (n.endsWith('date')) return 'const DateInputConfig()';
    if (n.contains('birthday') || n.contains('dob') || n.contains('born')) return 'const DateInputConfig()';
    if (n.contains('expiry') || n.contains('deadline') || n.contains('due')) return 'const DateInputConfig()';
    return null;
  }
}
