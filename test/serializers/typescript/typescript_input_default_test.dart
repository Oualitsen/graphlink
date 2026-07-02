import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';

TypeScriptSerializer _serializer(GLParser g) => TypeScriptSerializer(g, importPrefix: '');

/// Trims every line so indentation never breaks containsAllInOrder checks.
Iterable<String> lines(String s) => s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

const schema = '''
input PriceRangeFilter {
  max: Float
  min: Float = 0
}

type Query {
  products(filter: PriceRangeFilter): String
}
''';

void main() {
  group('typescript input default value serialization', () {
    late GLParser g;
    late String out;

    setUp(() {
      g = GLParser()..parse(schema);
      out = _serializer(g).doSerializeInputDefinition(g.inputs['PriceRangeFilter']!);
    });

    test('Int and Float both map to number — no type distinction, no literal-typing bug', () {
      expect(lines(out), containsAllInOrder(['max?: number | null;', 'min?: number | null;']));
    });

    test('min default 0 is a valid number literal in the defaults const', () {
      // TypeScript's `number` type covers both int and float, so `min: 0`
      // needs no decimal point — unlike Kotlin/Java's boxed Double, which
      // rejects a bare Int literal.
      expect(lines(out), containsAllInOrder([
        'export const defaultPriceRangeFilter: Partial<PriceRangeFilter> = {',
        'min: 0,',
        '};',
      ]));
    });
  });
}
