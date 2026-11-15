import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/dart/dart_serializer.dart';
import 'package:graphlink/src/serializers/dart/flutter_inputs/flutter_inputs_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
  input PriceInput { label: String! amount: Float! quantity: Int }
  input LabelOnlyInput { label: String! }
  type Query { noop: String }
''';

FlutterInputsSerializer _serializer(GLParser g, [FlutterConfig config = const FlutterConfig(generateInputs: true)]) =>
    FlutterInputsSerializer(g, DartSerializer(g, importPrefix: ''), config, '');

GLParser _parse() => GLParser(mode: CodeGenerationMode.client)..parse(_schema);

void main() {
  test('number fields parse, format and filter through their NumberInputConfig', () {
    final g = _parse();
    final out = _serializer(g).serializeInputForm(g.inputs['PriceInput']!);
    expect(out, contains('final PriceInputNumberConfig? numberConfig;'));
    expect(out, contains('NumberInputConfig get _amountNumber'));
    expect(out, contains('_amountNumber.parseDouble('));
    expect(out, contains('_quantityNumber.parseInt('));
    expect(out, contains('NumberInputFormatter('));
    expect(out, contains('_flashAmountHint('));
    expect(out, isNot(contains('double.tryParse')));
    expect(out, isNot(contains('double.parse')));
    expect(out, isNot(contains('int.tryParse')));
  });

  test('a form without int or double fields has no number plumbing', () {
    final g = _parse();
    final out = _serializer(g).serializeInputForm(g.inputs['LabelOnlyInput']!);
    expect(out, isNot(contains('NumberConfig')));
    expect(out, isNot(contains('number_input_config.dart')));
    expect(out, isNot(contains('Hint')));
  });

  test('the shared runtime takes its default separator from the config', () {
    final g = _parse();
    final defaults = _serializer(g).serializeSharedNumberInputConfig();
    expect(defaults, contains('decimalSeparator = DecimalSeparator.either'));

    final comma = _serializer(g, const FlutterConfig(generateInputs: true, defaultDecimalSeparator: DecimalSeparator.comma))
        .serializeSharedNumberInputConfig();
    expect(comma, contains('decimalSeparator = DecimalSeparator.comma'));
  });

  test('form strings carry the number feedback messages', () {
    final g = _parse();
    final strings = _serializer(g).serializeSharedFormStrings();
    for (final name in ['numberCharNotAllowed', 'numberOneSeparator', 'numberTooManyDecimals', 'numberNoNegative']) {
      expect(strings, contains(name));
    }
  });
}
