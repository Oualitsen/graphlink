import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/swift/swift_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
  input Ping { n: Int! pong: Pong }
  input Pong { n: Int! ping: Ping }
  input Node { value: Int! next: Node }
  input Tree { value: Int! children: [Tree!] }
  type Leaf { id: ID! parent: Leaf }
  type Query { a(p: Ping, n: Node, t: Tree): Leaf }
''';

GLParser _parse() => GLParser()..parse(_schema);

String _input(String name) {
  final g = _parse();
  return SwiftSerializer(g, importPrefix: 'G').serializeInputDefinition(g.inputs[name]!);
}

void main() {
  test('mutually recursive inputs store the cycle through a box', () {
    final out = _input('Ping');
    expect(out, contains('private let _pong: GLIndirect<Pong>?'));
    expect(out, contains('public var pong: Pong? { _pong?.value }'));
    expect(out, contains('self._pong = pong.map(GLIndirect.init)'));
    expect(out, contains('private final class GLIndirect<T>'));
  });

  test('both sides of the cycle are boxed', () {
    expect(_input('Pong'), contains('GLIndirect<Ping>?'));
  });

  test('a self-referencing input is boxed', () {
    expect(_input('Node'), contains('private let _next: GLIndirect<Node>?'));
  });

  test('recursion through a list needs no box', () {
    final out = _input('Tree');
    expect(out, contains('public let children: [Tree]?'));
    expect(out, isNot(contains('GLIndirect')));
  });

  test('a self-referencing type is boxed too', () {
    final g = _parse();
    final out = SwiftSerializer(g, importPrefix: 'G').serializeTypeDefinition(g.types['Leaf']!);
    expect(out, contains('GLIndirect<Leaf>?'));
  });

  test('a field outside any cycle is stored as usual', () {
    expect(_input('Ping'), contains('public let n: Int'));
  });
}
