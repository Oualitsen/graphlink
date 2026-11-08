import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/scalar_codec.dart';
import 'package:graphlink/src/serializers/go/go_serializer.dart';
import 'package:graphlink/src/serializers/swift/swift_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
scalar Opaque
scalar Count
type Query { bag: Bag }
type Bag {
  tag: Opaque!
  maybeTag: Opaque
  tags: [Opaque!]!
  maybeTags: [Opaque]
  count: Count!
}
''';

Map<String, dynamic> _config(Map<String, dynamic> typeMappings) => {
      'schemaPaths': ['schema.graphql'],
      'mode': 'client',
      'outputDir': 'out',
      'typeMappings': typeMappings,
    };

GLScalarCodec _codec(String type, String jsonType, [String? fromJson]) =>
    GLScalarCodec.fromConfig('Opaque', {'type': type, 'jsonType': jsonType, if (fromJson != null) 'fromJson': fromJson});

String _expr(Map<String, GLScalarCodec> codecs, String field) {
  final g = GLParser(scalarCodecs: codecs)..parse(_schema);
  final s = SwiftSerializer(g, importPrefix: '', typeMapOverrides: {for (final e in codecs.entries) e.key: e.value.type});
  final type = g.types['Bag']!.fields.firstWhere((f) => f.name.token == field).type;
  return s.checkedFromJsonExpr(type, 'j', 'Bag.$field');
}

void main() {
  group('config', () {
    test('jsonType is read from an object mapping', () {
      final c = GeneratorConfig.fromJson(_config({
        'Opaque': {'type': 'String', 'jsonType': 'String', 'fromJson': '{}'},
      }));
      expect(c.scalarCodecs['Opaque']!.jsonType, 'String');
    });

    test('jsonType is optional', () {
      final c = GeneratorConfig.fromJson(_config({
        'Opaque': {'type': 'String', 'fromJson': '{}'},
      }));
      expect(c.scalarCodecs['Opaque']!.jsonType, isNull);
    });

    test('every documented value is accepted', () {
      for (final value in ['String', 'Int', 'Double', 'Bool', 'Map', 'List']) {
        expect(_codec('T', value).jsonType, value);
      }
    });

    test('an unknown jsonType names the scalar and the allowed values', () {
      expect(
        () => _codec('String', 'Date'),
        throwsA(isA<ArgumentError>()
            .having((e) => e.message, 'message', allOf(contains('Opaque'), contains('jsonType'), contains('String')))),
      );
    });
  });

  group('Swift', () {
    final typed = {'Opaque': _codec('String', 'String', '"opaque:" + {}'), 'Count': _codec('Int', 'Int')};

    test('a non-null field reads the wire value through the checked helper', () {
      expect(_expr(typed, 'tag'), 'try "opaque:" + glString(j, "Bag.tag")');
    });

    test('a nullable field returns nil for null and checks a present value', () {
      expect(_expr(typed, 'maybeTag'), 'try glStringOrNil(j, "Bag.maybeTag").map { "opaque:" + \$0 }');
    });

    test('list elements are read one by one', () {
      expect(_expr(typed, 'tags'), 'try glList(j, "Bag.tags").map { e0 in try "opaque:" + glString(e0, "Bag.tags") }');
    });

    test('nullable list elements use the nil-returning helper', () {
      expect(
        _expr(typed, 'maybeTags'),
        'try glListOrNil(j, "Bag.maybeTags")?.map { e0 in try glStringOrNil(e0, "Bag.maybeTags").map { "opaque:" + \$0 } }',
      );
    });

    test('each jsonType picks its own helper', () {
      expect(_expr(typed, 'count'), 'try glInt(j, "Bag.count")');
    });

    test('without jsonType the template still receives the untyped value', () {
      final untyped = {'Opaque': GLScalarCodec.fromConfig('Opaque', {'type': 'String', 'fromJson': '"opaque:" + ({} as! String)'})};
      expect(_expr(untyped, 'tag'), '"opaque:" + (j as! String)');
    });
  });

  group('Go', () {
    String expr(Map<String, GLScalarCodec> codecs, String field) {
      final g = GLParser(scalarCodecs: codecs)..parse(_schema);
      final s = GoSerializer(g, importPrefix: '', typeMapOverrides: {for (final e in codecs.entries) e.key: e.value.type});
      final type = g.types['Bag']!.fields.firstWhere((f) => f.name.token == field).type;
      return s.fromJsonExpr(type, 'j');
    }

    final typed = {'Opaque': _codec('string', 'String', '"opaque:" + {}'), 'Count': _codec('int', 'Int', '{}')};

    test('a non-null field reads the wire value through a typed reader', () {
      expect(expr(typed, 'tag'), 'glThen(glString, func(v string) string { return "opaque:" + v })(j)');
    });

    test('a nullable field is wrapped so null stays nil', () {
      expect(expr(typed, 'maybeTag'), 'glPtr(glThen(glString, func(v string) string { return "opaque:" + v }))(j)');
    });

    test('list elements are decoded one by one', () {
      expect(expr(typed, 'tags'), 'glList(glThen(glString, func(v string) string { return "opaque:" + v }))(j)');
    });

    test('each jsonType picks its own reader and Go type', () {
      expect(expr(typed, 'count'), 'glThen(glInt, func(v int) int { return v })(j)');
      for (final entry in {
        'Double': ['glFloat64', 'float64'],
        'Bool': ['glBool', 'bool'],
        'Map': ['glMapAny', 'map[string]any'],
        'List': ['glListAny', '[]any'],
      }.entries) {
        final codecs = {'Opaque': _codec('T', entry.key, '{}'), 'Count': _codec('int', 'Int', '{}')};
        expect(expr(codecs, 'tag'), contains('glThen(${entry.value[0]}, func(v ${entry.value[1]})'), reason: entry.key);
      }
    });

    test('without jsonType the template still receives the untyped value', () {
      final untyped = {'Opaque': GLScalarCodec.fromConfig('Opaque', {'type': 'string', 'fromJson': '"opaque:" + {}.(string)'})};
      expect(expr(untyped, 'tag'), 'func(v any) (string, error) { return "opaque:" + v.(string), nil }(j)');
    });
  });
}
