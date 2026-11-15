import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/dart/dart_serializer.dart';
import 'package:graphlink/src/serializers/dart/flutter_inputs/flutter_inputs_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
  input EventInput { title: String! startsAt: Int }
  type Query { noop: String }
''';

void main() {
  test('time pickers follow the 24/12-hour letters of the date pattern', () {
    final g = GLParser(mode: CodeGenerationMode.client)..parse(_schema);
    final out = FlutterInputsSerializer(
      g,
      DartSerializer(g, importPrefix: ''),
      const FlutterConfig(generateInputs: true),
      '',
    ).serializeInputForm(g.inputs['EventInput']!);

    expect(out, contains('bool? _patternIs24Hour(String pattern)'));
    expect(out, contains('alwaysUse24HourFormat: _patternIs24Hour(pattern) ?? MediaQuery.alwaysUse24HourFormatOf(ctx)'));
    expect(out, contains('use24hFormat: _patternIs24Hour('));
    expect(out, contains('await _pickTime('));
    expect('showTimePicker('.allMatches(out), hasLength(1));
  });
}
