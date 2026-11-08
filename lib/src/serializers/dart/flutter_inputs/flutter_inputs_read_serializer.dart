import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'flutter_inputs_type_helpers.dart';

class FlutterInputsReadSerializer {
  final DartCodeGenUtils _u;
  final FlutterConfig _config;
  final FlutterInputsTypeHelpers _types;

  FlutterInputsReadSerializer(this._u, this._config, this._types);

  String serializeBuildResultMethod(
    String inputName,
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
    List<GLField> listFields,
    List<GLField> inputFields,
  ) {
    final allFormFields = [...textFields, ...enumFields, ...boolFields, ...inputFields];
    final visDecls = [...allFormFields, ...listFields].map((f) =>
        _u.constDecl('${f.codeName}Vis', 'vis.${f.codeName}?.call(ctx) ?? FieldVisibility.enabled')).toList();

    final nonInputAssignments = [...textFields, ...enumFields, ...boolFields].map((f) {
      final name = f.codeName;
      final visibleExpr = visibleReadExpr(f, textFields, enumFields, boolFields);
      final hiddenExpr = hiddenReadExpr(f);
      return '$name: ${name}Vis == FieldVisibility.hidden '
          '? $hiddenExpr '
          ': _form.values?.$name != null '
              '? _${name}OverrideKey.currentState!.read() '
              ': $visibleExpr';
    }).toList();

    final inputAssignments = inputFields.map((f) {
      final name = f.codeName;
      final hiddenExpr = hiddenReadExpr(f);
      return '$name: ${name}Vis != FieldVisibility.hidden ? _${name}Key.currentState!.read() : $hiddenExpr';
    }).toList();

    final listAssignments = listFields.map((f) {
      final name = f.codeName;
      final hiddenExpr = hiddenReadExpr(f);
      return '$name: ${name}Vis == FieldVisibility.hidden '
          '? $hiddenExpr '
          ': _form.values?.$name != null '
              '? _${name}OverrideKey.currentState!.read() '
              ': _$name';
    }).toList();

    return _u.createMethod(
      returnType: inputName,
      methodName: '_buildResult',
      arguments: [],
      namedArguments: false,
      statements: [
        _u.constDecl('vis', '_form.visibility ?? const ${inputName}Visibility()'),
        _u.constDecl('def', '_form.hiddenDefaults ?? const ${inputName}Defaults()'),
        _u.constDecl('ctx', '_buildContext()'),
        ...visDecls,
        'return ${_u.callExpression(inputName, [...nonInputAssignments, ...inputAssignments, ...listAssignments])};',
      ],
    );
  }

  String serializeReadMethod(String inputName) => _u.createMethod(
        override: true,
        returnType: inputName,
        methodName: 'read',
        arguments: [],
        namedArguments: false,
        statements: [
          _u.ifStatement(
            condition: '_submitting',
            ifBlockStatements: ["throw InputReadException('Form is submitting');"],
          ),
          if (_config.persistDrafts)
            _u.ifStatement(
              condition: '_restoring',
              ifBlockStatements: ["throw InputReadException('Form is restoring');"],
            ),
          _u.ifStatement(
            condition: '_isAsyncValidating',
            ifBlockStatements: ["throw InputReadException('Async validation in progress');"],
          ),
          _u.ifStatement(
            condition: '!validate()',
            ifBlockStatements: [
              '_scrollToFirstError();',
              "throw InputReadException('Validation failed');",
            ],
          ),
          'return _buildResult();',
        ],
      );

  String serializeTryReadMethod(String inputName) => _u.createMethod(
        returnType: '$inputName?',
        methodName: 'tryRead',
        arguments: [],
        namedArguments: false,
        statements: [
          _u.tryCatchFinally(
            tryStatements: ['return _buildResult();'],
            catchVariable: '_',
            catchStatements: ['return null;'],
          ),
        ],
      );

  String visibleReadExpr(GLField f, List<GLField> textFields, List<GLField> enumFields,
      List<GLField> boolFields) {
    final name = f.codeName;
    final dartType = _types.dartScalarType(f);
    final nullable = f.type.nullable;

    if (textFields.contains(f)) {
      if (dartType == 'int') {
        return nullable
            ? '_form.dateConfig?.$name != null ? _parseDate(_${name}Controller.text, _form.dateConfig!.$name!) : int.tryParse(_${name}Controller.text)'
            : '_form.dateConfig?.$name != null ? (_parseDate(_${name}Controller.text, _form.dateConfig!.$name!) ?? (throw InputReadException(\'$name: invalid date\'))) : int.parse(_${name}Controller.text)';
      }
      if (dartType == 'double') {
        return nullable ? 'double.tryParse(_${name}Controller.text)' : 'double.parse(_${name}Controller.text)';
      }
      return nullable
          ? '_${name}Controller.text.isEmpty ? null : _${name}Controller.text'
          : '_${name}Controller.text';
    }

    if (enumFields.contains(f)) {
      return nullable
          ? '_$name'
          : "_$name ?? (throw InputReadException('$name: no value selected'))";
    }

    if (boolFields.contains(f)) {
      final needsNullCheck = !nullable && _types.isTristateField(f);
      return needsNullCheck
          ? "_$name ?? (throw InputReadException('$name: no value selected'))"
          : '_$name';
    }

    return '_${name}Key.currentState!.read()';
  }

  String hiddenReadExpr(GLField f) {
    final name = f.codeName;
    return f.type.nullable
        ? 'def.$name'
        : "def.$name ?? (throw InputReadException('$name: default required when hidden'))";
  }
}
