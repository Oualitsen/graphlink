import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/gl_ui_entity.dart' show GlTypeEntity;
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';

class FlutterTypesSerializer {
  final GLParser _parser;
  final DartSerializer _dartSerializer;
  final FlutterConfig _config;
  final _u = DartCodeGenUtils();

  FlutterTypesSerializer(this._parser, this._dartSerializer, this._config);

  static const _internalTypes = {
    'GraphLinkError',
    'GraphLinkErrorLocation',
    'GraphLinkPayload',
    'GraphLinkSubscriptionMessage',
    'GraphLinkSubscriptionPayload',
    'GraphLinkSubscriptionErrorMessage',
  };

  static const _internalEnums = {
    'GraphLinkAckStatus',
  };

  bool shouldSkip(GLTypeDefinition def) =>
      _internalTypes.contains(def.token) ||
      _config.typesToSkip.contains(def.token);

  bool shouldSkipEnum(GLEnumDefinition def) =>
      _internalEnums.contains(def.token);

  String getWidgetFileNameFor(GLTypeDefinition def) =>
      '${def.token.toSnakeCase()}_widget.dart';

  String getEnumLabelsFileNameFor(GLEnumDefinition def) =>
      '${def.token.toSnakeCase()}_labels.dart';

  // ── Enum labels ────────────────────────────────────────────────────────────

  String serializeEnumLabels(GLEnumDefinition def, String importPrefix) {
    final enumName = def.token;
    final values = def.values;
    final buffer = StringBuffer();

    buffer.writeln("import 'package:flutter/material.dart';");
    buffer.writeln("import '$importPrefix/enums/${enumName.toSnakeCase()}.dart';");
    buffer.writeln();
    buffer.write(_u.createClass(
      className: '${enumName}Labels',
      statements: [
        'final Widget? unselected;',
        ...values.map((v) => 'final Widget? ${v.token};'),
        _u.createMethod(
          isConst: true,
          methodName: '${enumName}Labels',
          namedArguments: true,
          arguments: [
            'this.unselected',
            ...values.map((v) => 'this.${v.token}'),
          ],
        ),
        _u.createMethod(
          returnType: 'Widget?',
          methodName: 'call',
          namedArguments: false,
          arguments: ['$enumName value'],
          statements: [
            _u.switchStatement(
              expression: 'value',
              cases: values
                  .map((v) => DartCaseStatement(
                        caseValue: '$enumName.${v.token}',
                        statement: 'return ${v.token};',
                      ))
                  .toList(),
            ),
          ],
        ),
      ],
    ));

    return buffer.toString();
  }

  // ── Type widget ────────────────────────────────────────────────────────────

  String serializeTypeWidget(GLTypeDefinition def, String importPrefix) {
    if (def is GLInterfaceDefinition) return '';
    if (def.isResponseType) return '';
    if (shouldSkip(def)) return '';

    final entity = GlTypeEntity(def, _parser);
    final typeName = entity.name;
    final varName = typeName.firstLow;
    final fields = entity.fields;
    final enumFields = fields
        .where((f) => _parser.enums.containsKey(f.type.firstType.token))
        .toList();
    final nestedTypeFields = fields
        .where((f) => !f.type.isList &&
            _parser.types.containsKey(f.type.firstType.token) &&
            !_internalTypes.contains(f.type.firstType.token))
        .toList();
    final nestedTypeListFields = fields
        .where((f) => f.type.isList &&
            _parser.types.containsKey(f.type.firstType.token) &&
            !_internalTypes.contains(f.type.firstType.token))
        .toList();

    final buffer = StringBuffer();

    final imports = <String>{
      "import 'package:flutter/material.dart';",
      "import 'package:flutter/semantics.dart';",
      "import '$importPrefix/types/${typeName.toSnakeCase()}.dart';",
      "import '$importPrefix/widgets/inputs/form_strings.dart';",
      ...entity.enumDataImports(importPrefix),
      ...entity.enumLabelImports(importPrefix),
      for (final f in [...nestedTypeFields, ...nestedTypeListFields]) ...{
        "import '$importPrefix/types/${f.type.firstType.token.toSnakeCase()}.dart';",
        "import '$importPrefix/widgets/types/${f.type.firstType.token.toSnakeCase()}_widget.dart';",
      },
    };
    for (final imp in imports) { buffer.writeln(imp); }
    buffer.writeln();

    buffer.writeln(_serializeLabelsClass(typeName, fields));
    buffer.writeln();
    buffer.writeln(_serializeValuesClass(typeName, fields));
    buffer.writeln();
    buffer.writeln(_serializeVisibilityClass(typeName, fields));
    buffer.writeln();
    if (enumFields.isNotEmpty) {
      buffer.writeln(_serializeEnumLabelsClass(typeName, enumFields));
      buffer.writeln();
    }
    buffer.writeln(_serializeOrderClass(typeName, fields));
    buffer.writeln();
    buffer.writeln('enum ${typeName}Layout { labeledRow, listTile, listTileReversed, expandable }');
    buffer.writeln();
    buffer.write(_serializeWidgetClass(typeName, varName, fields, enumFields));

    return buffer.toString();
  }

  // ── Companion classes ──────────────────────────────────────────────────────

  String _serializeLabelsClass(String typeName, List<GLField> fields) {
    return _u.createClass(
      className: '${typeName}Labels',
      statements: [
        ...fields.map((f) => 'final Widget? ${f.name};'),
        r'final Widget? $group;',
        _u.createMethod(
          isConst: true,
          methodName: '${typeName}Labels',
          namedArguments: true,
          arguments: [...fields.map((f) => 'this.${f.name}'), r'this.$group'],
        ),
      ],
    );
  }

  String _serializeValuesClass(String typeName, List<GLField> fields) {
    return _u.createClass(
      className: '${typeName}Values',
      statements: [
        ...fields.map((f) => 'final Widget? ${f.name};'),
        _u.createMethod(
          isConst: true,
          methodName: '${typeName}Values',
          namedArguments: true,
          arguments: fields.map((f) => 'this.${f.name}').toList(),
        ),
      ],
    );
  }

  String _serializeVisibilityClass(String typeName, List<GLField> fields) {
    return _u.createClass(
      className: '${typeName}Visibility',
      statements: [
        ...fields.map((f) => 'final bool ${f.name};'),
        _u.createMethod(
          isConst: true,
          methodName: '${typeName}Visibility',
          namedArguments: true,
          arguments: fields.map((f) => 'this.${f.name} = ${f.type.firstType.token == 'ID' ? 'false' : 'true'}').toList(),
        ),
      ],
    );
  }

  String _serializeOrderClass(String typeName, List<GLField> fields) {
    return _u.createClass(
      className: '${typeName}Order',
      statements: [
        ...fields.map((f) => 'final int? ${f.name};'),
        r'final int? $group;',
        _u.createMethod(
          isConst: true,
          methodName: '${typeName}Order',
          namedArguments: true,
          arguments: [...fields.map((f) => 'this.${f.name}'), r'this.$group'],
        ),
      ],
    );
  }

  String _serializeEnumLabelsClass(String typeName, List<GLField> enumFields) {
    return _u.createClass(
      className: '${typeName}EnumLabels',
      statements: [
        ...enumFields.map((f) => 'final ${f.type.firstType.token}Labels? ${f.name};'),
        _u.createMethod(
          isConst: true,
          methodName: '${typeName}EnumLabels',
          namedArguments: true,
          arguments: enumFields.map((f) => 'this.${f.name}').toList(),
        ),
      ],
    );
  }

  // ── Widget class ───────────────────────────────────────────────────────────

  String _serializeWidgetClass(
      String typeName, String varName, List<GLField> fields, List<GLField> enumFields) {
    final gap = _config.defaultGap % 1 == 0
        ? _config.defaultGap.toInt().toString()
        : _config.defaultGap.toString();
    final hasEnumFields = enumFields.isNotEmpty;

    final buildMethod = _u.createMethod(
      override: true,
      returnType: 'Widget',
      methodName: 'build',
      namedArguments: false,
      arguments: ['BuildContext context'],
      statements: [
        _u.switchStatement(
          expression: 'layout',
          cases: [
            DartCaseStatement(
              caseValue: '${typeName}Layout.labeledRow',
              statement: 'return ${_u.callExpression('Table', [
                'columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()}',
                'children: _labeledTableRows()',
              ])};',
            ),
            DartCaseStatement(
              caseValue: '${typeName}Layout.listTile',
              statement: 'return ${_u.callExpression('Column', ['children: _spaced(_listTileItems())'])};',
            ),
            DartCaseStatement(
              caseValue: '${typeName}Layout.listTileReversed',
              statement: 'return ${_u.callExpression('Column', ['children: _spaced(_listTileReversedItems())'])};',
            ),
            DartCaseStatement(
              caseValue: '${typeName}Layout.expandable',
              statement: 'return ${_u.callExpression('Column', ['children: _spaced(_expandableItems())'])};',
            ),
          ],
        ),
      ],
    );

    return _u.createClass(
      className: '${typeName}Widget',
      extendsClassName: 'StatelessWidget',
      statements: [
        'final $typeName $varName;',
        'final ${typeName}Labels? labels;',
        'final ${typeName}Values? values;',
        'final ${typeName}Visibility? visibility;',
        'final ${typeName}Order? order;',
        if (hasEnumFields) 'final ${typeName}EnumLabels? enumLabels;',
        'final ${typeName}Layout layout;',
        'final ${typeName}Layout groupLayout;',
        'final double gap;',
        'final FormStrings strings;',
        _u.createMethod(
          isConst: true,
          methodName: '${typeName}Widget',
          positionalArguments: ['this.$varName'],
          namedArguments: true,
          arguments: [
            'super.key',
            'this.labels',
            'this.values',
            'this.visibility',
            'this.order',
            if (hasEnumFields) 'this.enumLabels',
            'this.layout = ${typeName}Layout.labeledRow',
            'this.groupLayout = ${typeName}Layout.labeledRow',
            'this.gap = $gap',
            'this.strings = const FormStrings()',
          ],
        ),
        buildMethod,
        _serializeToTableRowMethod(typeName, varName, fields),
        _serializeToTableHeaderRowMethod(typeName, varName, fields),
        _serializeLabeledTableRowsMethod(typeName, varName, fields),
        _serializeListTileItemsMethod(typeName, varName, fields),
        _serializeListTileReversedItemsMethod(typeName, varName, fields),
        _serializeExpandableItemsMethod(typeName, varName, fields),
        _serializeSpacedMethod(),
      ],
    );
  }

  String _serializeToTableRowMethod(String typeName, String varName, List<GLField> fields) {
    return _u.createMethod(
      returnType: 'TableRow',
      methodName: 'toTableRow',
      namedArguments: false,
      arguments: [],
      statements: [
        'final vis = visibility ?? const ${typeName}Visibility();',
        'final ord = order ?? const ${typeName}Order();',
        'final entries = <MapEntry<int, Widget>>[];',
        ...fields.asMap().entries.map((e) {
          final defaultVal = _defaultValueExpression(e.value, varName);
          return _u.ifStatement(
            condition: 'vis.${e.value.name}',
            ifBlockStatements: ['entries.add(MapEntry(ord.${e.value.name} ?? ${1000 + e.key}, values?.${e.value.name} ?? $defaultVal));'],
          );
        }),
        'entries.sort((a, b) => a.key.compareTo(b.key));',
        'return TableRow(children: entries.map((e) => e.value).toList());',
      ],
    );
  }

  String _serializeToTableHeaderRowMethod(String typeName, String varName, List<GLField> fields) {
    return _u.createMethod(
      returnType: 'TableRow',
      methodName: 'toTableHeaderRow',
      namedArguments: false,
      arguments: [],
      statements: [
        'final vis = visibility ?? const ${typeName}Visibility();',
        'final ord = order ?? const ${typeName}Order();',
        'final entries = <MapEntry<int, Widget>>[];',
        ...fields.asMap().entries.map((e) {
          final label = _humanize(e.value.name.token);
          return _u.ifStatement(
            condition: 'vis.${e.value.name}',
            ifBlockStatements: ["entries.add(MapEntry(ord.${e.value.name} ?? ${1000 + e.key}, labels?.${e.value.name} ?? const Text('$label')));"],
          );
        }),
        'entries.sort((a, b) => a.key.compareTo(b.key));',
        'return TableRow(children: entries.map((e) => e.value).toList());',
      ],
    );
  }

  String _serializeLabeledTableRowsMethod(String typeName, String varName, List<GLField> fields) {
    return _u.createMethod(
      returnType: 'List<TableRow>',
      methodName: '_labeledTableRows',
      namedArguments: false,
      arguments: [],
      statements: [
        'final vis = visibility ?? const ${typeName}Visibility();',
        'final ord = order ?? const ${typeName}Order();',
        'final entries = <MapEntry<int, TableRow>>[];',
        ...fields.asMap().entries.map((e) {
          final label = _humanize(e.value.name.token);
          final defaultVal = _defaultValueExpression(e.value, varName);
          final row = _u.callExpression('TableRow', [
            _u.listArg('children', [
              _u.callExpression('Padding', [
                'padding: EdgeInsets.only(right: gap, bottom: gap)',
                "child: labels?.${e.value.name} ?? const Text('$label')",
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

  String _serializeListTileItemsMethod(String typeName, String varName, List<GLField> fields) {
    return _u.createMethod(
      returnType: 'List<Widget>',
      methodName: '_listTileItems',
      namedArguments: false,
      arguments: [],
      statements: [
        'final vis = visibility ?? const ${typeName}Visibility();',
        'final ord = order ?? const ${typeName}Order();',
        'final entries = <MapEntry<int, Widget>>[];',
        ...fields.asMap().entries.map((e) {
          final label = _humanize(e.value.name.token);
          final defaultVal = _defaultValueExpression(e.value, varName);
          final tile = _u.callExpression('ListTile', [
            "title: labels?.${e.value.name} ?? const Text('$label')",
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

  String _serializeListTileReversedItemsMethod(String typeName, String varName, List<GLField> fields) {
    return _u.createMethod(
      returnType: 'List<Widget>',
      methodName: '_listTileReversedItems',
      namedArguments: false,
      arguments: [],
      statements: [
        'final vis = visibility ?? const ${typeName}Visibility();',
        'final ord = order ?? const ${typeName}Order();',
        'final entries = <MapEntry<int, Widget>>[];',
        ...fields.asMap().entries.map((e) {
          final label = _humanize(e.value.name.token);
          final defaultVal = _defaultValueExpression(e.value, varName);
          // Visual: value on top, label below.
          // Semantic: label announced first via OrdinalSortKey.
          final tile = _u.callExpression('Column', [
            'crossAxisAlignment: CrossAxisAlignment.start',
            _u.listArg('children', [
              _u.callExpression('Semantics', [
                'sortKey: const OrdinalSortKey(1.0)',
                "child: labels?.${e.value.name} ?? const Text('$label', style: TextStyle(fontSize: 12))",
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

  String _serializeExpandableItemsMethod(String typeName, String varName, List<GLField> fields) {
    final scalarFields = <MapEntry<int, GLField>>[];
    final nestedSingle = <MapEntry<int, GLField>>[];
    final nestedList = <MapEntry<int, GLField>>[];

    for (final e in fields.asMap().entries) {
      final baseToken = e.value.type.firstType.token;
      if (e.value.type.isList && _parser.types.containsKey(baseToken) && !_internalTypes.contains(baseToken)) {
        nestedList.add(MapEntry(e.key, e.value));
      } else if (!e.value.type.isList && _parser.types.containsKey(baseToken) && !_internalTypes.contains(baseToken)) {
        nestedSingle.add(MapEntry(e.key, e.value));
      } else {
        scalarFields.add(MapEntry(e.key, e.value));
      }
    }

    final statements = <String>[
      'final vis = visibility ?? const ${typeName}Visibility();',
      'final ord = order ?? const ${typeName}Order();',
      'final accordions = <MapEntry<int, Widget>>[];',
    ];

    // Scalar group — style controlled by groupLayout, position by ord.$group
    if (scalarFields.isNotEmpty) {
      // labeledRow / expandable branch → two-column Table
      final tableStmts = <String>['final scalarRows = <MapEntry<int, TableRow>>[];'];
      for (final e in scalarFields) {
        final idx = e.key;
        final f = e.value;
        final label = _humanize(f.name.token);
        final defaultVal = _defaultValueExpression(f, varName);
        final row = _u.callExpression('TableRow', [
          _u.listArg('children', [
            _u.callExpression('Padding', [
              'padding: EdgeInsets.only(right: gap, bottom: gap)',
              "child: labels?.${f.name} ?? const Text('$label')",
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

      // listTile branch → Column of ListTile (label as title, value as subtitle)
      final tileStmts = <String>['final scalarTiles = <MapEntry<int, Widget>>[];'];
      for (final e in scalarFields) {
        final idx = e.key;
        final f = e.value;
        final label = _humanize(f.name.token);
        final defaultVal = _defaultValueExpression(f, varName);
        final tile = _u.callExpression('ListTile', [
          "title: labels?.${f.name} ?? const Text('$label')",
          'subtitle: values?.${f.name} ?? $defaultVal',
        ]);
        tileStmts.add(_u.ifStatement(
          condition: 'vis.${f.name}',
          ifBlockStatements: ['scalarTiles.add(MapEntry(ord.${f.name} ?? ${1000 + idx}, $tile));'],
        ));
      }
      tileStmts.add('scalarTiles.sort((a, b) => a.key.compareTo(b.key));');
      tileStmts.add('scalarContent = ${_u.callExpression('Column', ['children: _spaced(scalarTiles.map((e) => e.value).toList())'])};');

      // listTileReversed branch → Column of ListTile (value as title, label as subtitle)
      final reversedStmts = <String>['final scalarReversed = <MapEntry<int, Widget>>[];'];
      for (final e in scalarFields) {
        final idx = e.key;
        final f = e.value;
        final label = _humanize(f.name.token);
        final defaultVal = _defaultValueExpression(f, varName);
        final tile = _u.callExpression('ListTile', [
          'title: values?.${f.name} ?? $defaultVal',
          "subtitle: labels?.${f.name} ?? const Text('$label')",
        ]);
        reversedStmts.add(_u.ifStatement(
          condition: 'vis.${f.name}',
          ifBlockStatements: ['scalarReversed.add(MapEntry(ord.${f.name} ?? ${1000 + idx}, $tile));'],
        ));
      }
      reversedStmts.add('scalarReversed.sort((a, b) => a.key.compareTo(b.key));');
      reversedStmts.add('scalarContent = ${_u.callExpression('Column', ['children: _spaced(scalarReversed.map((e) => e.value).toList())'])};');

      statements.add('Widget? scalarContent;');
      statements.add(_u.switchStatement(
        expression: 'groupLayout',
        cases: [
          DartCaseStatement(
            caseValue: '${typeName}Layout.listTile',
            statement: tileStmts.join(' '),
          ),
          DartCaseStatement(
            caseValue: '${typeName}Layout.listTileReversed',
            statement: reversedStmts.join(' '),
          ),
          DartCaseStatement(
            caseValue: 'default',
            statement: tableStmts.join(' '),
          ),
        ],
      ));

      final accordionTile = _u.callExpression('ExpansionTile', [
        r"title: labels?.$group ?? const Text('Details')",
        _u.listArg('children', ['scalarContent!']),
      ]);
      statements.add(r'if (scalarContent != null) accordions.add(MapEntry(ord.$group ?? 0, ' + '$accordionTile));');
    }

    // Each single nested type → its own ExpansionTile
    for (final e in nestedSingle) {
      final idx = e.key;
      final f = e.value;
      final label = _humanize(f.name.token);
      final childType = f.type.firstType.token;
      final condition = f.type.nullable
          ? 'vis.${f.name} && $varName.${f.name} != null'
          : 'vis.${f.name}';
      final childExpr = f.type.nullable
          ? '${childType}Widget($varName.${f.name}!, strings: strings)'
          : '${childType}Widget($varName.${f.name}, strings: strings)';
      final tile = _u.callExpression('ExpansionTile', [
        "title: labels?.${f.name} ?? const Text('$label')",
        _u.listArg('children', ["values?.${f.name} ?? $childExpr"]),
      ]);
      statements.add(_u.ifStatement(
        condition: condition,
        ifBlockStatements: ['accordions.add(MapEntry(ord.${f.name} ?? ${1000 + idx}, $tile));'],
      ));
    }

    // Each list-of-nested-type → its own ExpansionTile with mapped child widgets
    for (final e in nestedList) {
      final idx = e.key;
      final f = e.value;
      final label = _humanize(f.name.token);
      final childType = f.type.firstType.token;
      final listAccess = f.type.nullable ? '$varName.${f.name}!' : '$varName.${f.name}';
      final condition = f.type.nullable
          ? 'vis.${f.name} && ($varName.${f.name}?.isNotEmpty ?? false)'
          : 'vis.${f.name} && $varName.${f.name}.isNotEmpty';
      final tile = _u.callExpression('ExpansionTile', [
        "title: labels?.${f.name} ?? const Text('$label')",
        'children: $listAccess.map((item) => ${childType}Widget(item, strings: strings)).toList()',
      ]);
      statements.add(_u.ifStatement(
        condition: condition,
        ifBlockStatements: ['accordions.add(MapEntry(ord.${f.name} ?? ${1000 + idx}, $tile));'],
      ));
    }

    statements.add('accordions.sort((a, b) => a.key.compareTo(b.key));');
    statements.add('return accordions.map((e) => e.value).toList();');

    return _u.createMethod(
      returnType: 'List<Widget>',
      methodName: '_expandableItems',
      namedArguments: false,
      arguments: [],
      statements: statements,
    );
  }

  String _serializeSpacedMethod() {
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

  // ── Default value expression ───────────────────────────────────────────────

  String _defaultValueExpression(GLField field, String varName) {
    final accessor = '$varName.${field.name}';
    final type = field.type;
    final baseToken = type.firstType.token;
    final nullable = type.nullable;
    final dartType = _dartSerializer.typeMap[baseToken] ?? baseToken;

    // List
    if (type.isList) {
      // Nested type list — Column of child widgets if the widget is generated, else count chip
      if (_parser.types.containsKey(baseToken) && !_internalTypes.contains(baseToken)) {
        final typeDef = _parser.types[baseToken]!;
        final widgetGenerated = !typeDef.isResponseType && !_config.typesToSkip.contains(baseToken);
        final list = '$accessor${nullable ? '!' : ''}';
        final inner = widgetGenerated
            ? "Column(children: $list.map((e) => ${baseToken}Widget(e, strings: strings)).toList())"
            : "Chip(label: Text('\${$list.length} ${_humanize(baseToken)}'))";
        return nullable ? "($accessor == null ? const SizedBox.shrink() : $inner)" : inner;
      }
      // Enum list — chip per value; enumLabels controls the chip label, not the chip itself
      if (_parser.enums.containsKey(baseToken)) {
        final fieldName = field.name;
        final list = '$accessor${nullable ? '!' : ''}';
        final wrap = "Wrap(spacing: 4, runSpacing: 4, children: $list.map((e) => Chip(label: enumLabels?.$fieldName?.call(e) ?? Text(e.name))).toList())";
        return nullable ? "($accessor == null ? const SizedBox.shrink() : $wrap)" : wrap;
      }
      // Scalar list (String, Int, Float, Boolean, ID) — chip per value
      final wrap = "Wrap(spacing: 4, runSpacing: 4, children: $accessor${nullable ? '!' : ''}.map((e) => Chip(label: Text(e.toString()))).toList())";
      return nullable ? "($accessor == null ? const SizedBox.shrink() : $wrap)" : wrap;
    }

    // Boolean
    if (dartType == 'bool') {
      if (nullable) {
        return "($accessor == null ? const SizedBox.shrink() : Icon($accessor! ? Icons.check : Icons.close, semanticLabel: $accessor! ? strings.yes : strings.no))";
      }
      return "Icon($accessor ? Icons.check : Icons.close, semanticLabel: $accessor ? strings.yes : strings.no)";
    }

    // Enum
    if (_parser.enums.containsKey(baseToken)) {
      final fieldName = field.name;
      if (nullable) {
        return "($accessor == null ? const SizedBox.shrink() : enumLabels?.$fieldName?.call($accessor!) ?? Text($accessor!.name))";
      }
      return "enumLabels?.$fieldName?.call($accessor) ?? Text($accessor.name)";
    }

    // Nested type — auto-embed child widget
    if (_parser.types.containsKey(baseToken) && !_internalTypes.contains(baseToken)) {
      if (nullable) {
        return "($accessor == null ? const SizedBox.shrink() : ${baseToken}Widget($accessor!, strings: strings))";
      }
      return "${baseToken}Widget($accessor, strings: strings)";
    }

    // String and ID
    if (dartType == 'String') {
      return nullable ? "Text($accessor ?? '')" : 'Text($accessor)';
    }

    // Int, double
    return nullable ? "Text($accessor?.toString() ?? '')" : 'Text($accessor.toString())';
  }

  String _humanize(String camelCase) {
    final spaced = camelCase.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m[1]} ${m[2]}',
    );
    return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
  }
}
