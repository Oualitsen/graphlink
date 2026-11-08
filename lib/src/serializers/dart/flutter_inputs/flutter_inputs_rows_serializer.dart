import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'flutter_inputs_draft_serializer.dart';
import 'flutter_inputs_field_serializer.dart';
import 'flutter_inputs_type_helpers.dart';

class FlutterInputsRowsSerializer {
  final DartCodeGenUtils _u;
  final FlutterConfig _config;
  final FlutterInputsTypeHelpers _types;
  final FlutterInputsFieldSerializer _fields;
  final FlutterInputsDraftSerializer _drafts;

  FlutterInputsRowsSerializer(this._u, this._config, this._types, this._fields, this._drafts);

  String serializeVisibleRowsMethod(
    String methodName,
    String inputName,
    List<GLField> fields,
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
    List<GLField> listFields,
    List<GLField> inputFields,
  ) {
    final visDecls = fields.map((f) =>
        _u.constDecl('${f.codeName}Vis', 'vis.${f.codeName}?.call(ctx) ?? FieldVisibility.enabled')).toList();

    final rowLines = buildFieldLines(
      inputName,
      fields, textFields, enumFields, boolFields, listFields, inputFields,
      (f, idx, w) => "entries.add(MapEntry(ord.${f.codeName} ?? $idx, $w))",
    );

    return _u.createMethod(
      returnType: 'List<Widget>',
      methodName: methodName,
      arguments: [],
      namedArguments: false,
      statements: [
        _u.constDecl('vis', '_form.visibility ?? const ${inputName}Visibility()'),
        _u.constDecl('ord', '_form.order ?? const ${inputName}Order()'),
        _u.constDecl('ctx', '_buildContext()'),
        _u.constDecl('entries', '<MapEntry<int, Widget>>[]'),
        ...visDecls,
        ...rowLines,
        'entries.sort((a, b) => a.key.compareTo(b.key));',
        'return entries.map((e) => e.value).toList();',
      ],
    );
  }

  String buildContextMethod(String inputName, List<GLField> contextFields) {
    final args = contextFields.map((f) =>
        '${f.codeName}: ${_types.formContextFieldInitExpr(f)}').toList();
    return _u.createMethod(
      returnType: '${inputName}FormContext',
      methodName: '_buildContext',
      arguments: [],
      namedArguments: false,
      statements: [
        'return ${_u.callExpression('${inputName}FormContext', args)};',
      ],
    );
  }

  // ── Nested input field row ────────────────────────────────────────────────────

  String inputFieldRowMethod(GLField f) {
    final name = f.codeName;
    final childType = _types.resolveTypeCodeName(f.type.firstType.token);

    final defaultChildForm = _u.callExpression('${childType}Form', [
      'key: _${name}Key',
      'initialValues: _form.initialValues?.$name',
      'strings: _form.strings',
      'requiredIndicator: _form.requiredIndicator',
      'requiredLabel: _form.requiredLabel',
      'optionalLabel: _form.optionalLabel',
      'labelPosition: ${childType}LabelPosition.values.byName(_form.labelPosition.name)',
      'labelWidth: _form.labelWidth',
      'gap: _form.gap',
      // bubble sub-form field changes up to the parent's onChange / onContextChange
      'onContextChange: (_) => _onFieldChanged()',
      if (_config.persistDrafts) ..._drafts.childArgs(name),
    ]);
    // A Values override replaces the generated child form entirely, but reuses the
    // same GlobalKey<InputFormState<Child>> so read/validate/reset/isDirty/
    // setSubmitting keep working transparently against whichever widget is built.
    final childForm = '_form.values?.$name?.call(_${name}Key) ?? $defaultChildForm';

    return _u.createMethod(
      returnType: 'Widget',
      methodName: '_${name}InputRow',
      namedArguments: false,
      arguments: ['Widget label', 'bool enabled'],
      statements: [
        _u.constDecl('child', _u.callExpression('Column', [
          'crossAxisAlignment: CrossAxisAlignment.start',
          _u.listArg('children', [
            'DefaultTextStyle(style: Theme.of(context).textTheme.labelLarge ?? const TextStyle(fontWeight: FontWeight.bold), child: Padding(padding: const EdgeInsets.only(bottom: 8), child: label))',
            childForm,
          ]),
        ])),
        'return enabled ? child : IgnorePointer(ignoring: true, child: Opacity(opacity: 0.38, child: child));',
      ],
    );
  }

  List<String> buildFieldLines(
    String inputName,
    List<GLField> fields,
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
    List<GLField> listFields,
    List<GLField> inputFields,
    String Function(GLField f, int defaultIdx, String widgetExpr) accumulate,
  ) {
    final directFields = {
      ...listFields.where((f) => _types.isEnumListField(f) || _types.isScalarListField(f)),
    };
    final rowMethodFields = {...enumFields, ...boolFields, ...inputFields};

    return fields.asMap().entries.map((entry) {
      final i = entry.key;
      final f = entry.value;
      final humanLabel = _types.humanize(f.name.token);
      final enabledExpr = '!_submitting && ${_config.persistDrafts ? '!_restoring && ' : ''}${f.codeName}Vis == FieldVisibility.enabled';
      final fieldWidget = _fields.fieldWidgetExpr(f, textFields, enumFields, boolFields, listFields, enabledExpr);
      final defaultIdx = 1000 + i;
      final isRequired = !f.type.nullable;
      final labelStmt = _u.constDecl("rl", "_requiredLabel(_form.labels?.${f.codeName} ?? const Text('$humanLabel'), $isRequired); final label = _form.labelPosition == ${inputName}LabelPosition.floatingLabel ? rl : _labelWithInfo(rl, _form.labels?.${f.codeName}Info)");

      final String widgetExpr;
      if (inputFields.contains(f)) {
        widgetExpr = '_${f.codeName}InputRow(label, $enabledExpr)';
      } else if (textFields.contains(f)) {
        widgetExpr = '_form.values?.${f.codeName}?.call(_${f.codeName}OverrideKey, label) ?? _${f.codeName}ScalarRow(label, $enabledExpr)';
      } else if (rowMethodFields.contains(f)) {
        widgetExpr = '_form.values?.${f.codeName}?.call(_${f.codeName}OverrideKey, label) ?? _${f.codeName}Row(label, $enabledExpr)';
      } else if (directFields.contains(f)) {
        widgetExpr = '_form.values?.${f.codeName}?.call(_${f.codeName}OverrideKey) ?? $fieldWidget';
      } else {
        widgetExpr = '_field(label, _form.values?.${f.codeName}?.call(_${f.codeName}OverrideKey) ?? $fieldWidget)';
      }

      return _u.ifStatement(
        condition: '${f.codeName}Vis != FieldVisibility.hidden',
        ifBlockStatements: [labelStmt, '${accumulate(f, defaultIdx, "_withFloatingInfo($widgetExpr, _form.labels?.${f.codeName}Info)")};'],
      );
    }).toList();
  }

  String serializeScalarRowsMethod(
      String inputName,
      List<GLField> fields,
      List<GLField> textFields,
      List<GLField> enumFields,
      List<GLField> boolFields,
      List<GLField> listFields) {
    final scalarFields = fields
        .where((f) => !_types.isInputField(f) && !_types.isInputListField(f))
        .toList();
    final scalarListFields = listFields
        .where((f) => !_types.isInputListField(f))
        .toList();
    return serializeVisibleRowsMethod(
      '_scalarRows',
      inputName,
      scalarFields,
      textFields,
      enumFields,
      boolFields,
      scalarListFields,
      [],
    );
  }

}
