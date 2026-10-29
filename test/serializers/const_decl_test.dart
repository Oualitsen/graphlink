import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/kotlin_code_gen_utils.dart';
import 'package:graphlink/src/swift_code_gen_utils.dart';
import 'package:graphlink/src/typescript_code_gen_utils.dart';
import 'package:test/test.dart';

void main() {
  test('typescript', () {
    final u = TypeScriptCodeGenUtils();
    expect(u.constDecl('a', '1'), 'const a = 1;');
    expect(u.constDecl('a', '{}', type: 'Record<string, unknown>'), 'const a: Record<string, unknown> = {};');
  });

  test('dart', () {
    final u = DartCodeGenUtils();
    expect(u.constDecl('a', '1'), 'final a = 1;');
    expect(u.constDecl('a', '{}', type: 'Map<String, int>'), 'final Map<String, int> a = {};');
  });

  test('java', () {
    final u = JavaCodeGenUtils();
    expect(u.constDecl('a', '1'), 'final var a = 1;');
    expect(u.constDecl('a', 'new X()', type: 'X'), 'final X a = new X();');
  });

  test('kotlin', () {
    final u = KotlinCodeGenUtils();
    expect(u.constDecl('a', '1'), 'val a = 1');
    expect(u.constDecl('a', 'mapOf()', type: 'Map<String, Any?>'), 'val a: Map<String, Any?> = mapOf()');
  });

  test('swift', () {
    final u = SwiftCodeGenUtils();
    expect(u.constDecl('a', '1'), 'let a = 1');
    expect(u.constDecl('a', '[]', type: '[String]'), 'let a: [String] = []');
  });
}
