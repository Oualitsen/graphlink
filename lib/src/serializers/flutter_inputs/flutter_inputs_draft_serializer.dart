import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'flutter_inputs_type_helpers.dart';

class _DraftField {
  final GLField field;
  final String stateEncode;
  final String? overrideEncode;
  final String guard;
  final String value;
  final String stateAssign;

  const _DraftField({
    required this.field,
    required this.stateEncode,
    required this.overrideEncode,
    required this.guard,
    required this.value,
    required this.stateAssign,
  });

  String get name => field.codeName;
}

class FlutterInputsDraftSerializer {
  final DartCodeGenUtils _u;
  final FlutterInputsTypeHelpers _types;

  FlutterInputsDraftSerializer(this._u, this._types);

  static const stateVarDecls = [
    'bool _restoring = false;',
    'Timer? _draftTimer;',
    'String? _pendingDraft;',
  ];

  static const widgetArgs = ['this.draftStore', 'this.draftId'];

  static const disposeStatements = ['_draftTimer?.cancel();', '_flushDraft();'];

  static const clearDraftStatement = '_clearDraft();';

  List<String> widgetDecls(String inputName) => [
        "static const draftKey = 'graphlink_generated_form_$inputName';",
        "static String draftKeyFor([String? draftId]) => draftId == null ? draftKey : '\$draftKey:\$draftId';",
        'final FormDraftStore? draftStore;',
        'final String? draftId;',
      ];

  List<String> childArgs(String fieldName) => [
        'draftStore: _form.draftStore',
        "draftId: _form.draftId == null ? '$fieldName' : '\${_form.draftId}.$fieldName'",
      ];

  String initStatement() => _u.ifStatement(
        condition: '_form.draftStore != null',
        ifBlockStatements: [
          '_restoring = true;',
          'WidgetsBinding.instance.addPostFrameCallback((_) => _restoreDraft());',
        ],
      );

  List<String> stateMethods(
    String inputName,
    List<GLField> fields,
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
    List<GLField> listFields,
  ) {
    final entries = _entries(fields, textFields, enumFields, boolFields, listFields);
    return [
      'static const _draftSchemaHash = ${_types.draftSchemaHash(fields)};',
      'String get _draftKey => ${inputName}Form.draftKeyFor(_form.draftId);',
      _snapshotMethod(entries),
      _restoreMethod(entries),
      _scheduleSaveMethod(),
      _flushMethod(),
      _clearMethod(),
    ];
  }

  List<_DraftField> _entries(
    List<GLField> fields,
    List<GLField> textFields,
    List<GLField> enumFields,
    List<GLField> boolFields,
    List<GLField> listFields,
  ) {
    final entries = <_DraftField>[];
    for (final f in fields) {
      final name = f.codeName;
      final nullable = f.type.nullable;
      if (textFields.contains(f)) {
        if (_types.isPasswordField(f)) continue;
        final dartType = _types.dartScalarType(f);
        final persistableOverride = dartType == 'String' || dartType == 'int' || dartType == 'double';
        entries.add(_DraftField(
          field: f,
          stateEncode: '_${name}Controller.text',
          overrideEncode: persistableOverride ? 'v' : null,
          guard: dartType == 'int'
              ? 'raw is int'
              : dartType == 'double'
                  ? 'raw is num'
                  : 'raw is String',
          value: dartType == 'double' ? 'raw.toDouble()' : 'raw',
          stateAssign: _u.ifStatement(
            condition: 'raw is String',
            ifBlockStatements: ['_${name}Controller.text = raw;'],
          ),
        ));
      } else if (enumFields.contains(f)) {
        final enumType = _types.resolveTypeCodeName(f.type.firstType.token);
        entries.add(_DraftField(
          field: f,
          stateEncode: '_$name?.name',
          overrideEncode: nullable ? 'v?.name' : 'v.name',
          guard: 'raw is String',
          value: '$enumType.values.asNameMap()[raw]',
          stateAssign: _u.ifStatement(
            condition: 'raw is String',
            ifBlockStatements: ['_$name = $enumType.values.asNameMap()[raw];'],
            elseBlockStatements: [
              _u.ifStatement(
                condition: "raw == null && draft.containsKey('$name')",
                ifBlockStatements: ['_$name = null;'],
              ),
            ],
          ),
        ));
      } else if (boolFields.contains(f)) {
        final nullableState = _types.boolStateType(f) == 'bool?';
        entries.add(_DraftField(
          field: f,
          stateEncode: '_$name',
          overrideEncode: 'v',
          guard: 'raw is bool',
          value: 'raw',
          stateAssign: _assignIfValid(
            name,
            nullableState ? "raw is bool || (raw == null && draft.containsKey('$name'))" : 'raw is bool',
            nullableState ? 'raw as bool?' : 'raw',
          ),
        ));
      } else if (_types.isEnumListField(f)) {
        final enumType = _types.resolveTypeCodeName(f.type.inlineType.firstType.token);
        final item = f.type.inlineType.nullable ? 'e?.name' : 'e.name';
        final enumListValue = 'raw.map((s) => $enumType.values.asNameMap()[s]).whereType<$enumType>().toList()';
        entries.add(_DraftField(
          field: f,
          stateEncode: '_$name.map((e) => $item).toList()',
          overrideEncode: nullable ? 'v?.map((e) => $item).toList()' : 'v.map((e) => $item).toList()',
          guard: 'raw is List',
          value: enumListValue,
          stateAssign: _assignIfValid(name, 'raw is List', enumListValue),
        ));
      } else if (_types.isScalarListField(f) && _types.isJsonScalarType(_types.listItemTypeNonNull(f))) {
        final itemType = _types.listItemTypeNonNull(f);
        final scalarListValue = itemType == 'double'
            ? 'raw.whereType<num>().map((n) => n.toDouble()).toList()'
            : 'raw.whereType<$itemType>().toList()';
        entries.add(_DraftField(
          field: f,
          stateEncode: 'List.of(_$name)',
          overrideEncode: 'v',
          guard: 'raw is List',
          value: scalarListValue,
          stateAssign: _assignIfValid(name, 'raw is List', scalarListValue),
        ));
      }
    }
    return entries;
  }

  String _assignIfValid(String name, String condition, String value) => _u.ifStatement(
        condition: condition,
        ifBlockStatements: ['_$name = $value;'],
      );

  String _snapshotMethod(List<_DraftField> entries) {
    final statements = <String>[_u.constDecl('m', '<String, Object?>{}')];
    for (final e in entries) {
      final stateLine = "m['${e.name}'] = ${e.stateEncode};";
      final overrideEncode = e.overrideEncode;
      if (overrideEncode == null) {
        statements.add(_u.ifStatement(
          condition: '_form.values?.${e.name} == null',
          ifBlockStatements: [stateLine],
        ));
        continue;
      }
      statements.add(_u.ifStatement(
        condition: '_form.values?.${e.name} != null',
        ifBlockStatements: [
          _u.tryCatchFinally(
            tryStatements: [
              _u.constDecl('v', '_${e.name}OverrideKey.currentState!.read()'),
              "m['${e.name}'] = $overrideEncode;",
            ],
            catchVariable: '_',
            catchStatements: [],
          ),
        ],
        elseBlockStatements: [stateLine],
      ));
    }
    statements.add('return m;');
    return _u.createMethod(
      returnType: 'Map<String, Object?>',
      methodName: '_draftSnapshot',
      arguments: [],
      namedArguments: false,
      statements: statements,
    );
  }

  String _restoreEntry(_DraftField e) {
    final branches = e.overrideEncode == null
        ? _u.ifStatement(
            condition: '_form.values?.${e.name} == null',
            ifBlockStatements: [e.stateAssign],
          )
        : _u.ifStatement(
            condition: '_form.values?.${e.name} != null',
            ifBlockStatements: [
              _u.constDecl('v', '${e.guard} ? ${e.value} : null'),
              _u.inlineIfStatement(
                condition: 'v != null',
                statement: '_${e.name}OverrideKey.currentState?.restore(v);',
              ),
            ],
            elseBlockStatements: [e.stateAssign],
          );
    return _u.block([_u.constDecl("raw", "draft['${e.name}']"), branches]);
  }

  String _restoreMethod(List<_DraftField> entries) => _u.createMethod(
        returnType: 'Future<void>',
        methodName: '_restoreDraft',
        async: true,
        arguments: [],
        namedArguments: false,
        statements: [
          _u.inlineIfStatement(condition: '!mounted', statement: 'return;'),
          _u.constDecl('store', '_form.draftStore!'),
          'Map<String, dynamic>? loaded;',
          _u.tryCatchFinally(
            tryStatements: [
              _u.constDecl('stored', 'await store.read(_draftKey)'),
              _u.ifStatement(
                condition: 'stored != null',
                ifBlockStatements: [
                  _u.constDecl('decoded', 'jsonDecode(stored)'),
                  _u.ifStatement(
                    condition:
                        "decoded is Map<String, dynamic> && decoded['v'] == _draftSchemaHash && decoded['f'] is Map<String, dynamic>",
                    ifBlockStatements: ["loaded = decoded['f'] as Map<String, dynamic>;"],
                    elseBlockStatements: ['await store.delete(_draftKey);'],
                  ),
                ],
              ),
            ],
            catchVariable: '_',
            catchStatements: ['loaded = null;'],
          ),
          _u.inlineIfStatement(condition: '!mounted', statement: 'return;'),
          _u.constDecl('draft', 'loaded'),
          _u.ifStatement(
            condition: 'draft == null',
            ifBlockStatements: [
              '_isResetting = true;',
              _u.tryCatchFinally(
                tryStatements: ['setState(() => _restoring = false);'],
                finallyStatements: ['_isResetting = false;'],
              ),
              'return;',
            ],
          ),
          'setState(() ${_u.block(['_restoring = false;', ...entries.map(_restoreEntry)])});',
        ],
      );

  String _scheduleSaveMethod() => _u.createMethod(
        returnType: 'void',
        methodName: '_scheduleDraftSave',
        arguments: [],
        namedArguments: false,
        statements: [
          _u.inlineIfStatement(condition: '_form.draftStore == null || _restoring', statement: 'return;'),
          "_pendingDraft = jsonEncode({'v': _draftSchemaHash, 'f': _draftSnapshot()});",
          '_draftTimer?.cancel();',
          '_draftTimer = Timer(_form.debounceDuration, _flushDraft);',
        ],
      );

  String _flushMethod() => _u.createMethod(
        returnType: 'void',
        methodName: '_flushDraft',
        arguments: [],
        namedArguments: false,
        statements: [
          _u.constDecl('pending', '_pendingDraft'),
          _u.inlineIfStatement(condition: 'pending == null', statement: 'return;'),
          '_pendingDraft = null;',
          _u.tryCatchFinally(
            tryStatements: ['_form.draftStore!.write(_draftKey, pending).catchError((_) {});'],
            catchVariable: '_',
            catchStatements: [],
          ),
        ],
      );

  String _clearMethod() => _u.createMethod(
        returnType: 'void',
        methodName: '_clearDraft',
        arguments: [],
        namedArguments: false,
        statements: [
          '_draftTimer?.cancel();',
          '_pendingDraft = null;',
          _u.tryCatchFinally(
            tryStatements: ['_form.draftStore?.delete(_draftKey).catchError((_) {});'],
            catchVariable: '_',
            catchStatements: [],
          ),
        ],
      );
}
