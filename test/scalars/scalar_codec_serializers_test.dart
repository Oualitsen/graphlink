import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/scalar_codec.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/dart/dart_serializer.dart';
import 'package:graphlink/src/serializers/go/go_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:graphlink/src/serializers/swift/swift_serializer.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
scalar DateTime
type Query { now: DateTime! bag: Bag }
type Bag {
  at: DateTime!
  maybe: DateTime
  many: [DateTime!]!
}
input BagInput {
  at: DateTime!
  maybe: DateTime
}
''';

GLScalarCodec _codec(String type, String from, String to, [Object? import]) => GLScalarCodec.fromConfig('DateTime', {
      'type': type,
      'fromJson': from,
      'toJson': to,
      if (import != null) 'import': import,
    });

class _Emitted {
  final String type;
  final String input;
  _Emitted(GLSerializer s, GLParser g)
      : type = s.serializeTypeDefinition(g.types['Bag'] as GLTypeDefinition),
        input = s.serializeInputDefinition(g.inputs['BagInput']!);
}

GLParser _parser(GLScalarCodec codec, {NamingConvention? naming, Set<String> reserved = const {}}) =>
    GLParser(scalarCodecs: {'DateTime': codec}, naming: naming, reservedWords: reserved)..parse(_schema);

void main() {
  test('Dart', () {
    final codec = _codec('DateTime', 'DateTime.parse({} as String)', '{}.toUtc().toIso8601String()');
    final g = _parser(codec);
    final e = _Emitted(DartSerializer(g, importPrefix: '', typeMapOverrides: {'DateTime': codec.type}), g);
    expect(e.type, contains("at: DateTime.parse(json['at'] as String)"));
    expect(e.type, contains("maybe: json['maybe'] == null ? null : DateTime.parse(json['maybe'] as String)"));
    expect(e.type, contains("(json['many'] as List<dynamic>).map((e0) => DateTime.parse(e0 as String)).toList()"));
    expect(e.type, contains("'at': at.toUtc().toIso8601String()"));
    expect(e.type, contains("'maybe': maybe == null ? null : maybe!.toUtc().toIso8601String()"));
    expect(e.type, contains('many.map((e0) => e0.toUtc().toIso8601String()).toList()'));
    expect(e.input, contains("'at': at.toUtc().toIso8601String()"));
  });

  test('Kotlin', () {
    final codec = _codec('OffsetDateTime', 'OffsetDateTime.parse({} as String)', '{}.toString()', 'java.time.OffsetDateTime');
    final g = _parser(codec);
    final e = _Emitted(KotlinSerializer(g, importPrefix: '', typeMapOverrides: {'DateTime': codec.type}), g);
    expect(e.type, contains('at = OffsetDateTime.parse(map["at"] as String)'));
    expect(e.type, contains('map["maybe"]?.let { OffsetDateTime.parse(it as String) }'));
    expect(e.type, contains('"at" to at.toString()'));
    expect(e.type, contains('maybe?.let { it.toString() }'));
    expect(e.type, contains('import java.time.OffsetDateTime'));
  });

  test('Swift', () {
    final codec = _codec('Date', 'ISO8601DateFormatter().date(from: {} as! String)!', 'ISO8601DateFormatter().string(from: {})');
    final g = _parser(codec);
    final e = _Emitted(SwiftSerializer(g, importPrefix: '', typeMapOverrides: {'DateTime': codec.type}), g);
    expect(e.type, contains('ISO8601DateFormatter().date(from: map["at"] as! String)!'));
    expect(e.type, contains('.map { ISO8601DateFormatter().date(from: \$0 as! String)! }'));
    expect(e.type, contains('ISO8601DateFormatter().string(from: at)'));
    expect(e.type, contains('maybe.map { ISO8601DateFormatter().string(from: \$0) }'));
  });

  test('Java', () {
    final codec = _codec('OffsetDateTime', 'OffsetDateTime.parse((String) {})', '{}.toString()', 'java.time.OffsetDateTime');
    final g = _parser(codec);
    final e = _Emitted(JavaSerializer(g, importPrefix: '', typeMapOverrides: {'DateTime': codec.type}), g);
    expect(e.type, contains('OffsetDateTime.parse((String) json.get("at"))'));
    expect(e.type, contains('json.get("maybe") == null ? null : OffsetDateTime.parse((String) json.get("maybe"))'));
    expect(e.type, contains('at.toString()'));
    expect(e.type, contains('maybe == null ? null : maybe.toString()'));
    expect(e.type, contains('import java.time.OffsetDateTime;'));
  });

  test('TypeScript', () {
    final codec = _codec('Date', 'new Date({} as string)', '{}.toISOString()');
    final g = _parser(codec);
    final e = _Emitted(TypeScriptSerializer(g, importPrefix: '', typeMapOverrides: {'DateTime': codec.type}), g);
    expect(e.type, contains('new Date(json["at"] as string)'));
    expect(e.type, contains('json["maybe"] != null ? new Date(json["maybe"] as string) : null'));
    expect(e.type, contains('"at": obj.at.toISOString()'));
    expect(e.type, contains('obj.maybe != null ? obj.maybe.toISOString() : obj.maybe'));
  });

  test('Python', () {
    final codec = _codec('datetime', 'datetime.fromisoformat({})', '{}.isoformat()', 'from datetime import datetime');
    final g = _parser(codec, naming: NamingConvention.python, reserved: pythonReservedWords);
    final e = _Emitted(PythonSerializer(g, typeMapOverrides: {'DateTime': codec.type}), g);
    expect(e.type, contains('at=datetime.fromisoformat(json["at"])'));
    expect(e.type, contains('maybe=(None if json.get("maybe") is None else datetime.fromisoformat(json.get("maybe")))'));
    expect(e.type, contains('"at": self.at.isoformat()'));
    expect(e.type, contains('"maybe": (None if self.maybe is None else self.maybe.isoformat())'));
    expect(e.type, contains('from datetime import datetime'));
  });

  test('Go', () {
    final codec = _codec('string', 'strings.ToUpper({}.(string))', 'strings.ToLower({})');
    final g = _parser(codec, naming: NamingConvention.go, reserved: goReservedWords);
    final e = _Emitted(GoSerializer(g, typeMapOverrides: {'DateTime': codec.type}), g);
    expect(e.type, contains('func(v any) (string, error) { return strings.ToUpper(v.(string)), nil }(m["at"])'));
    expect(e.type, contains('glPtr(func(v any) (string, error) { return strings.ToUpper(v.(string)), nil })(m["maybe"])'));
    expect(e.type, contains('func(v string) (any, error) { return strings.ToLower(v), nil }(v.At)'));
    expect(e.type, contains('glEncPtr(func(v string) (any, error) { return strings.ToLower(v), nil })(v.Maybe)'));
    expect(e.type, contains('glEncList(func(v string) (any, error) { return strings.ToLower(v), nil })(v.Many)'));
  });

  test('a plain alias changes nothing', () {
    final g = GLParser(scalarCodecs: {'DateTime': GLScalarCodec.fromConfig('DateTime', 'String')})..parse(_schema);
    final out = DartSerializer(g, importPrefix: '', typeMapOverrides: {'DateTime': 'String'}).serializeTypeDefinition(g.types['Bag']!);
    expect(out, contains("at: json['at'] as String"));
    expect(out, contains("'at': at"));
  });
}
