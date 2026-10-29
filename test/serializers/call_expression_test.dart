import 'package:graphlink/src/code_gen_utils.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/kotlin_code_gen_utils.dart';
import 'package:graphlink/src/swift_code_gen_utils.dart';
import 'package:graphlink/src/typescript_code_gen_utils.dart';
import 'package:test/test.dart';

List<String> _lines(String s) => s.split('\n').map((l) => l.trim()).toList();

void main() {
  final noTrailingComma = <String, CodeGenUtilsBase>{
    'java': JavaCodeGenUtils(),
    'kotlin': KotlinCodeGenUtils(),
    'swift': SwiftCodeGenUtils(),
    'typescript': TypeScriptCodeGenUtils(),
  };

  for (final entry in noTrailingComma.entries) {
    group('${entry.key} callExpression', () {
      final u = entry.value;

      test('puts one argument per line with no trailing comma', () {
        expect(_lines(u.callExpression('run<T>', ['a', 'b'])), ['run<T>(', 'a,', 'b', ')']);
      });

      test('indents a multi-line argument as a whole', () {
        final out = u.callExpression('run', ['a', 'f(\n  x\n)']);
        expect(_lines(out), ['run(', 'a,', 'f(', 'x', ')', ')']);
      });

      test('emits empty parentheses without arguments', () {
        expect(u.callExpression('run', []), 'run()');
      });
    });
  }

  group('dart callExpression', () {
    final u = DartCodeGenUtils();

    test('keeps the trailing comma', () {
      expect(_lines(u.callExpression('Foo', ['a', 'b'])), ['Foo(', 'a,', 'b,', ')']);
    });

    test('emits empty parentheses without arguments', () {
      expect(u.callExpression('Foo', []), 'Foo()');
    });
  });
}
