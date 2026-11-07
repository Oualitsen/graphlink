import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/scalar_codec.dart';
import 'package:test/test.dart';

const _decodeOnly = {'type': 'T', 'fromJson': 'f({})'};
const _encodeOnly = {'type': 'T', 'toJson': 'g({})'};
const _both = {'type': 'T', 'fromJson': 'f({})', 'toJson': 'g({})'};

void _parse(String schema, Map<String, Object> codecs) {
  GLParser(scalarCodecs: {
    for (final e in codecs.entries) e.key: GLScalarCodec.fromConfig(e.key, e.value),
  }).parse(schema);
}

Matcher _fails(List<String> parts) => throwsA(isA<ParseException>().having(
      (e) => e.message,
      'message',
      allOf([for (final p in parts) contains(p)]),
    ));

void main() {
  group('a scalar used on one side only', () {
    test('encode only is enough for an operation argument', () {
      expect(
        () => _parse('scalar Money type Query { price(m: Money): String }', {'Money': _encodeOnly}),
        returnsNormally,
      );
    });

    test('encode only is enough for an input field', () {
      expect(
        () => _parse('scalar Money input I { m: Money } type Query { a(i: I): String }', {'Money': _encodeOnly}),
        returnsNormally,
      );
    });

    test('decode only is enough for a response field', () {
      expect(
        () => _parse('scalar Stamp type Query { now: Stamp } type T { at: Stamp }', {'Stamp': _decodeOnly}),
        returnsNormally,
      );
    });

    test('decode only is enough for a list of response values', () {
      expect(
        () => _parse('scalar Stamp type Query { all: [[Stamp!]] }', {'Stamp': _decodeOnly}),
        returnsNormally,
      );
    });
  });

  group('a scalar used on the side the codec does not cover', () {
    test('an encode-only scalar in a response field is rejected', () {
      expect(
        () => _parse('scalar Money type Query { price: Money }', {'Money': _encodeOnly}),
        _fails(['Money', 'fromJson', 'Query.price']),
      );
    });

    test('a decode-only scalar as an operation argument is rejected', () {
      expect(
        () => _parse('scalar Stamp type Query { a(at: Stamp): String }', {'Stamp': _decodeOnly}),
        _fails(['Stamp', 'toJson', 'at']),
      );
    });

    test('a decode-only scalar in an input field is rejected', () {
      expect(
        () => _parse('scalar Stamp input I { at: Stamp } type Query { a(i: I): String }', {'Stamp': _decodeOnly}),
        _fails(['Stamp', 'toJson', 'I.at']),
      );
    });

    test('a custom operation variable counts as an argument', () {
      expect(
        () => _parse(
          'scalar Stamp type Query { a(at: String): String } query q(\$at: Stamp) { a(at: "x") }',
          {'Stamp': _decodeOnly},
        ),
        _fails(['Stamp', 'toJson', 'q']),
      );
    });

    test('a list element counts', () {
      expect(
        () => _parse('scalar Money type Query { all: [Money!]! }', {'Money': _encodeOnly}),
        _fails(['Money', 'fromJson']),
      );
    });

    test('a scalar used on both sides with one side declared fails once, naming the missing side', () {
      expect(
        () => _parse('scalar Money input I { m: Money } type Query { a(i: I): Money }', {'Money': _encodeOnly}),
        _fails(['Money', 'fromJson']),
      );
    });
  });

  group('default values', () {
    test('a default on a scalar that has a codec is rejected, because the literal is a wire value', () {
      expect(
        () => _parse('scalar Stamp type Query { a(at: Stamp = "2026-01-01"): String }', {'Stamp': _both}),
        _fails(['Stamp', 'default', 'at']),
      );
    });

    test('a default inside an input type is rejected too', () {
      expect(
        () => _parse('scalar Stamp input I { at: Stamp = "2026-01-01" } type Query { a(i: I): String }', {'Stamp': _both}),
        _fails(['Stamp', 'default', 'I.at']),
      );
    });

    test('a list default counts', () {
      expect(
        () => _parse('scalar Stamp type Query { a(at: [Stamp!] = ["x"]): String }', {'Stamp': _both}),
        _fails(['Stamp', 'default']),
      );
    });

    test('an alias keeps its default', () {
      expect(
        () => _parse('scalar Long type Query { a(n: Long = 9007199254740993): String }', {'Long': 'int'}),
        returnsNormally,
      );
    });

    test('a codec scalar without a default is fine', () {
      expect(
        () => _parse('scalar Stamp type Query { a(at: Stamp): String }', {'Stamp': _both}),
        returnsNormally,
      );
    });
  });

  group('opting out', () {
    test('an explicit identity on the missing side makes it pass', () {
      expect(
        () => _parse('scalar Money type Query { price(m: Money): Money }', {
          'Money': {'type': 'String', 'toJson': '{}', 'fromJson': '{}'},
        }),
        returnsNormally,
      );
    });

    test('both sides declared never fails', () {
      expect(
        () => _parse('scalar D input I { d: D } type Query { a(i: I, d: D): D }', {'D': _both}),
        returnsNormally,
      );
    });

    test('an alias is never checked', () {
      expect(
        () => _parse('scalar Long input I { l: Long } type Query { a(i: I): Long }', {'Long': 'int'}),
        returnsNormally,
      );
    });

    test('a codec with imports only is never checked', () {
      expect(
        () => _parse('scalar Opaque type Query { a(o: Opaque): Opaque }', {
          'Opaque': {'type': 'Foo', 'import': 'foo'},
        }),
        returnsNormally,
      );
    });

    test('a scalar that is never used is never checked', () {
      expect(
        () => _parse('scalar Unused type Query { a: String }', {'Unused': _encodeOnly}),
        returnsNormally,
      );
    });
  });
}
