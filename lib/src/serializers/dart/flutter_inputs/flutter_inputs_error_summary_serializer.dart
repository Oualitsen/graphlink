import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'flutter_inputs_type_helpers.dart';

class FlutterInputsErrorSummarySerializer {
  final DartCodeGenUtils _u;
  final FlutterInputsTypeHelpers _types;

  FlutterInputsErrorSummarySerializer(this._u, this._types);

  String updateErrorsNotifierMethod(
    String inputName,
    List<GLField> allFields,
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
  ) {
    final scrollableFields = allFields
        .where((f) => textFields.contains(f) || enumFields.contains(f) || boolFields.contains(f))
        .toList();

    if (scrollableFields.isEmpty) {
      return _u.createMethod(
        returnType: 'void', methodName: '_updateErrorsNotifier',
        arguments: [], namedArguments: false, statements: [],
      );
    }

    final addEntries = scrollableFields.map((f) {
      final defaultIdx = 1000 + allFields.indexOf(f);
      return _u.ifStatement(
        condition: "_${f.codeName}FieldKey.currentState?.hasError == true",
        ifBlockStatements: [
          "entries.add(MapEntry(ord.${f.codeName} ?? $defaultIdx, MapEntry('${f.codeName}', _${f.codeName}FieldKey.currentState!.errorText!)));",
        ],
      );
    }).toList();

    return _u.createMethod(
      returnType: 'void',
      methodName: '_updateErrorsNotifier',
      arguments: [],
      namedArguments: false,
      statements: [
        _u.constDecl('ord', '_form.order ?? const ${inputName}Order()'),
        _u.constDecl('entries', '<MapEntry<int, MapEntry<String, String>>>[]'),
        ...addEntries,
        'entries.sort((a, b) => a.key.compareTo(b.key));',
        '_errorsNotifier.value = Map.fromEntries(entries.map((e) => e.value));',
      ],
    );
  }

  String scrollToFieldMethod(
    String inputName,
    List<GLField> allFields,
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
  ) {
    final scrollableFields = allFields
        .where((f) => textFields.contains(f) || enumFields.contains(f) || boolFields.contains(f))
        .toList();

    final cases = scrollableFields.map((f) => DartCaseStatement(
      caseValue: "'${f.codeName}'",
      statement: _u.block([
        _u.constDecl('ctx', '_${f.codeName}FieldKey.currentContext'),
        _u.inlineIfStatement(
          condition: 'ctx != null',
          statement: '${_u.callExpression('Scrollable.ensureVisible', ['ctx', 'duration: const Duration(milliseconds: 300)', 'curve: Curves.easeInOut'])};',
        ),
      ]),
    )).toList();

    return _u.createMethod(
      returnType: 'void',
      methodName: 'scrollToField',
      namedArguments: false,
      arguments: ['String fieldName'],
      statements: [
        _u.switchStatement(expression: 'fieldName', cases: cases, defaultStatements: []),
      ],
    );
  }

  String serializeErrorSummaryClass(
    String inputName,
    List<GLField> allFields,
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
  ) {
    final scrollableFields = allFields
        .where((f) => textFields.contains(f) || enumFields.contains(f) || boolFields.contains(f))
        .toList();
    final stateName = '_${inputName}ErrorSummaryState';
    const errorColor = 'Theme.of(context).colorScheme.error';

    final errorRow = _u.callExpression('Row', [
      _u.listArg('children', [
        _u.callExpression('Icon', ['Icons.error_outline', 'color: $errorColor', 'size: 16']),
        'const SizedBox(width: 8)',
        _u.callExpression('Expanded', [
          'child: ${_u.callExpression('Text', [
            "'\${_label(e.key)}: \${e.value}'",
            'style: TextStyle(color: $errorColor, fontSize: 13)',
          ])}',
        ]),
      ]),
    ]);
    final errorTile = _u.callExpression('Semantics', [
      'liveRegion: true',
      'child: ${_u.callExpression('InkWell', [
        'onTap: () => widget.formKey.currentState?.scrollToField(e.key)',
        'child: ${_u.callExpression('Padding', [
          'padding: const EdgeInsets.symmetric(vertical: 4)',
          'child: $errorRow',
        ])}',
      ])}',
    ]);

    final summaryClass = _u.createClass(
      className: '${inputName}ErrorSummary',
      extendsClassName: 'StatefulWidget',
      statements: [
        'final GlobalKey<${inputName}FormState> formKey;',
        _u.createMethod(
          isConst: true,
          methodName: '${inputName}ErrorSummary',
          arguments: ['required this.formKey', 'super.key'],
        ),
        _u.createMethod(
          override: true,
          returnType: 'State<${inputName}ErrorSummary>',
          methodName: 'createState',
          namedArguments: false,
          arguments: [],
          statements: ['return $stateName();'],
        ),
      ],
    );

    final stateClass = _u.createClass(
      className: stateName,
      extendsClassName: 'State<${inputName}ErrorSummary>',
      statements: [
        _u.createMethod(
          override: true,
          returnType: 'void',
          methodName: 'initState',
          namedArguments: false,
          arguments: [],
          statements: [
            'super.initState();',
            '// Trigger a rebuild once the form state is available.',
            'WidgetsBinding.instance.addPostFrameCallback(${_u.functionLiteral(['_'], [
              _u.inlineIfStatement(condition: 'mounted', statement: 'setState(${_u.functionLiteral([], [])});'),
            ])});',
          ],
        ),
        _u.createMethod(
          returnType: 'String',
          methodName: '_label',
          namedArguments: false,
          arguments: ['String field'],
          statements: [
            _u.switchStatement(
              expression: 'field',
              cases: [
                for (final f in scrollableFields)
                  DartCaseStatement(
                    caseValue: "'${f.codeName}'",
                    statement: "return '${_types.humanize(f.name.token)}';",
                  ),
              ],
              defaultStatements: ['return field;'],
            ),
          ],
        ),
        _u.createMethod(
          override: true,
          returnType: 'Widget',
          methodName: 'build',
          namedArguments: false,
          arguments: ['BuildContext context'],
          statements: [
            _u.constDecl('state', 'widget.formKey.currentState'),
            _u.inlineIfStatement(condition: 'state == null', statement: 'return const SizedBox.shrink();'),
            'return ${_u.callExpression('ListenableBuilder', [
              'listenable: state.errorsNotifier',
              'builder: ${_u.functionLiteral(['context', '_'], [
                'final errors = state.errorsNotifier.value;',
                _u.inlineIfStatement(condition: 'errors.isEmpty', statement: 'return const SizedBox.shrink();'),
                'return ${_u.callExpression('Column', [
                  'crossAxisAlignment: CrossAxisAlignment.start',
                  'children: errors.entries.map((e) => $errorTile).toList()',
                ])};',
              ])}',
            ])};',
          ],
        ),
      ],
    );

    return '$summaryClass\n\n$stateClass';
  }


  String serializeScrollToFirstErrorMethod(
    String inputName,
    List<GLField> fields,
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
  ) {
    final scrollableFields = fields
        .where((f) => textFields.contains(f) || enumFields.contains(f) || boolFields.contains(f))
        .toList();

    if (scrollableFields.isEmpty) {
      return _u.createMethod(
        returnType: 'void',
        methodName: '_scrollToFirstError',
        arguments: [],
        namedArguments: false,
        statements: [],
      );
    }

    final addEntries = scrollableFields.map((f) {
      final defaultIdx = 1000 + fields.indexOf(f);
      return "entries.add(MapEntry(ord.${f.codeName} ?? $defaultIdx, _${f.codeName}FieldKey));";
    }).toList();

    return _u.createMethod(
      returnType: 'void',
      methodName: '_scrollToFirstError',
      arguments: [],
      namedArguments: false,
      statements: [
        _u.constDecl('ord', '_form.order ?? const ${inputName}Order()'),
        _u.constDecl('entries', '<MapEntry<int, GlobalKey<FormFieldState>>>[]'),
        ...addEntries,
        'entries.sort((a, b) => a.key.compareTo(b.key));',
        _u.forEachLoop(
          variable: 'e',
          iterable: 'entries',
          statements: [
            _u.constDecl('ctx', 'e.value.currentContext'),
            _u.ifStatement(
              condition: 'ctx != null && (e.value.currentState?.hasError ?? false)',
              ifBlockStatements: [
                '${_u.callExpression('Scrollable.ensureVisible', ['ctx', 'duration: const Duration(milliseconds: 300)', 'curve: Curves.easeInOut'])};',
                'return;',
              ],
            ),
          ],
        ),
      ],
    );
  }

}
