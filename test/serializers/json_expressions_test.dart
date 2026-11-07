import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/scalar_codec.dart';
import 'package:graphlink/src/serializers/dart/dart_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/go/go_serializer.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:graphlink/src/serializers/swift/swift_serializer.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
scalar Stamp
enum Role { ADMIN }
type Address { street: String }
type Query { a: Address }
type Holder {
  maybeRole: Role
  maybeAddress: Address
  roles: [Role!]!
  grid: [[Address]]
  maybeStamp: Stamp
  stamps: [Stamp!]
}
''';

final _codec = GLScalarCodec.fromConfig('Stamp', {'type': 'int', 'fromJson': 'conv({})', 'toJson': 'back({})'});

typedef _Expected = Map<String, List<String>>;

void _check(GLSerializer Function(GLParser) make, _Expected expected) {
  final parser = GLParser(scalarCodecs: {'Stamp': _codec})..parse(_schema);
  final s = make(parser);
  final fields = {for (final f in parser.types['Holder']!.fields) f.name.token: f.type};
  expected.forEach((name, pair) {
    final type = fields[name]!;
    expect(s.toJsonExpr(type, 'v'), pair[0], reason: 'toJsonExpr $name');
    expect(s.fromJsonExpr(type, 'j'), pair[1], reason: 'fromJsonExpr $name');
  });
}

void main() {
  test('Dart', () {
    _check((p) => DartSerializer(p, importPrefix: '', typeMapOverrides: {'Stamp': 'int'}), {
      'maybeRole': ['v?.toJson()', 'j == null ? null : Role.fromJson(j as String)'],
      'maybeAddress': ['v?.toJson()', 'j == null ? null : Address.fromJson(j as Map<String, dynamic>)'],
      'roles': ['v.map((e0) => e0.toJson()).toList()', '(j as List<dynamic>).map((e0) => Role.fromJson(e0 as String)).toList()'],
      'grid': ['v?.map((e0) => e0?.map((e1) => e1?.toJson()).toList()).toList()', '(j as List<dynamic>?)?.map((e0) => (e0 as List<dynamic>?)?.map((e1) => e1 == null ? null : Address.fromJson(e1 as Map<String, dynamic>)).toList()).toList()'],
      'maybeStamp': ['v == null ? null : back(v!)', 'j == null ? null : conv(j)'],
      'stamps': ['v?.map((e0) => back(e0)).toList()', '(j as List<dynamic>?)?.map((e0) => conv(e0)).toList()'],
    });
  });

  test('Kotlin', () {
    _check((p) => KotlinSerializer(p, importPrefix: '', typeMapOverrides: {'Stamp': 'Int'}), {
      'maybeRole': ['v?.toJson()', '(j as? String)?.let { Role.fromJson(it) }'],
      'maybeAddress': ['v?.toJson()', '(j as? Map<*, *>)?.let { Address.fromJson(it as Map<String, Any?>) }'],
      'roles': ['v.map { e0 -> e0.toJson() }', '(j as List<*>).map { e0 -> Role.fromJson(e0 as String)!! }'],
      'grid': ['v?.map { e0 -> e0?.map { e1 -> e1?.toJson() } }', '(j as? List<*>)?.map { e0 -> (e0 as? List<*>)?.map { e1 -> (e1 as? Map<*, *>)?.let { Address.fromJson(it as Map<String, Any?>) } } }'],
      'maybeStamp': ['v?.let { back(it) }', 'j?.let { conv(it) }'],
      'stamps': ['v?.map { e0 -> back(e0) }', '(j as? List<*>)?.map { e0 -> conv(e0) }'],
    });
  });

  test('Swift', () {
    _check((p) => SwiftSerializer(p, importPrefix: '', typeMapOverrides: {'Stamp': 'Int'}), {
      'maybeRole': ['v?.toJson()', '(j as? String).map { Role.fromJson(\$0) }'],
      'maybeAddress': ['v?.toJson()', '(j as? [String: Any?]).map { Address.fromJson(\$0) }'],
      'roles': ['v.map { e0 in e0.toJson() }', '(j as! [Any?]).map { e0 in Role.fromJson(e0 as! String) }'],
      'grid': ['v?.map { e0 in e0?.map { e1 in e1?.toJson() } }', '(j as? [Any?])?.map { e0 in (e0 as? [Any?])?.map { e1 in (e1 as? [String: Any?]).map { Address.fromJson(\$0) } } }'],
      'maybeStamp': ['v.map { back(\$0) }', '(j ?? nil).flatMap { \$0 is NSNull ? nil : \$0 }.map { conv(\$0) }'],
      'stamps': ['v?.map { e0 in back(e0) }', '(j as? [Any?])?.map { e0 in conv(e0) }'],
    });
  });

  test('Java', () {
    _check((p) => JavaSerializer(p, importPrefix: '', typeMapOverrides: {'Stamp': 'Integer'}), {
      'maybeRole': ['v == null ? null : v.toJson()', 'j == null ? null : Role.fromJson((String)j)'],
      'maybeAddress': ['v == null ? null : v.toJson()', 'j == null ? null : Address.fromJson((Map<String, Object>)j)'],
      'roles': ['v.stream().map(e0 -> e0.toJson()).collect(Collectors.toList())', '((List<?>)j).stream().map(e0 -> Role.fromJson((String)e0)).collect(Collectors.toList())'],
      'grid': ['v == null ? null : v.stream().map(e0 -> e0 == null ? null : e0.stream().map(e1 -> e1 == null ? null : e1.toJson()).collect(Collectors.toList())).collect(Collectors.toList())', 'j == null ? null : ((List<?>)j).stream().map(e0 -> e0 == null ? null : ((List<?>)e0).stream().map(e1 -> e1 == null ? null : Address.fromJson((Map<String, Object>)e1)).collect(Collectors.toList())).collect(Collectors.toList())'],
      'maybeStamp': ['v == null ? null : back(v)', 'j == null ? null : conv(j)'],
      'stamps': ['v == null ? null : v.stream().map(e0 -> back(e0)).collect(Collectors.toList())', 'j == null ? null : ((List<?>)j).stream().map(e0 -> conv(e0)).collect(Collectors.toList())'],
    });
  });

  test('TypeScript', () {
    _check((p) => TypeScriptSerializer(p, importPrefix: '', typeMapOverrides: {'Stamp': 'number'}), {
      'maybeRole': ['v != null ? Role.toJson(v) : v', 'j != null ? Role.fromJson(j as string) : null'],
      'maybeAddress': ['v != null ? Address.toJson(v) : v', 'j != null ? Address.fromJson(j as Record<string, unknown>) : null'],
      'roles': ['v.map((e0) => Role.toJson(e0))', '(j as unknown[]).map((e0) => Role.fromJson(e0 as string))'],
      'grid': ['v != null ? v.map((e0) => e0 != null ? e0.map((e1) => e1 != null ? Address.toJson(e1) : e1) : e0) : v', 'j != null ? (j as unknown[]).map((e0) => e0 != null ? (e0 as unknown[]).map((e1) => e1 != null ? Address.fromJson(e1 as Record<string, unknown>) : null) : null) : null'],
      'maybeStamp': ['v != null ? back(v) : v', 'j != null ? conv(j) : null'],
      'stamps': ['v != null ? v.map((e0) => back(e0)) : v', 'j != null ? (j as unknown[]).map((e0) => conv(e0)) : null'],
    });
  });

  test('Python', () {
    _check((p) => PythonSerializer(p, importPrefix: '', typeMapOverrides: {'Stamp': 'int'}), {
      'maybeRole': ['(None if v is None else v.to_json())', '(None if j is None else Role.from_json(j))'],
      'maybeAddress': ['(None if v is None else v.to_json())', '(None if j is None else Address.from_json(j))'],
      'roles': ['[e0.to_json() for e0 in v]', '[Role.from_json(e0) for e0 in j]'],
      'grid': ['(None if v is None else [(None if e0 is None else [(None if e1 is None else e1.to_json()) for e1 in e0]) for e0 in v])', '(None if j is None else [(None if e0 is None else [(None if e1 is None else Address.from_json(e1)) for e1 in e0]) for e0 in j])'],
      'maybeStamp': ['(None if v is None else back(v))', '(None if j is None else conv(j))'],
      'stamps': ['(None if v is None else [back(e0) for e0 in v])', '(None if j is None else [conv(e0) for e0 in j])'],
    });
  });

  test('Go', () {
    _check((p) => GoSerializer(p, importPrefix: '', typeMapOverrides: {'Stamp': 'int'}), {
      'maybeRole': ['glEncPtr(glEncEnum[Role])(v)', 'glPtr(RoleFromJson)(j)'],
      'maybeAddress': ['glEncPtr(glEncObject[Address])(v)', 'glPtr(glObject(AddressFromJson))(j)'],
      'roles': ['glEncList(glEncEnum[Role])(v)', 'glList(RoleFromJson)(j)'],
      'grid': ['glEncList(glEncList(glEncPtr(glEncObject[Address])))(v)', 'glNilable(glList(glNilable(glList(glPtr(glObject(AddressFromJson))))))(j)'],
      'maybeStamp': ['glEncPtr(func(v int) (any, error) { return back(v), nil })(v)', 'glPtr(func(v any) (int, error) { return conv(v), nil })(j)'],
      'stamps': ['glEncList(func(v int) (any, error) { return back(v), nil })(v)', 'glNilable(glList(func(v any) (int, error) { return conv(v), nil }))(j)'],
    });
  });

  test('a nullable type is never dereferenced without a guard, in every language', () {
    final parser = GLParser(scalarCodecs: {'Stamp': _codec})..parse(_schema);
    final field = parser.types['Holder']!.fields.firstWhere((f) => f.name.token == 'maybeAddress');
    expect(DartSerializer(parser, importPrefix: '').toJsonExpr(field.type, 'v'), contains('v?.'));
    expect(JavaSerializer(parser, importPrefix: '').toJsonExpr(field.type, 'v'), startsWith('v == null ? null :'));
    expect(PythonSerializer(parser, importPrefix: '').toJsonExpr(field.type, 'v'), startsWith('(None if v is None'));
  });
}
