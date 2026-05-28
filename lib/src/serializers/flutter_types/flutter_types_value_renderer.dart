import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'flutter_types_constants.dart';

class FlutterTypesValueRenderer {
  final GLParser _parser;
  final DartSerializer _dartSerializer;
  final FlutterConfig _config;
  final DartCodeGenUtils _u;

  FlutterTypesValueRenderer(this._parser, this._dartSerializer, this._config, this._u);

  String defaultValueExpression(GLField field, String varName) {
    final accessor = '$varName.${field.name}';
    final type = field.type;
    final baseToken = type.firstType.token;
    final nullable = type.nullable;
    final dartType = _dartSerializer.typeMap[baseToken] ?? baseToken;

    if (type.isList) {
      if (_parser.types.containsKey(baseToken) && !flutterInternalTypes.contains(baseToken)) {
        final typeDef = _parser.types[baseToken]!;
        final widgetGenerated = !typeDef.isResponseType && !_config.typesToSkip.contains(baseToken);
        final list = '$accessor${nullable ? '!' : ''}';
        final inner = widgetGenerated
            ? "Column(children: $list.map((e) => ${baseToken}Widget(e, strings: strings)).toList())"
            : "Chip(label: Text('\${$list.length} ${humanize(baseToken)}'))";
        return nullable ? "($accessor == null ? const SizedBox.shrink() : $inner)" : inner;
      }
      if (_parser.enums.containsKey(baseToken)) {
        final fieldName = field.name;
        final list = '$accessor${nullable ? '!' : ''}';
        final wrap = "Wrap(spacing: 4, runSpacing: 4, children: $list.map((e) => Chip(label: enumLabels?.$fieldName?.call(e) ?? Text(e.name))).toList())";
        return nullable ? "($accessor == null ? const SizedBox.shrink() : $wrap)" : wrap;
      }
      final wrap = "Wrap(spacing: 4, runSpacing: 4, children: $accessor${nullable ? '!' : ''}.map((e) => Chip(label: Text(e.toString()))).toList())";
      return nullable ? "($accessor == null ? const SizedBox.shrink() : $wrap)" : wrap;
    }

    if (dartType == 'bool') {
      if (nullable) {
        return "($accessor == null ? const SizedBox.shrink() : Icon($accessor! ? Icons.check : Icons.close, semanticLabel: $accessor! ? strings.yes : strings.no))";
      }
      return "Icon($accessor ? Icons.check : Icons.close, semanticLabel: $accessor ? strings.yes : strings.no)";
    }

    if (_parser.enums.containsKey(baseToken)) {
      final fieldName = field.name;
      if (nullable) {
        return "($accessor == null ? const SizedBox.shrink() : enumLabels?.$fieldName?.call($accessor!) ?? Text($accessor!.name))";
      }
      return "enumLabels?.$fieldName?.call($accessor) ?? Text($accessor.name)";
    }

    if (_parser.types.containsKey(baseToken) && !flutterInternalTypes.contains(baseToken)) {
      if (nullable) {
        return "($accessor == null ? const SizedBox.shrink() : ${baseToken}Widget($accessor!, strings: strings))";
      }
      return "${baseToken}Widget($accessor, strings: strings)";
    }

    if (dartType == 'String') {
      return nullable ? "Text($accessor ?? '')" : 'Text($accessor)';
    }

    return nullable ? "Text($accessor?.toString() ?? '')" : 'Text($accessor.toString())';
  }

  String labelTextWidget(String label, {bool hasContext = true, bool small = false}) {
    final fontSize = small ? ', fontSize: 12' : '';
    switch (_config.labelStyle) {
      case FlutterLabelStyle.bold:
        return "const Text('$label', style: TextStyle(fontWeight: FontWeight.bold$fontSize))";
      case FlutterLabelStyle.muted:
        if (!hasContext) return "const Text('$label'${ small ? ", style: const TextStyle(fontSize: 12)" : ''})";
        return "Text('$label', style: TextStyle(color: Theme.of(context).colorScheme.outline$fontSize))";
    }
  }

  String humanize(String camelCase) {
    final spaced = camelCase.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m[1]} ${m[2]}',
    );
    return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
  }
}
