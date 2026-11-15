import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/dart/dart_serializer.dart';
import 'package:graphlink/src/serializers/dart/flutter_types_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
  enum DocType { OD PEC }
  type Query { noop: String }
''';

String _labels({required bool tolerant}) {
  final g = GLParser(mode: CodeGenerationMode.client, tolerantEnums: tolerant)..parse(_schema);
  final flutter = FlutterTypesSerializer(g, DartSerializer(g, importPrefix: ''), const FlutterConfig(), '');
  return flutter.serializeEnumLabels(g.enums['DocType']!);
}

void main() {
  test('labels switch covers unknownValue__ and returns null for it', () {
    final out = _labels(tolerant: true);
    expect(out, contains('case DocType.unknownValue__:'));
    expect(out, matches(RegExp(r'case DocType\.unknownValue__:\s*return null;')));
    expect(out, isNot(contains('final Widget? unknownValue__;')));
  });

  test('strict enums leave the labels switch unchanged', () {
    expect(_labels(tolerant: false), isNot(contains('unknownValue__')));
  });
}
