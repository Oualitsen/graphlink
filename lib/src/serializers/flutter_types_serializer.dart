import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
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
  late final FlutterTypesValueRenderer _renderer;
  late final FlutterTypesCompanionSerializer _companions;
  late final FlutterTypesLayoutSerializer _layout;

  FlutterTypesSerializer(this._parser, DartSerializer dartSerializer, this._config, this.importPrefix) {
    _u = DartCodeGenUtils();
    _renderer = FlutterTypesValueRenderer(_parser, dartSerializer, _config, _u);
    _companions = FlutterTypesCompanionSerializer(_u);
    _layout = FlutterTypesLayoutSerializer(_parser, _config, _u, _renderer);
  }

  bool shouldSkip(GLTypeDefinition def) =>
      flutterInternalTypes.contains(def.token) || _config.typesToSkip.contains(def.token);

  bool shouldSkipEnum(GLEnumDefinition def) => flutterInternalEnums.contains(def.token);

  String getWidgetFileNameFor(GLTypeDefinition def) =>
      '${def.token.toSnakeCase()}_widget.dart';

  String getEnumLabelsFileNameFor(GLEnumDefinition def) =>
      '${def.token.toSnakeCase()}_labels.dart';

  // ── Enum labels file ───────────────────────────────────────────────────────

  String serializeEnumLabels(GLEnumDefinition def) {
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
          arguments: ['this.unselected', ...values.map((v) => 'this.${v.token}')],
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

    buffer.writeln(_companions.serializeLabelsClass(typeName, fields));
    buffer.writeln();
    buffer.writeln(_companions.serializeValuesClass(typeName, fields));
    buffer.writeln();
    buffer.writeln(_companions.serializeVisibilityClass(typeName, fields));
    buffer.writeln();
    buffer.writeln(_companions.serializeShowOnlyClass(typeName, fields));
    buffer.writeln();
    if (enumFields.isNotEmpty) {
      buffer.writeln(_companions.serializeEnumLabelsClass(typeName, enumFields));
      buffer.writeln();
    }
    buffer.writeln(_companions.serializeOrderClass(typeName, fields));
    buffer.writeln();
    buffer.writeln('enum ${typeName}Layout { labeledRow, listTile, listTileReversed, expandable }');
    buffer.writeln();
    buffer.write(_serializeWidgetClass(typeName, varName, fields, enumFields));

    return buffer.toString();
  }

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
