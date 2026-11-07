import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
scalar Long
input I {
  big: Long = 9007199254740993
  small: Long = 5
  negative: Long = -4294967296
  plain: Int = 3
  many: [Long!] = [1, 4294967296]
}
''';

void main() {
  late GLParser g;
  late JavaSerializer s;

  setUp(() {
    g = GLParser()..parse(_schema);
    s = JavaSerializer(g, importPrefix: '');
  });

  String literal(String field) {
    final f = g.inputs['I']!.fields.firstWhere((f) => f.name.token == field);
    return s.serializeDefaultLiteral(f.type, f.initialValue);
  }

  test('a Long literal beyond 32 bits carries the L suffix', () {
    expect(literal('big'), '9007199254740993L');
    expect(literal('negative'), '-4294967296L');
  });

  test('a small Long literal still needs the suffix, a boxed Long takes no int literal', () {
    expect(literal('small'), '5L');
  });

  test('an Int literal is untouched', () {
    expect(literal('plain'), '3');
  });

  test('list elements of Long are suffixed', () {
    expect(literal('many'), 'Arrays.asList(1L, 4294967296L)');
  });
}
