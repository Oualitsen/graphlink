import 'package:graphlink/src/swift_code_gen_utils.dart';
import 'package:test/test.dart';

void main() {
  final u = SwiftCodeGenUtils();

  test('a method is not throwing by default', () {
    expect(u.method(returnType: 'Int', methodName: 'f', statements: ['return 1']), startsWith('func f() -> Int {'));
    expect(u.createMethod(returnType: 'Int', methodName: 'f', statements: ['return 1']), startsWith('func f() -> Int {'));
  });

  test('method can be marked throws', () {
    final out = u.method(returnType: 'Int', methodName: 'f', arguments: ['_ a: Int'], statements: ['return a'], throws: true);
    expect(out, startsWith('func f(_ a: Int) throws -> Int {'));
  });

  test('createMethod can be marked throws', () {
    final out = u.createMethod(returnType: 'Pet', methodName: 'fromJson', arguments: ['_ map: [String: Any?]'], statements: ['return x'], throws: true);
    expect(out, startsWith('func fromJson(_ map: [String: Any?]) throws -> Pet {'));
  });

  test('throws without a return type', () {
    final out = u.method(returnType: 'Void', methodName: 'run', statements: ['try go()'], throws: true);
    expect(out, startsWith('func run() throws {'));
  });
}
