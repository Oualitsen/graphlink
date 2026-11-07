import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/go/go_serializer.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
  input Inner { n: Int = 1 label: String = "d" tags: [String!] = ["a"] }
  input Outer { inner: Inner = {n: 5} empty: Inner = {} }
  type Query { f(a: Inner = {n: 9}, b: Inner = {}, c: Outer = {}): String }
''';

void main() {
  late GLParser g;
  late TypeScriptSerializer ts;
  setUp(() {
    g = GLParser()..parse(_schema);
    ts = TypeScriptSerializer(g, importPrefix: '');
  });

  dynamic argument(String name) =>
      g.types['Query']!.fields.single.arguments.firstWhere((a) => a.token == name);

  String literal(String name) {
    final arg = argument(name);
    return ts.serializeDefaultLiteral(arg.type, arg.defaultValue!.value);
  }

  test('TypeScript: the defaults of the input type fill the members a default object leaves out', () {
    expect(literal('a'), '{ n: 9, label: "d", tags: ["a"] }');
  });

  test('TypeScript: an empty default object takes every default', () {
    expect(literal('b'), '{ n: 1, label: "d", tags: ["a"] }');
  });

  test('TypeScript: nested input defaults are completed too', () {
    expect(literal('c'),
        '{ inner: { n: 5, label: "d", tags: ["a"] }, empty: { n: 1, label: "d", tags: ["a"] } }');
  });

  test('Go: the defaults of the input type fill the members a default object leaves out', () {
    final go = GoSerializer(g, packageName: 'generated');
    final arg = argument('a');
    expect(go.serializeDefaultLiteral(arg.type, arg.defaultValue!.value),
        'Ptr[Inner](Inner{n: Ptr[int](9), label: Ptr[string]("d"), tags: []string{"a"}})');
  });
}
