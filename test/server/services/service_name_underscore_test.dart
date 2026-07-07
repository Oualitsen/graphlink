import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  test('leading-underscore scalar op yields a clean service name', () {
    final g = GLParser(mode: CodeGenerationMode.server);
    g.parse('type Query { _status: String! }');

    expect(g.services.containsKey('StatusService'), isTrue);
    expect(g.services.keys.any((k) => k.startsWith('_')), isFalse);
  });
}
