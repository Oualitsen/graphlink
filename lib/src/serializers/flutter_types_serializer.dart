import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/gl_ui_entity.dart' show GlTypeEntity;
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'flutter_types/flutter_types_companion_serializer.dart';
import 'flutter_types/flutter_types_constants.dart';
import 'flutter_types/flutter_types_layout_serializer.dart';
import 'flutter_types/flutter_types_value_renderer.dart';

class FlutterTypesSerializer {
  final GLParser _parser;
  final FlutterConfig _config;
  final String importPrefix;

  late final DartCodeGenUtils _u;
  late final DartSerializer _dartSerializer;
  late final FlutterTypesValueRenderer _renderer;
  late final FlutterTypesCompanionSerializer _companions;
  late final FlutterTypesLayoutSerializer _layout;

  FlutterTypesSerializer(this._parser, DartSerializer dartSerializer, this._config, this.importPrefix) {
    _u = DartCodeGenUtils();
    _dartSerializer = dartSerializer;
    _renderer = FlutterTypesValueRenderer(_parser, dartSerializer, _config);
    _companions = FlutterTypesCompanionSerializer(_u, _parser);
    _layout = FlutterTypesLayoutSerializer(_parser, _u, _renderer);
  }

  bool shouldSkip(GLTypeDefinition def) =>
      flutterInternalTypes.contains(def.token) || _config.typesToSkip.contains(def.token);

  bool shouldSkipEnum(GLEnumDefinition def) => flutterInternalEnums.contains(def.token);

  String getWidgetFileNameFor(GLTypeDefinition def) =>
      '${def.codeName.toSnakeCase()}_widget.dart';

  String getEnumLabelsFileNameFor(GLEnumDefinition def) =>
      '${def.codeName.toSnakeCase()}_labels.dart';

  // ── Enum labels file ───────────────────────────────────────────────────────

  String serializeEnumLabels(GLEnumDefinition def) {
    final enumName = def.codeName;
    final values = def.values;

    final body = _u.createClass(
      className: '${enumName}Labels',
      statements: [
        'final Widget? unselected;',
        ...values.map((v) => 'final Widget? ${v.codeName};'),
        _u.createMethod(
          isConst: true,
          methodName: '${enumName}Labels',
          namedArguments: true,
          arguments: ['this.unselected', ...values.map((v) => 'this.${v.codeName}')],
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
                        caseValue: '$enumName.${v.codeName}',
                        statement: 'return ${v.codeName};',
                      ))
                  .toList(),
            ),
          ],
        ),
      ],
    );

    return _dartSerializer.serializeGlClass(GLClassModel(
      imports: ['package:flutter/material.dart'],
      importDepencies: [def],
      body: body,
    ));
  }

  // ── Type widget file ───────────────────────────────────────────────────────

  String serializeTypeWidget(GLTypeDefinition def) {
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
        .where((f) =>
            !f.type.isList &&
            _parser.types.containsKey(f.type.firstType.token) &&
            !flutterInternalTypes.contains(f.type.firstType.token))
        .toList();
    final nestedTypeListFields = fields
        .where((f) =>
            f.type.isList &&
            _parser.types.containsKey(f.type.firstType.token) &&
            !flutterInternalTypes.contains(f.type.firstType.token))
        .toList();

    final header = _serializeAgentHeader(typeName, varName, fields, enumFields,
        nestedTypeFields, nestedTypeListFields);

    final enumTokens = <GLToken>{
      for (final f in fields)
        if (!f.type.isList && _parser.enums.containsKey(f.type.firstType.token))
          _parser.enums[f.type.firstType.token]!,
      for (final f in fields)
        if (f.type.isList && _parser.enums.containsKey(f.type.inlineType.firstType.token))
          _parser.enums[f.type.inlineType.firstType.token]!,
    };
    final nestedTypeTokens = <GLToken>{
      for (final f in [...nestedTypeFields, ...nestedTypeListFields])
        if (_parser.types[f.type.firstType.token] != null) _parser.types[f.type.firstType.token]!,
    };
    final importDeps = <GLToken>[def, ...enumTokens, ...nestedTypeTokens];

    final imports = <String>{
      'package:flutter/material.dart',
      'package:flutter/semantics.dart',
      '$importPrefix/widgets/inputs/form_strings.dart',
      for (final f in fields)
        if (!f.type.isList && _parser.enums.containsKey(f.type.firstType.token))
          '$importPrefix/widgets/enums/${_parser.enums[f.type.firstType.token]!.codeName.toSnakeCase()}_labels.dart',
      for (final f in fields)
        if (f.type.isList && _parser.enums.containsKey(f.type.inlineType.firstType.token))
          '$importPrefix/widgets/enums/${_parser.enums[f.type.inlineType.firstType.token]!.codeName.toSnakeCase()}_labels.dart',
      for (final f in [...nestedTypeFields, ...nestedTypeListFields])
        '$importPrefix/widgets/types/${(_parser.types[f.type.firstType.token]?.codeName ?? f.type.firstType.token).toSnakeCase()}_widget.dart',
    };

    final bodyBuffer = StringBuffer();
    bodyBuffer.writeln(_companions.serializeLabelsClass(typeName, fields));
    bodyBuffer.writeln();
    bodyBuffer.writeln(_companions.serializeValuesClass(typeName, fields));
    bodyBuffer.writeln();
    bodyBuffer.writeln(_companions.serializeVisibilityClass(typeName, fields));
    bodyBuffer.writeln();
    bodyBuffer.writeln(_companions.serializeShowOnlyClass(typeName, fields));
    bodyBuffer.writeln();
    if (enumFields.isNotEmpty) {
      bodyBuffer.writeln(_companions.serializeEnumLabelsClass(typeName, enumFields));
      bodyBuffer.writeln();
    }
    bodyBuffer.writeln(_companions.serializeOrderClass(typeName, fields));
    bodyBuffer.writeln();
    bodyBuffer.writeln('enum ${typeName}Layout { labeledRow, listTile, listTileReversed, expandable }');
    bodyBuffer.writeln();
    bodyBuffer.write(_serializeWidgetClass(typeName, varName, fields, enumFields));

    final file = _dartSerializer.serializeGlClass(GLClassModel(
      imports: imports.toList(),
      importDepencies: importDeps,
      body: bodyBuffer.toString(),
    ));

    return '$header$file';
  }

  // ── Agent header ──────────────────────────────────────────────────────────

  String _serializeAgentHeader(
    String typeName,
    String varName,
    List<GLField> fields,
    List<GLField> enumFields,
    List<GLField> nestedTypeFields,
    List<GLField> nestedTypeListFields,
  ) {
    final sep = '// ${'=' * 77}';
    final buf = StringBuffer();

    buf.writeln(sep);
    buf.writeln('// AGENT GUIDE — ${typeName}Widget');
    buf.writeln(sep);
    buf.writeln('// Stateless display widget. Renders a $typeName instance in a chosen layout.');
    buf.writeln('//');
    buf.writeln('// USAGE:');
    buf.writeln('//   ${typeName}Widget($varName)');
    buf.writeln('//   ${typeName}Widget($varName, layout: ${typeName}Layout.listTile, labels: ...)');
    buf.writeln('//');

    // ── Fields ────────────────────────────────────────────────────────────────
    buf.writeln('// FIELDS (schema order):');
    final pad = fields.map((f) => f.name.token.length).fold<int>(0, (a, b) => a > b ? a : b) + 2;
    for (final f in fields) {
      final name = f.name.token.padRight(pad);
      final baseToken = f.type.firstType.token;
      final q = f.type.nullable ? '?' : '';
      final String typeDesc;
      if (nestedTypeListFields.contains(f)) {
        typeDesc = 'List<$baseToken>  → ${baseToken}Widget per item';
      } else if (nestedTypeFields.contains(f)) {
        typeDesc = '$baseToken$q  → ${baseToken}Widget inline';
      } else if (f.type.isList && _parser.enums.containsKey(baseToken)) {
        typeDesc = 'List<$baseToken>  → Wrap of Chips  → EnumLabels for labels';
      } else if (f.type.isList) {
        final inner = _dartTypeFor(baseToken);
        typeDesc = 'List<$inner>  → Wrap of Chips';
      } else if (enumFields.contains(f)) {
        typeDesc = '$baseToken$q  → EnumLabels for custom label widgets';
      } else {
        final dartT = _dartTypeFor(baseToken);
        final suffix = dartT == 'bool' ? '  → Icon(check / close)' : '';
        typeDesc = '$dartT$q$suffix';
      }
      buf.writeln('//   $name$typeDesc');
    }

    // ── Layouts ───────────────────────────────────────────────────────────────
    buf.writeln('//');
    buf.writeln('// LAYOUTS:');
    buf.writeln('//   ${typeName}Layout.labeledRow        two-column Table (label | value)');
    buf.writeln('//   ${typeName}Layout.listTile          ListTile per field (label above, value below)');
    buf.writeln('//   ${typeName}Layout.listTileReversed  ListTile per field (value above, label below)');
    buf.writeln('//   ${typeName}Layout.expandable        ExpansionTile per nested type; scalars grouped');

    // ── Companion classes ─────────────────────────────────────────────────────
    buf.writeln('//');
    buf.writeln('// COMPANION CLASSES (all optional):');
    buf.writeln('//   ${typeName}Labels      per-field label widgets + \$group/\$groupInfo for expandable header');
    buf.writeln('//   ${typeName}Values      replace any field\'s display with a custom Widget');
    buf.writeln('//   ${typeName}Visibility  per-field bool (default: true; ID fields default: false)');
    buf.writeln('//   ${typeName}ShowOnly    show only the listed fields (use instead of Visibility)');
    buf.writeln('//   ${typeName}Order       render-order overrides (int? per field + \$group)');
    if (enumFields.isNotEmpty) {
      buf.writeln('//   ${typeName}EnumLabels  per-enum-field label widgets (uses \${Enum}Labels)');
    }

    // ── Table integration ─────────────────────────────────────────────────────
    buf.writeln('//');
    buf.writeln('// TABLE INTEGRATION (call on the widget instance):');
    buf.writeln('//   toTableRow()       → TableRow          (cells = visible field values)');
    buf.writeln('//   toTableHeaderRow() → TableRow          (cells = visible field labels)');
    buf.writeln('//   toDataRow()        → DataRow           (DataCell per visible field)');
    buf.writeln('//   toDataColumns()    → List<DataColumn>');
    buf.writeln(sep);
    buf.writeln();

    return buf.toString();
  }

  String _dartTypeFor(String graphqlToken) =>
      const {'String': 'String', 'Int': 'int', 'Float': 'double', 'Boolean': 'bool', 'ID': 'String'}[graphqlToken] ??
      graphqlToken;

  // ── Widget class ───────────────────────────────────────────────────────────

  String _serializeWidgetClass(
      String typeName, String varName, fields, List enumFields) {
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
                'children: _labeledTableRows(context)',
              ])};',
            ),
            DartCaseStatement(
              caseValue: '${typeName}Layout.listTile',
              statement: 'return ${_u.callExpression('Column', ['children: _spaced(_listTileItems(context))'])};',
            ),
            DartCaseStatement(
              caseValue: '${typeName}Layout.listTileReversed',
              statement: 'return ${_u.callExpression('Column', ['children: _spaced(_listTileReversedItems(context))'])};',
            ),
            DartCaseStatement(
              caseValue: '${typeName}Layout.expandable',
              statement: 'return ${_u.callExpression('Column', ['children: _spaced(_expandableItems(context))'])};',
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
        'final ${typeName}ShowOnly? showOnly;',
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
            'this.showOnly',
            'this.order',
            if (hasEnumFields) 'this.enumLabels',
            'this.layout = ${typeName}Layout.${_config.defaultTypeLayout.name}',
            'this.groupLayout = ${typeName}Layout.${_config.defaultGroupLayout.name}',
            'this.gap = $gap',
            'this.strings = const FormStrings()',
          ],
          initializers: [
            "assert(visibility == null || showOnly == null, '${typeName}Widget: use visibility or showOnly, not both')",
          ],
        ),
        buildMethod,
        _layout.serializeToTableRowMethod(typeName, varName, fields),
        _layout.serializeToTableHeaderRowMethod(typeName, varName, fields),
        _layout.serializeToDataRowMethod(typeName, varName, fields),
        _layout.serializeToDataColumnsMethod(typeName, varName, fields),
        _layout.serializeLabeledTableRowsMethod(typeName, varName, fields),
        _layout.serializeListTileItemsMethod(typeName, varName, fields),
        _layout.serializeListTileReversedItemsMethod(typeName, varName, fields),
        _layout.serializeExpandableItemsMethod(typeName, varName, fields),
        _layout.serializeSpacedMethod(),
        _layout.serializeLabelWithInfoMethod(),
      ],
    );
  }
}
