import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'flutter_inputs_draft_serializer.dart';
import 'flutter_inputs_type_helpers.dart';

class FlutterInputsWidgetSerializer {
  final DartCodeGenUtils _u;
  final FlutterConfig _config;
  final FlutterInputsTypeHelpers _types;
  final FlutterInputsDraftSerializer _drafts;

  FlutterInputsWidgetSerializer(this._u, this._config, this._types, this._drafts);

  String serializeWidgetClass(
      String inputName, List<GLField> listFields, List<GLField> formFields,
      List<GLField> enumFields, List<GLField> boolFields, List<GLField> textFields,
      List<GLField> dateEligibleFields,
      List<GLField> inputFields, List<GLField> inputListFields) {
    final hasSubInputs = inputFields.isNotEmpty || inputListFields.isNotEmpty;
    final gap = _types.gapStr();
    final hasDropdownLabels = enumFields.isNotEmpty || boolFields.isNotEmpty || listFields.any(_types.isEnumListField);

    final listFieldDecls = <String>[];
    final listParams = <String>[];
    for (final f in listFields) {
      if (_types.isEnumListField(f)) {
        listFieldDecls.add('final List<${_types.listItemTypeNonNull(f)}> ${f.codeName};');
        listParams.add('this.${f.codeName} = ${_types.typedEmptyList(f)}');
      } else if (_types.isScalarListField(f)) {
        listFieldDecls.add('final List<${_types.listItemTypeNonNull(f)}> ${f.codeName};');
        listFieldDecls.add('final List<${_types.listItemTypeNonNull(f)}>? ${f.codeName}Options;');
        listParams.add('this.${f.codeName} = ${_types.typedEmptyList(f)}');
        listParams.add('this.${f.codeName}Options');
      } else {
        listFieldDecls.add('final ${_types.listDartType(f)} ${f.codeName};');
        listParams.add(f.type.nullable ? 'this.${f.codeName}' : 'required this.${f.codeName}');
      }
    }

    return _u.createClass(
      className: '${inputName}Form',
      extendsClassName: 'InputFormWidget<$inputName>',
      statements: [
        ...listFieldDecls,
        if (_config.persistDrafts) ..._drafts.widgetDecls(inputName),
        'final $inputName? initialValues;',
        if (hasDropdownLabels) 'final ${inputName}DropdownLabels? dropdownLabels;',
        'final ${inputName}Labels? labels;',
        'final ${inputName}Values? values;',
        'final ${inputName}Visibility? visibility;',
        'final ${inputName}Order? order;',
        'final ${inputName}Defaults? hiddenDefaults;',
        'final ${inputName}Validations? validations;',
        if (enumFields.isNotEmpty || boolFields.isNotEmpty) 'final ${inputName}Widgets? widgets;',
        if (textFields.isNotEmpty) 'final ${inputName}TextConfig? textConfig;',
        if (dateEligibleFields.isNotEmpty) 'final ${inputName}DateConfig? dateConfig;',
        if (textFields.isNotEmpty) 'final ${inputName}SelectConfig? selectConfig;',
        if (textFields.isNotEmpty) 'final ${inputName}FocusNodes? focusNodes;',
        if (textFields.isNotEmpty || enumFields.isNotEmpty) 'final ${inputName}FieldIcons? fieldIcons;',
        'final ${inputName}Layout layout;',
        'final ${inputName}LabelPosition labelPosition;',
        'final double labelWidth;',
        'final double gap;',
        'final RequiredIndicator requiredIndicator;',
        'final Widget? requiredLabel;',
        'final Widget? optionalLabel;',
        'final FormStrings strings;',
        'final MainAxisSize columnMainAxisSize;',
        if (hasSubInputs) 'final ${inputName}StepConfig? stepConfig;',
        if (hasSubInputs) 'final StepperType stepperType;',
        if (hasSubInputs) 'final Widget Function(BuildContext, ControlsDetails)? stepControlsBuilder;',
        if (hasSubInputs) 'final MainAxisAlignment stepControlsAlignment;',
        if (hasSubInputs) 'final StepperStrings stepperStrings;',
        '/// Called synchronously on every field change with a live snapshot of all field values.\n'
            '/// Use for instant reactive UI — visibility decisions, computed labels, live summaries.\n'
            'final void Function(${inputName}FormContext)? onContextChange;',
        '/// Called after [debounceDuration] with the result of [tryRead].\n'
            '/// Delivers `null` when the form is not yet parseable (required fields empty,\n'
            '/// invalid format, enum not selected). Delivers `$inputName` when the form\n'
            '/// is complete enough to submit. Note: custom [validations] are NOT run here —\n'
            '/// they only run on [read]. Use [onContextChange] to inspect raw field values\n'
            '/// when the form is incomplete.\n'
            'final void Function($inputName?)? onChange;',
        '/// How long to wait after the last field change before firing [onChange]. Default: 300ms.\n'
            'final Duration debounceDuration;',
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}Form',
          namedArguments: true,
          arguments: [
            'super.key',
            'this.initialValues',
            ...listParams,
            if (_config.persistDrafts) ...FlutterInputsDraftSerializer.widgetArgs,
            if (hasDropdownLabels) 'this.dropdownLabels',
            'this.labels',
            'this.values',
            'this.visibility',
            'this.order',
            'this.hiddenDefaults',
            'this.validations',
            if (enumFields.isNotEmpty || boolFields.isNotEmpty) 'this.widgets',
            if (textFields.isNotEmpty) 'this.textConfig',
            if (dateEligibleFields.isNotEmpty) 'this.dateConfig',
            if (textFields.isNotEmpty) 'this.selectConfig',
            if (textFields.isNotEmpty) 'this.focusNodes',
            if (textFields.isNotEmpty || enumFields.isNotEmpty) 'this.fieldIcons',
            'this.layout = ${inputName}Layout.${_config.defaultFormLayout.name}',
            'this.labelPosition = ${inputName}LabelPosition.${_config.defaultLabelPosition.name}',
            'this.labelWidth = ${_config.defaultLabelWidth % 1 == 0 ? _config.defaultLabelWidth.toInt() : _config.defaultLabelWidth}',
            'this.gap = $gap',
            'this.requiredIndicator = RequiredIndicator.${_config.defaultRequiredIndicator.name}',
            'this.requiredLabel',
            'this.optionalLabel',
            'this.strings = const FormStrings()',
            'this.columnMainAxisSize = MainAxisSize.min',
            if (hasSubInputs) 'this.stepConfig',
            if (hasSubInputs) 'this.stepperType = StepperType.${_config.defaultStepperOrientation.name}',
            if (hasSubInputs) 'this.stepControlsBuilder',
            if (hasSubInputs) 'this.stepControlsAlignment = MainAxisAlignment.spaceBetween',
            if (hasSubInputs) 'this.stepperStrings = const StepperStrings()',
            'this.onContextChange',
            'this.onChange',
            'this.debounceDuration = const Duration(milliseconds: ${_config.defaultDebounceDuration})',
          ],
        ),
        _u.createMethod(
          override: true,
          returnType: 'State<InputFormWidget<$inputName>>',
          methodName: 'createState',
          arguments: [],
          namedArguments: false,
          statements: ['return ${inputName}FormState();'],
        ),
      ],
    );
  }
}
