import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';

DartSerializer _serializer(GLParser g) => DartSerializer(g, importPrefix: '');

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
  group('dart input default value serialization', () {
    late GLParser g;
    late String out;

    setUp(() {
      g = GLParser()..parse(schema);
      out = _serializer(g).doSerializeInputDefinition(g.inputs['PriceRangeFilter']!);
    });

    test('max has no default — nullable double with no initializer', () {
      expect(lines(out), contains('final double? max;'));
    });

    test('min default 0 is a valid Dart double literal — implicit int-to-double literal conversion', () {
      // Dart allows an integer literal (`0`) in a context expecting `double`
      // (e.g. `this.min = 0` in a constructor parameter default), so this
      // does not have the same bug as Kotlin/Java, where boxed Double fields
      // reject a bare Int literal.
      expect(lines(out), contains('final double? min;'));
      expect(lines(out), contains('this.min = 0'));
    });
  });
}
