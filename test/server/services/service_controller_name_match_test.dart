import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  test('controller invokes the service using the method the interface declares', () {
    // Same knobs the Spring/Java server sets (grammar_factory): java naming
    // convention + non-empty reserved words.
    final g = GLParser(
      mode: CodeGenerationMode.server,
      naming: NamingConvention.java,
      reservedWords: const {'class', 'int', 'return'},
    );
    g.parse('type Query { _status: String! }');

    final serviceField =
        g.services['StatusService']!.getFieldByName('_status')!;
    final controllerField =
        g.controllers['StatusServiceController']!.getFieldByName('_status')!;

    // The controller body calls `service.<controllerField.codeName>()`, so it
    // must match the interface method `<serviceField.codeName>()`.
    expect(controllerField.codeName, equals(serviceField.codeName));
  });
}
