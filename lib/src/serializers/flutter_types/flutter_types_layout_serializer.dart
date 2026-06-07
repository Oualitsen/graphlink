import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'flutter_types_constants.dart';
import 'flutter_types_value_renderer.dart';

class FlutterTypesLayoutSerializer {
  final GLParser _parser;
  final FlutterConfig _config;
  final DartCodeGenUtils _u;
  final FlutterTypesValueRenderer _renderer;

  FlutterTypesLayoutSerializer(this._parser, this._config, this._u, this._renderer);

  // ── Table / DataTable rows ─────────────────────────────────────────────────

  String serializeToTableRowMethod(String typeName, String varName, List<GLField> fields) {
    return _u.createMethod(
      returnType: 'TableRow',
      methodName: 'toTableRow',
      namedArguments: false,
      arguments: [],
      statements: [
        'final vis = showOnly?.toVisibility() ?? visibility ?? const ${typeName}Visibility();',
        'final ord = order ?? const ${typeName}Order();',
        'final entries = <MapEntry<int, Widget>>[];',
        ...fields.asMap().entries.map((e) {
          final defaultVal = _renderer.defaultValueExpression(e.value, varName);
          return _u.ifStatement(
            condition: 'vis.${e.value.name}',
            ifBlockStatements: [
              'entries.add(MapEntry(ord.${e.value.name} ?? ${1000 + e.key}, values?.${e.value.name} ?? $defaultVal));',
            ],
          );
        }),
        'entries.sort((a, b) => a.key.compareTo(b.key));',
        'return TableRow(children: entries.map((e) => e.value).toList());',
      ],
    );
  }

  String serializeToTableHeaderRowMethod(String typeName, String varName, List<GLField> fields) {
    return _u.createMethod(
      returnType: 'TableRow',
      methodName: 'toTableHeaderRow',
      namedArguments: false,
      arguments: [],
      statements: [
        'final vis = showOnly?.toVisibility() ?? visibility ?? const ${typeName}Visibility();',
        'final ord = order ?? const ${typeName}Order();',
        'final entries = <MapEntry<int, Widget>>[];',
        ...fields.asMap().entries.map((e) {
          final label = _renderer.humanize(e.value.name.token);
          final labelWidget = _renderer.labelTextWidget(label, hasContext: false);
          return _u.ifStatement(
            condition: 'vis.${e.value.name}',
            ifBlockStatements: [
              "entries.add(MapEntry(ord.${e.value.name} ?? ${1000 + e.key}, labels?.${e.value.name} ?? $labelWidget));",
            ],
          );
        }),
        'entries.sort((a, b) => a.key.compareTo(b.key));',
        'return TableRow(children: entries.map((e) => e.value).toList());',
      ],
    );
  }

  String serializeToDataRowMethod(String typeName, String varName, List<GLField> fields) {
    return _u.createMethod(
      returnType: 'DataRow',
      methodName: 'toDataRow',
      namedArguments: false,
      arguments: [],
      statements: [
        'final vis = showOnly?.toVisibility() ?? visibility ?? const ${typeName}Visibility();',
        'final ord = order ?? const ${typeName}Order();',
        'final entries = <MapEntry<int, DataCell>>[];',
        ...fields.asMap().entries.map((e) {
          final defaultVal = _renderer.defaultValueExpression(e.value, varName);
          return _u.ifStatement(
            condition: 'vis.${e.value.name}',
            ifBlockStatements: [
              'entries.add(MapEntry(ord.${e.value.name} ?? ${1000 + e.key}, DataCell(values?.${e.value.name} ?? $defaultVal)));',
            ],
          );
        }),
        'entries.sort((a, b) => a.key.compareTo(b.key));',
        'return DataRow(cells: entries.map((e) => e.value).toList());',
      ],
    );
  }

  String serializeToDataColumnsMethod(String typeName, String varName, List<GLField> fields) {
    return _u.createMethod(
      returnType: 'List<DataColumn>',
      methodName: 'toDataColumns',
      namedArguments: false,
      arguments: [],
      statements: [
        'final vis = showOnly?.toVisibility() ?? visibility ?? const ${typeName}Visibility();',
        'final ord = order ?? const ${typeName}Order();',
        'final entries = <MapEntry<int, DataColumn>>[];',
        ...fields.asMap().entries.map((e) {
          final label = _renderer.humanize(e.value.name.token);
          final labelWidget = _renderer.labelTextWidget(label, hasContext: false);
          return _u.ifStatement(
            condition: 'vis.${e.value.name}',
            ifBlockStatements: [
              "entries.add(MapEntry(ord.${e.value.name} ?? ${1000 + e.key}, DataColumn(label: labels?.${e.value.name} ?? $labelWidget)));",
            ],
          );
        }),
        'entries.sort((a, b) => a.key.compareTo(b.key));',
        'return entries.map((e) => e.value).toList();',
      ],
    );
  }

  // ── Layout methods (generate Dart method bodies) ───────────────────────────

  String serializeLabeledTableRowsMethod(String typeName, String varName, List<GLField> fields) {
    return _u.createMethod(
      returnType: 'List<TableRow>',
      methodName: '_labeledTableRows',
      namedArguments: false,
      arguments: ['BuildContext context'],
      statements: [
        'final vis = showOnly?.toVisibility() ?? visibility ?? const ${typeName}Visibility();',
        'final ord = order ?? const ${typeName}Order();',
        'final entries = <MapEntry<int, TableRow>>[];',
        ...fields.asMap().entries.map((e) {
          final label = _renderer.humanize(e.value.name.token);
          final labelWidget = _renderer.labelTextWidget(label);
          final defaultVal = _renderer.defaultValueExpression(e.value, varName);
          final row = _u.callExpression('TableRow', [
            _u.listArg('children', [
              _u.callExpression('Padding', [
                'padding: EdgeInsets.only(right: gap, bottom: gap)',
                "child: _labelWithInfo(context, labels?.${e.value.name} ?? $labelWidget, labels?.${e.value.name}Info)",
              ]),
              _u.callExpression('Padding', [
                'padding: EdgeInsets.only(bottom: gap)',
                'child: values?.${e.value.name} ?? $defaultVal',
              ]),
            ]),
          ]);
          return _u.ifStatement(
            condition: 'vis.${e.value.name}',
            ifBlockStatements: ['entries.add(MapEntry(ord.${e.value.name} ?? ${1000 + e.key}, $row));'],
          );
        }),
        'entries.sort((a, b) => a.key.compareTo(b.key));',
        'return entries.map((e) => e.value).toList();',
      ],
    );
  }

  String serializeListTileItemsMethod(String typeName, String varName, List<GLField> fields) {
    return _u.createMethod(
      returnType: 'List<Widget>',
      methodName: '_listTileItems',
      namedArguments: false,
      arguments: ['BuildContext context'],
      statements: [
        'final vis = showOnly?.toVisibility() ?? visibility ?? const ${typeName}Visibility();',
        'final ord = order ?? const ${typeName}Order();',
        'final entries = <MapEntry<int, Widget>>[];',
        ...fields.asMap().entries.map((e) {
          final label = _renderer.humanize(e.value.name.token);
          final labelWidget = _renderer.labelTextWidget(label);
          final defaultVal = _renderer.defaultValueExpression(e.value, varName);
          final tile = _u.callExpression('ListTile', [
            "title: _labelWithInfo(context, labels?.${e.value.name} ?? $labelWidget, labels?.${e.value.name}Info)",
            'subtitle: values?.${e.value.name} ?? $defaultVal',
          ]);
          return _u.ifStatement(
            condition: 'vis.${e.value.name}',
            ifBlockStatements: ['entries.add(MapEntry(ord.${e.value.name} ?? ${1000 + e.key}, $tile));'],
          );
        }),
        'entries.sort((a, b) => a.key.compareTo(b.key));',
        'return entries.map((e) => e.value).toList();',
      ],
    );
  }

  String serializeListTileReversedItemsMethod(String typeName, String varName, List<GLField> fields) {
    return _u.createMethod(
      returnType: 'List<Widget>',
      methodName: '_listTileReversedItems',
      namedArguments: false,
      arguments: ['BuildContext context'],
      statements: [
        'final vis = showOnly?.toVisibility() ?? visibility ?? const ${typeName}Visibility();',
        'final ord = order ?? const ${typeName}Order();',
        'final entries = <MapEntry<int, Widget>>[];',
        ...fields.asMap().entries.map((e) {
          final label = _renderer.humanize(e.value.name.token);
          final labelWidget = _renderer.labelTextWidget(label, small: true);
          final defaultVal = _renderer.defaultValueExpression(e.value, varName);
          final tile = _u.callExpression('Column', [
            'crossAxisAlignment: CrossAxisAlignment.start',
            _u.listArg('children', [
              _u.callExpression('Semantics', [
                'sortKey: const OrdinalSortKey(1.0)',
                "child: _labelWithInfo(context, labels?.${e.value.name} ?? $labelWidget, labels?.${e.value.name}Info)",
              ]),
              _u.callExpression('Semantics', [
                'sortKey: const OrdinalSortKey(2.0)',
                'child: values?.${e.value.name} ?? $defaultVal',
              ]),
            ]),
          ]);
          return _u.ifStatement(
            condition: 'vis.${e.value.name}',
            ifBlockStatements: ['entries.add(MapEntry(ord.${e.value.name} ?? ${1000 + e.key}, $tile));'],
          );
        }),
        'entries.sort((a, b) => a.key.compareTo(b.key));',
        'return entries.map((e) => e.value).toList();',
      ],
    );
  }

  String serializeExpandableItemsMethod(String typeName, String varName, List<GLField> fields) {
    final scalarFields = <MapEntry<int, GLField>>[];
    final nestedSingle = <MapEntry<int, GLField>>[];
    final nestedList = <MapEntry<int, GLField>>[];

    for (final e in fields.asMap().entries) {
      final baseToken = e.value.type.firstType.token;
      if (e.value.type.isList && _parser.types.containsKey(baseToken) && !flutterInternalTypes.contains(baseToken)) {
        nestedList.add(MapEntry(e.key, e.value));
      } else if (!e.value.type.isList && _parser.types.containsKey(baseToken) && !flutterInternalTypes.contains(baseToken)) {
        nestedSingle.add(MapEntry(e.key, e.value));
      } else {
        scalarFields.add(MapEntry(e.key, e.value));
      }
    }

    final statements = <String>[
      'final vis = showOnly?.toVisibility() ?? visibility ?? const ${typeName}Visibility();',
      'final ord = order ?? const ${typeName}Order();',
      'final accordions = <MapEntry<int, Widget>>[];',
    ];

    if (scalarFields.isNotEmpty) {
      statements.addAll(_buildScalarGroup(typeName, varName, scalarFields));
    }

    for (final e in nestedSingle) {
      statements.addAll(_buildNestedSingleAccordion(varName, e));
    }

    for (final e in nestedList) {
      statements.addAll(_buildNestedListAccordion(varName, e));
    }

    statements.add('accordions.sort((a, b) => a.key.compareTo(b.key));');
    statements.add('return accordions.map((e) => e.value).toList();');

    return _u.createMethod(
      returnType: 'List<Widget>',
      methodName: '_expandableItems',
      namedArguments: false,
      arguments: ['BuildContext context'],
      statements: statements,
    );
  }

  List<String> _buildScalarGroup(
      String typeName, String varName, List<MapEntry<int, GLField>> scalarFields) {
    // labeledRow / expandable → two-column Table
    final tableStmts = <String>['final scalarRows = <MapEntry<int, TableRow>>[];'];
    for (final e in scalarFields) {
      final idx = e.key;
      final f = e.value;
      final label = _renderer.humanize(f.name.token);
      final labelWidget = _renderer.labelTextWidget(label);
      final defaultVal = _renderer.defaultValueExpression(f, varName);
      final row = _u.callExpression('TableRow', [
        _u.listArg('children', [
          _u.callExpression('Padding', [
            'padding: EdgeInsets.only(right: gap, bottom: gap)',
            "child: _labelWithInfo(context, labels?.${f.name} ?? $labelWidget, labels?.${f.name}Info)",
          ]),
          _u.callExpression('Padding', [
            'padding: EdgeInsets.only(bottom: gap)',
            'child: values?.${f.name} ?? $defaultVal',
          ]),
        ]),
      ]);
      tableStmts.add(_u.ifStatement(
        condition: 'vis.${f.name}',
        ifBlockStatements: ['scalarRows.add(MapEntry(ord.${f.name} ?? ${1000 + idx}, $row));'],
      ));
    }
    tableStmts.add('scalarRows.sort((a, b) => a.key.compareTo(b.key));');
    tableStmts.add('scalarContent = ${_u.callExpression('Table', [
      'columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()}',
      'children: scalarRows.map((e) => e.value).toList()',
    ])};');

    // listTile → Column of ListTile
    final tileStmts = <String>['final scalarTiles = <MapEntry<int, Widget>>[];'];
    for (final e in scalarFields) {
      final idx = e.key;
      final f = e.value;
      final label = _renderer.humanize(f.name.token);
      final labelWidget = _renderer.labelTextWidget(label);
      final defaultVal = _renderer.defaultValueExpression(f, varName);
      final tile = _u.callExpression('ListTile', [
        "title: _labelWithInfo(context, labels?.${f.name} ?? $labelWidget, labels?.${f.name}Info)",
        'subtitle: values?.${f.name} ?? $defaultVal',
      ]);
      tileStmts.add(_u.ifStatement(
        condition: 'vis.${f.name}',
        ifBlockStatements: ['scalarTiles.add(MapEntry(ord.${f.name} ?? ${1000 + idx}, $tile));'],
      ));
    }
    tileStmts.add('scalarTiles.sort((a, b) => a.key.compareTo(b.key));');
    tileStmts.add('scalarContent = ${_u.callExpression('Column', ['children: _spaced(scalarTiles.map((e) => e.value).toList())'])};');

    // listTileReversed → Column with value on top, label below
    final reversedStmts = <String>['final scalarReversed = <MapEntry<int, Widget>>[];'];
    for (final e in scalarFields) {
      final idx = e.key;
      final f = e.value;
      final label = _renderer.humanize(f.name.token);
      final labelWidget = _renderer.labelTextWidget(label);
      final defaultVal = _renderer.defaultValueExpression(f, varName);
      final tile = _u.callExpression('ListTile', [
        'title: values?.${f.name} ?? $defaultVal',
        "subtitle: _labelWithInfo(context, labels?.${f.name} ?? $labelWidget, labels?.${f.name}Info)",
      ]);
      reversedStmts.add(_u.ifStatement(
        condition: 'vis.${f.name}',
        ifBlockStatements: ['scalarReversed.add(MapEntry(ord.${f.name} ?? ${1000 + idx}, $tile));'],
      ));
    }
    reversedStmts.add('scalarReversed.sort((a, b) => a.key.compareTo(b.key));');
    reversedStmts.add('scalarContent = ${_u.callExpression('Column', ['children: _spaced(scalarReversed.map((e) => e.value).toList())'])};');

    final switchStmt = _u.switchStatement(
      expression: 'groupLayout',
      cases: [
        DartCaseStatement(caseValue: '${typeName}Layout.listTile', statement: tileStmts.join(' ')),
        DartCaseStatement(caseValue: '${typeName}Layout.listTileReversed', statement: reversedStmts.join(' ')),
        DartCaseStatement(caseValue: 'default', statement: tableStmts.join(' ')),
      ],
    );

    final accordionTile = _u.callExpression('ExpansionTile', [
      r"title: _labelWithInfo(context, labels?.$group ?? const Text('Details'), labels?.$groupInfo)",
      _u.listArg('children', ['scalarContent']),
    ]);

    return [
      'Widget? scalarContent;',
      switchStmt,
      'accordions.add(MapEntry(ord.\$group ?? 0, $accordionTile));',
    ];
  }

  List<String> _buildNestedSingleAccordion(String varName, MapEntry<int, GLField> e) {
    final idx = e.key;
    final f = e.value;
    final label = _renderer.humanize(f.name.token);
    final labelWidget = _renderer.labelTextWidget(label);
    final childType = f.type.firstType.token;
    final condition = f.type.nullable
        ? 'vis.${f.name} && $varName.${f.name} != null'
        : 'vis.${f.name}';
    final childExpr = f.type.nullable
        ? '${childType}Widget($varName.${f.name}!, strings: strings)'
        : '${childType}Widget($varName.${f.name}, strings: strings)';
    final tile = _u.callExpression('ExpansionTile', [
      "title: _labelWithInfo(context, labels?.${f.name} ?? $labelWidget, labels?.${f.name}Info)",
      _u.listArg('children', ["values?.${f.name} ?? $childExpr"]),
    ]);
    return [
      _u.ifStatement(
        condition: condition,
        ifBlockStatements: ['accordions.add(MapEntry(ord.${f.name} ?? ${1000 + idx}, $tile));'],
      ),
    ];
  }

  List<String> _buildNestedListAccordion(String varName, MapEntry<int, GLField> e) {
    final idx = e.key;
    final f = e.value;
    final label = _renderer.humanize(f.name.token);
    final labelWidget = _renderer.labelTextWidget(label);
    final childType = f.type.firstType.token;
    final listAccess = f.type.nullable ? '$varName.${f.name}!' : '$varName.${f.name}';
    final mapSource = f.type.inlineType.nullable ? '$listAccess.whereType<$childType>()' : listAccess;
    final condition = f.type.nullable
        ? 'vis.${f.name} && ($varName.${f.name}?.isNotEmpty ?? false)'
        : 'vis.${f.name} && $varName.${f.name}.isNotEmpty';
    final tile = _u.callExpression('ExpansionTile', [
      "title: _labelWithInfo(context, labels?.${f.name} ?? $labelWidget, labels?.${f.name}Info)",
      'children: $mapSource.map((item) => ${childType}Widget(item, strings: strings)).toList()',
    ]);
    return [
      _u.ifStatement(
        condition: condition,
        ifBlockStatements: ['accordions.add(MapEntry(ord.${f.name} ?? ${1000 + idx}, $tile));'],
      ),
    ];
  }

  // ── Shared helper method bodies ────────────────────────────────────────────

  String serializeSpacedMethod() {
    return _u.createMethod(
      returnType: 'List<Widget>',
      methodName: '_spaced',
      namedArguments: false,
      arguments: ['List<Widget> items'],
      statements: [
        'final result = <Widget>[];',
        'for (var i = 0; i < items.length; i++) { if (i > 0) result.add(SizedBox(height: gap)); result.add(items[i]); }',
        'return result;',
      ],
    );
  }

  String serializeLabelWithInfoMethod() {
    return _u.createMethod(
      returnType: 'Widget',
      methodName: '_labelWithInfo',
      namedArguments: false,
      arguments: ['BuildContext context', 'Widget label', 'String? info'],
      statements: [
        'if (info == null) return label;',
        'return ${_u.callExpression('Row', [
          'mainAxisSize: MainAxisSize.min',
          _u.listArg('children', [
            'label',
            _u.callExpression('IconButton', [
              'icon: const Icon(Icons.info_outline, size: 16)',
              'padding: EdgeInsets.zero',
              'constraints: const BoxConstraints()',
              "onPressed: () => showDialog(context: context, builder: (_) => AlertDialog(content: Text(info), actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))]))",
            ]),
          ]),
        ])};',
      ],
    );
  }
}
