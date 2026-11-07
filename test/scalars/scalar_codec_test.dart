import 'package:graphlink/src/model/scalar_codec.dart';
import 'package:test/test.dart';

void main() {
  group('GLScalarCodec.fromConfig', () {
    test('a plain string is a type alias that converts nothing', () {
      final c = GLScalarCodec.fromConfig('Long', 'int');
      expect(c.type, 'int');
      expect(c.canDecode, isFalse);
      expect(c.canEncode, isFalse);
      expect(c.imports, isEmpty);
    });

    test('an object carries type, codec expressions and one import', () {
      final c = GLScalarCodec.fromConfig('Money', {
        'type': 'Decimal',
        'import': 'package:decimal/decimal.dart',
        'fromJson': 'Decimal.parse({})',
        'toJson': '{}.toString()',
      });
      expect(c.type, 'Decimal');
      expect(c.canDecode, isTrue);
      expect(c.canEncode, isTrue);
      expect(c.imports, {'package:decimal/decimal.dart'});
    });

    test('import may be a list, and duplicates collapse', () {
      final c = GLScalarCodec.fromConfig('Money', {
        'type': 'Decimal',
        'import': ['a', 'b', 'a'],
      });
      expect(c.imports, {'a', 'b'});
    });

    test('an object without codec expressions is a type alias with imports', () {
      final c = GLScalarCodec.fromConfig('Opaque', {'type': 'Foo', 'import': 'foo'});
      expect(c.canDecode, isFalse);
      expect(c.canEncode, isFalse);
      expect(c.imports, {'foo'});
    });

    test('type is required in the object form', () {
      expect(() => GLScalarCodec.fromConfig('X', {'fromJson': '{}', 'toJson': '{}'}), throwsA(isA<ArgumentError>()));
    });

    test('either side may be declared alone', () {
      final decodeOnly = GLScalarCodec.fromConfig('X', {'type': 'T', 'fromJson': 'f({})'});
      expect([decodeOnly.canDecode, decodeOnly.canEncode], [true, false]);
      final encodeOnly = GLScalarCodec.fromConfig('X', {'type': 'T', 'toJson': 'g({})'});
      expect([encodeOnly.canDecode, encodeOnly.canEncode], [false, true]);
    });

    test('an expression without the {} placeholder is rejected', () {
      expect(
        () => GLScalarCodec.fromConfig('X', {'type': 'T', 'fromJson': 'f()', 'toJson': 'g({})'}),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('X'))),
      );
    });

    test('any other value is rejected', () {
      expect(() => GLScalarCodec.fromConfig('X', 5), throwsA(isA<ArgumentError>()));
      expect(() => GLScalarCodec.fromConfig('X', {'type': 5}), throwsA(isA<ArgumentError>()));
      expect(() => GLScalarCodec.fromConfig('X', {'type': 'T', 'import': 5}), throwsA(isA<ArgumentError>()));
    });
  });

  group('decode and encode', () {
    final c = GLScalarCodec.fromConfig('DateTime', {
      'type': 'DateTime',
      'fromJson': 'DateTime.parse({})',
      'toJson': '{}.toUtc().toIso8601String()',
    });

    test('substitute the placeholder', () {
      expect(c.decode("json['dt']"), "DateTime.parse(json['dt'])");
      expect(c.encode('dt'), 'dt.toUtc().toIso8601String()');
    });

    test('every placeholder is replaced', () {
      final twice = GLScalarCodec.fromConfig('X', {'type': 'T', 'fromJson': 'f({}, {})', 'toJson': '{}'});
      expect(twice.decode('v'), 'f(v, v)');
    });

    test('the side that is not declared returns the expression untouched', () {
      final decodeOnly = GLScalarCodec.fromConfig('X', {'type': 'T', 'fromJson': 'f({})'});
      expect(decodeOnly.decode('v'), 'f(v)');
      expect(decodeOnly.encode('v'), 'v');
    });

    test('an alias returns the expression untouched', () {
      final alias = GLScalarCodec.fromConfig('Long', 'int');
      expect(alias.decode('v'), 'v');
      expect(alias.encode('v'), 'v');
    });
  });
}
