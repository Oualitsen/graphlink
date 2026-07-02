import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:test/test.dart';

JavaSerializer _serializer(GLParser g, {bool immutableInputFields = true}) => JavaSerializer(
      g,
      importPrefix: 'com.example',
      immutableInputFields: immutableInputFields,
    );

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
  group('java input default value serialization', () {
    late GLParser g;

    setUp(() {
      g = GLParser()..parse(schema);
    });

    group('immutable (final) fields — default config', () {
      late String out;
      setUp(() {
        out = _serializer(g).doSerializeInputDefinition(g.inputs['PriceRangeFilter']!);
      });

      test('fields are final, boxed Double, with no field initializer', () {
        expect(lines(out), containsAllInOrder(['private final Double max;', 'private final Double min;']));
      });

      test('constructor falls back to a valid Double literal, not a bare Int', () {
        expect(lines(out), contains('this.min = min != null ? min : 0.0;'));
      });
    });

    group('mutable fields — immutableInputFields: false', () {
      late String out;
      setUp(() {
        out = _serializer(g, immutableInputFields: false)
            .doSerializeInputDefinition(g.inputs['PriceRangeFilter']!);
      });

      test('min default 0 is emitted as a valid Java Double literal, not an Int', () {
        // `private Double min = 0;` fails to compile in Java — boxed Double
        // fields don't accept an int literal in a field initializer.
        expect(lines(out), contains('private Double min = 0.0;'));
        expect(out, isNot(contains('= 0;')));
      });

      test('max has no default — plain boxed Double field', () {
        expect(lines(out), contains('private Double max;'));
      });
    });
  });
}
