import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/scalar_codec.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_scalar_codec_extension.dart';
import 'package:test/test.dart';

const _schema = '''
scalar DateTime
scalar Money
scalar Plain

type Query {
  now: DateTime!
  priceOf(sku: String!, at: DateTime): Money
  plain(p: Plain): Plain
}

type Bag {
  at: DateTime!
  ats: [DateTime!]!
  nested: [[DateTime]]
  money: Money
  name: String
}

type Empty { name: String }

input BagInput {
  at: DateTime!
  ats: [DateTime!]
}

query one(\$when: DateTime!) { priceOf(sku: "a", at: \$when) }
query two(\$when: DateTime, \$m: [Money!]) { now }
query none(\$s: String) { plain(p: null) }
''';

GLQueryDefinition _op(GLParser g, String name) => g.queries[GLOperationKey(name, GLQueryType.query)]!;

GLParser _parser({Map<String, GLScalarCodec>? codecs}) {
  final g = GLParser(
    scalarCodecs: codecs ??
        {
          'DateTime': GLScalarCodec.fromConfig('DateTime', {
            'type': 'OffsetDateTime',
            'import': 'java.time.OffsetDateTime',
            'fromJson': 'OffsetDateTime.parse({})',
            'toJson': '{}.toString()',
          }),
          'Money': GLScalarCodec.fromConfig('Money', {
            'type': 'Decimal',
            'import': ['decimal.Decimal', 'decimal.Context'],
          }),
        },
  );
  g.parse(_schema);
  return g;
}

void main() {
  group('type and input imports', () {
    test('a scalar field imports its codec', () {
      final g = _parser();
      expect(g.getType('Bag'.toToken()).getImports(g), contains('java.time.OffsetDateTime'));
    });

    test('list elements and nested lists are covered', () {
      final g = _parser(codecs: {
        'DateTime': GLScalarCodec.fromConfig('DateTime', {'type': 'D', 'import': 'only.for.dates'}),
      });
      final onlyList = g.getType('Bag'.toToken()).getImports(g);
      expect(onlyList, contains('only.for.dates'));
    });

    test('every import of a multi-import codec is added', () {
      final g = _parser();
      expect(g.getType('Bag'.toToken()).getImports(g), containsAll(['decimal.Decimal', 'decimal.Context']));
    });

    test('a type without scalar fields gets none', () {
      final g = _parser();
      final imports = g.getType('Empty'.toToken()).getImports(g);
      expect(imports.where((i) => i.contains('OffsetDateTime') || i.contains('decimal')), isEmpty);
    });

    test('an input imports the codecs of its fields', () {
      final g = _parser();
      expect(g.inputs['BagInput']!.getImports(g), contains('java.time.OffsetDateTime'));
    });

    test('field arguments import their codecs', () {
      final g = _parser();
      expect(g.getType('Query'.toToken()).getImports(g), contains('java.time.OffsetDateTime'));
    });

    test('a scalar without a codec adds nothing', () {
      final g = _parser();
      expect(g.getType('Query'.toToken()).getImports(g).where((i) => i.toLowerCase().contains('plain')), isEmpty);
    });
  });

  group('operation imports', () {
    test('an argument scalar contributes its codec imports', () {
      final g = _parser();
      expect(g.scalarImportsOfOperation(_op(g, 'one')), {'java.time.OffsetDateTime'});
    });

    test('a list argument is covered', () {
      final g = _parser();
      expect(g.scalarImportsOfOperation(_op(g, 'two')), {'java.time.OffsetDateTime', 'decimal.Decimal', 'decimal.Context'});
    });

    test('an operation with only built-in arguments gets none', () {
      final g = _parser();
      expect(g.scalarImportsOfOperation(_op(g, 'none')), isEmpty);
    });

    test('all operations together are deduplicated', () {
      final g = _parser();
      final all = g.scalarImportsOfOperations(g.queries.values);
      expect(all, {'java.time.OffsetDateTime', 'decimal.Decimal', 'decimal.Context'});
    });
  });

  group('codec lookup', () {
    test('finds the codec of a scalar token', () {
      final g = _parser();
      expect(g.scalarCodecOf('DateTime')!.type, 'OffsetDateTime');
      expect(g.scalarCodecOf('Plain'), isNull);
      expect(g.scalarCodecOf('String'), isNull);
    });

    test('a codec with imports for an undeclared scalar is rejected', () {
      final g = GLParser(scalarCodecs: {
        'Missing': GLScalarCodec.fromConfig('Missing', {'type': 'T', 'import': 'x'}),
      });
      expect(
        () => g.parse('type Query { a: String }'),
        throwsA(isA<ParseException>().having((e) => e.message, 'message', contains('Missing'))),
      );
    });

    test('a plain alias for an undeclared scalar is ignored, as before', () {
      final g = GLParser(scalarCodecs: {'Long': GLScalarCodec.fromConfig('Long', 'int')});
      expect(() => g.parse('type Query { a: String }'), returnsNormally);
    });
  });
}
