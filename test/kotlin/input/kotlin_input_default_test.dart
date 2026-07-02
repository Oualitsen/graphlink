import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:test/test.dart';

KotlinSerializer _serializer(GLParser g) => KotlinSerializer(
      g,
      importPrefix: 'com.example',
      inputsAsDataClass: true,
      typesAsDataClass: true,
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
  group('kotlin input default value serialization', () {
    late GLParser g;
    late String out;

    setUp(() {
      g = GLParser()..parse(schema);
      out = _serializer(g).doSerializeInputDefinition(g.inputs['PriceRangeFilter']!);
    });

    test('max has no default — nullable Double with null default', () {
      expect(lines(out), contains('val max: Double? = null,'));
    });

    test('min default 0 is emitted as a valid Kotlin Double literal, not an Int', () {
      expect(lines(out), contains('val min: Double? = 0.0,'));
      expect(out, isNot(contains('= 0,')));
    });

    test('toJson emits both keys', () {
      expect(lines(out), containsAllInOrder([
        'fun toJson(): Map<String, Any?> = mapOf(',
        '"max" to max,',
        '"min" to min,',
      ]));
    });

    test('fromJson parses both fields as nullable Double', () {
      expect(lines(out), containsAllInOrder([
        'fun fromJson(map: Map<String, Any?>): PriceRangeFilter = PriceRangeFilter(',
        'max = (map["max"] as? Number)?.toDouble(),',
        'min = (map["min"] as? Number)?.toDouble(),',
      ]));
    });
  });
}
