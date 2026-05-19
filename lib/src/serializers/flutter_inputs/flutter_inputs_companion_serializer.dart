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
        ...enumFields.map((f) => 'final ${f.type.firstType.token}Labels? ${f.name};'),
        ...boolFields.map((f) => 'final BooleanLabels? ${f.name};'),
        ...enumListFields.map((f) => 'final ${f.type.inlineType.firstType.token}Labels? ${f.name};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}DropdownLabels',
          namedArguments: true,
          arguments: [
            ...enumFields.map((f) => 'this.${f.name}'),
            ...boolFields.map((f) => 'this.${f.name}'),
            ...enumListFields.map((f) => 'this.${f.name}'),
          ],
        ),
      ],
    );
  }

  String serializeLabelsClass(String inputName, List<GLField> fields) {
    return _u.createClass(
      className: '${inputName}Labels',
      statements: [
        ...fields.map((f) => 'final Widget? ${f.name};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}Labels',
          namedArguments: true,
          arguments: fields.map((f) => 'this.${f.name}').toList(),
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
            'final InputFormWidget<${_types.valuesFieldType(f)}> Function(Key)? ${f.name};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}Values',
          namedArguments: true,
          arguments: valueFields.map((f) => 'this.${f.name}').toList(),
        ),
      ],
    );
  }

  String serializeVisibilityClass(String inputName, List<GLField> fields) {
    final ctx = '${inputName}FormContext';
    return _u.createClass(
      className: '${inputName}Visibility',
      statements: [
        ...fields.map((f) => 'final FieldVisibility Function($ctx)? ${f.name};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}Visibility',
          namedArguments: true,
          arguments: fields.map((f) => 'this.${f.name}').toList(),
        ),
      ],
    );
  }

  String serializeFormContextClass(String inputName, List<GLField> contextFields) {
    return _u.createClass(
      className: '${inputName}FormContext',
      statements: [
        ...contextFields.map((f) => 'final ${_types.formContextFieldType(f)} ${f.name};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}FormContext',
          namedArguments: true,
          arguments: contextFields.map((f) {
            final type = _types.formContextFieldType(f);
            return type.endsWith('?') ? 'this.${f.name}' : 'required this.${f.name}';
          }).toList(),
        ),
      ],
    );
  }

  String serializeDefaultsClass(String inputName, List<GLField> formFields) {
    return _u.createClass(
      className: '${inputName}Defaults',
      statements: [
        ...formFields.map((f) => 'final ${_types.defaultsFieldType(f)} ${f.name};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}Defaults',
          namedArguments: true,
          arguments: formFields.map((f) => 'this.${f.name}').toList(),
        ),
      ],
    );
  }

  String serializeOrderClass(String inputName, List<GLField> fields) {
    return _u.createClass(
      className: '${inputName}Order',
      statements: [
        ...fields.map((f) => 'final int? ${f.name};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}Order',
          namedArguments: true,
          arguments: fields.map((f) => 'this.${f.name}').toList(),
        ),
      ],
    );
  }

  String serializeWidgetsClass(String inputName, List<GLField> enumFields, List<GLField> boolFields) {
    return _u.createClass(
      className: '${inputName}Widgets',
      statements: [
        ...enumFields.map((f) => 'final EnumFieldWidget? ${f.name};'),
        ...boolFields.map((f) => 'final BoolFieldWidget? ${f.name};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}Widgets',
          namedArguments: true,
          arguments: [
            ...enumFields.map((f) => 'this.${f.name}'),
            ...boolFields.map((f) => 'this.${f.name}'),
          ],
        ),
      ],
    );
  }

  String serializeTextConfigClass(String inputName, List<GLField> textFields) {
    return _u.createClass(
      className: '${inputName}TextConfig',
      statements: [
        ...textFields.map((f) => 'final TextFieldOptions? ${f.name};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}TextConfig',
          namedArguments: true,
          arguments: textFields.map((f) => 'this.${f.name}').toList(),
        ),
      ],
    );
  }

  String serializeDateConfigClass(String inputName, List<GLField> dateEligibleFields) {
    return _u.createClass(
      className: '${inputName}DateConfig',
      statements: [
        ...dateEligibleFields.map((f) => 'final DateInputConfig? ${f.name};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}DateConfig',
          namedArguments: true,
          arguments: dateEligibleFields.map((f) {
            final h = _heuristicDateConfig(f);
            return h != null ? 'this.${f.name} = $h' : 'this.${f.name}';
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
        ...formFields.map((f) => 'final ${_types.validatorType(f, enumFields, boolFields, inputName)} ${f.name};'),
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}Validations',
          namedArguments: true,
          arguments: formFields.map((f) => 'this.${f.name}').toList(),
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
