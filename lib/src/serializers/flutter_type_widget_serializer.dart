import 'package:retrofit_graphql/src/code_gen_utils.dart';
import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_enum_definition.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/serializers/dart_serializer.dart';
import 'package:retrofit_graphql/src/ui/flutter/gq_type_view.dart';

class FlutterTypeWidgetSerializer {
  final GQGrammar grammar;
  final DartSerializer serializer;
  final bool useApplocalisation;
  final codeGenUtils = DartCodeGenUtils();

  FlutterTypeWidgetSerializer(
      this.grammar, this.serializer, this.useApplocalisation);

  List<String> getDeclarations(GQTypeDefinition type) {
    var fields = type.getSerializableFields(grammar.mode);
    var result = <String>[
      'final ${type.token} value;',
      ...fields.map((e) => 'final int ${orderVar(e)};'),
      ...fields.map((e) => 'final bool ${visibleVar(e)};'),
      ...fields.map((e) => 'final String? ${labelVar(e)};'),
      ...fields.map((e) => 'final Widget? ${widgetVar(e)};'),
      ...fields.where((e) => grammar.isNonProjectableType(e.type.token)).map((e) =>
          'final String Function(${serializer.serializeType(e.type.firstType, false)})? ${transVar(e)};'),
      'final TextStyle? labelStyle;',
      'final TextStyle? valueStyle;',
      'final double spaceBetween;',
      'final int labelFlex;',
      'final int valueFlex;',
      'final bool verticalLayout;',
      'final GQFieldViewType viewType;',
      // generate list containers
      ...fields.where((f) => f.type.isList).map((e) =>
          'final Widget Function(List<Widget> children)? ${containerVar(e)};')
    ];

    return result;
  }

  String _widgetName(String typeName) {
    return '${typeName}Widget';
  }

  String serializeType(GQTypeView typeView, String importPrefix) {
    final type = typeView.type;
    var fields = type.getSerializableFields(grammar.mode);
    var buffer = StringBuffer();
    final widgetName = _widgetName(type.token);
    var imports = serializer.serializeImports(typeView, importPrefix);
    buffer.writeln(imports);

    fields
        .where((f) => grammar.isEnum(f.type.token))
        .map((f) => grammar.enums[f.type.token]!)
        .map(generateEnumValueFor)
        .forEach(buffer.writeln);

    buffer.write('class ${widgetName} extends StatelessWidget ');
    // field orders

    buffer.writeln(codeGenUtils.block([
      ...getDeclarations(type),
      serializeConstructor(widgetName, fields),
      serializeBuildMethod(fields),
      serializeGetLabel(type),
      serializeGetInBetweenWidget(),
      _serializeCreateLabelWidget(),
      _serializeWrapWiget(),
    ]));

    return buffer.toString();
  }

  String _serializeCreateLabelWidget() {
    return '''
Widget _createLabelWidget(String name, BuildContext context) {
    String value = _getLabel(name, context);
    if (viewType == GQFieldViewType.labelValueRow) {
      return Text(value, style: labelStyle ?? TextStyle(fontWeight: FontWeight.bold));
    } else {
      return Text(value, style: labelStyle);
    }
  }
''';
  }

  String _serializeWrapWiget() {
    return '''
Widget _wrapWidget(Widget label, Widget value) {
    switch (viewType) {
      case GQFieldViewType.listTile:
        return ListTile(title: (label), subtitle: (value));
      case GQFieldViewType.reversedListTile:
        return ListTile(title: (label), subtitle: (value));
      case GQFieldViewType.labelValueRow:
        return Row(
          children: [
            Expanded(flex: labelFlex, child: label),
            Expanded(flex: valueFlex, child: value),
          ],
        );
    }
  }
''';
  }

  String serializeConstructor(String widgetName, List<GQField> fields) {
    var m = codeGenUtils.createMethod(
        methodName: widgetName,
        returnType: 'const',
        arguments: [
          'super.key,',
          'required this.value,',
          // orders
          for (var i = 0, field = fields[i]; i < fields.length; i++)
            'this.${orderVar(field)} = ${i},',
          // visibility
          for (var i = 0, field = fields[i]; i < fields.length; i++)
            'this.${visibleVar(field)} = true,',
          // field labels
          for (var field in fields) 'this.${labelVar(field)},',
          // replacement widgets
          for (var field in fields) 'this.${widgetVar(field)},',
          // transformers
          ...fields
              .where((f) => grammar.isNonProjectableType(f.type.token))
              .map((field) => 'this.${transVar(field)},'),
          // viewType
          'this.viewType = GQFieldViewType.labelValueRow,',
          'this.labelFlex = 1,',
          'this.valueFlex = 1,',
          'this.spaceBetween = 10.0,',
          // styles
          'this.labelStyle,',
          'this.valueStyle,',
          'this.verticalLayout = true,',
          ...fields
              .where((f) => f.type.isList)
              .map((e) => 'this.${containerVar(e)},')
        ]);
    return "${m};";
  }

  String serializeBuildMethod(List<GQField> fields) {
    var methodStatements = <String>[
      'final ${widgetsVar} = <MapEntry<Widget, int>>[];',
      ...fields.map((field) {
        return codeGenUtils
            .ifStatement(condition: visibleVar(field), ifBlockStatements: [
          codeGenUtils.ifStatement(
              condition: '${widgetVar(field)} != null',
              ifBlockStatements: [
                '${widgetsVar}.add(MapEntry(${widgetVar(field)}!, ${orderVar(field)}));'
              ],
              elseBlockStatements: [
                'final valueWidget = ${_generateValueWidget(field, null)};',
                'final labelWidget = _wrapWidget(_createLabelWidget("${field.name.token}", context), valueWidget);',
                '${widgetsVar}.add(MapEntry(labelWidget, ${orderVar(field)}));'
              ])
        ]);
      })
    ];

    methodStatements.add("${widgetsVar}.sort((a, b) => (a.value - b.value));");
    methodStatements.add("final \$\$inbetweenWidget = _getInBetweenWidget();");
    methodStatements.add(
        "final ${childrenVar} = ${widgetsVar}.expand((e) => e == ${widgetsVar}.last ? [e.key]: [e.key, if (\$\$inbetweenWidget != null) \$\$inbetweenWidget]).toList();");

    methodStatements.add(codeGenUtils.ifStatement(
        condition: 'verticalLayout',
        ifBlockStatements: ["return Column(children: ${childrenVar});"],
        elseBlockStatements: ["return Row(children: ${childrenVar});"]));

    final buffer = StringBuffer();
    buffer.writeln("@override");

    var m = codeGenUtils.method(
        returnType: 'Widget',
        methodName: 'build',
        arguments: ['BuildContext context'],
        statements: methodStatements);
    buffer.writeln(m);
    return buffer.toString();
  }

  String _generateValueWidget(GQField field, GQField? original) {
    var buffer = StringBuffer();
    var type = field.type.token;

    var targetField = original ?? field;
    String valueName;
    if (original == null) {
      valueName = "value.${field.name}";
    } else {
      valueName = field.name.token;
    }
    String dot = targetField.type.nullable ?  "!.": ".";

    if (field.type.isList) {
      // handle list of values
      var newField = GQField(
          name: "e".toToken(),
          type: field.type.inlineType,
          arguments: field.arguments,
          directives: field.getDirectives());
      final mapToList =
          "map((e) => ${_generateValueWidget(newField, field)}).toList())";
      var ternaryOp = codeGenUtils.ternaryOp(
          condition: "${containerVar(field)} != null",
          positiveStatement:
              "${containerVar(field)}!(${valueName}${dot}${mapToList}",
          negativeStatement: "Column(children: ${valueName}${dot}${mapToList}");
          var nullValueCheck = codeGenUtils.ternaryOp(condition: '${valueName} != null', positiveStatement: "(${ternaryOp})", negativeStatement: 'SizedBox.shrink()');
      buffer.write(nullValueCheck);

      return buffer.toString();
    }
    var serialType = serializer.serializeType(field.type, false);
    if (grammar.isProjectableType(type)) {
      if (field.type.nullable) {
        buffer.write(
            "${valueName} == null ? Text('N/A') : ${_widgetName(type)}(value: ${valueName}!)");
      } else {
        buffer.write("${_widgetName(type)}(value: ${valueName})");
      }

      return buffer.toString();
    } else {
      buffer.write('Text(${transVar(targetField)}?.call(${valueName}) ?? ');
      if (grammar.isEnum(type)) {
        buffer.write('_getGenderValue(context, ${valueName})');
      } else {
        
        switch (serialType) {
          case 'String':
          case 'String?':
            buffer.write(valueName);
            break;
          case 'int':
          case 'double':
          case 'num':
          case 'bool':
          default:
            buffer.write("'\${${valueName}}'");
        }
      }
    }

    if (field.type.firstType.nullable && serialType == "String?") {
      buffer.write(' ?? ""');
    }
    buffer.write(")");
    return buffer.toString();
  }

  String generateEnumValueFor(GQEnumDefinition def) {
    return codeGenUtils.method(
        returnType: "String",
        methodName: "_get${def.token}Value",
        arguments: [
          'BuildContext context',
          '${def.token}? value'
        ],
        statements: [
          if (useApplocalisation) ...[
            'final lang = AppLocalizations.of(context)!;',
            codeGenUtils.switchStatement(
                expression: 'value',
                cases: [
                  ...def.values.map(
                    (val) => DartCaseStatement(
                        caseValue: "${def.token}.${val.value.token}",
                        statement:
                            'return lang.${def.token.firstLow}${val.value.token.firstUp};'),
                  ),
                ],
                defaultStatement: 'return lang.${def.token.firstLow}Null;')
          ] else
            'return value.toJson();'
        ]);
  }

  String serializeGetInBetweenWidget() {
    return codeGenUtils.method(
        returnType: "Widget?",
        methodName: "_getInBetweenWidget",
        statements: [
          codeGenUtils.ifStatement(
              condition: "spaceBetween <= 0",
              ifBlockStatements: ["return null;"]),
          codeGenUtils.ifStatement(
              condition: "verticalLayout",
              ifBlockStatements: ["return SizedBox(height: spaceBetween);"]),
          "return SizedBox(width: spaceBetween);"
        ]);
  }

  String containerVar(GQField field) {
    return "${field.name}Conatiner";
  }

  String visibleVar(GQField field) {
    return "${field.name}Visible";
  }

  String labelVar(GQField field) {
    return "${field.name}Label";
  }

  String widgetVar(GQField field) {
    return "${field.name}Widget";
  }

  String orderVar(GQField field) {
    return "${field.name}Order";
  }

  String transVar(GQField field) {
    return "${field.name}Transformer";
  }

  String get widgetsVar => "\$\$widgets";
  String get childrenVar => "\$\$children";

  String serializeGetLabel(GQTypeDefinition type) {
    var fields = type.getSerializableFields(grammar.mode);
    var methodStatements = <String>["String result;"];
    if (useApplocalisation) {
      methodStatements.add('final lang = AppLocalizations.of(context)!;');
    }

    var cases = fields.map((field) {
      var b = StringBuffer('result = ${labelVar(field)} ?? ');
      if (useApplocalisation) {
        b.write("lang.${type.token.firstLow}${field.name.token.firstUp};");
      } else {
        b.write('fieldName;');
      }
      return DartCaseStatement(
          caseValue: '"${field.name.token}"', statement: b.toString());
    }).toList();
    methodStatements.add(codeGenUtils.switchStatement(
        expression: 'fieldName',
        cases: cases,
        defaultStatement: 'result = fieldName;'));
    methodStatements.add('return result;');
    return codeGenUtils.method(
        returnType: "String",
        methodName: "_getLabel",
        arguments: ["String fieldName", "BuildContext context"],
        statements: methodStatements);
  }
}
