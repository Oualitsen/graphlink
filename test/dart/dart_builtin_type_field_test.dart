import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  test('a field named after a dart:core type is sanitized (int -> int_)', () {
    final g = GLParser(
      naming: NamingConvention.dart,
      reservedWords: dartReservedWords,
    );
    g.parse('type Query { thing: T } type T { int: Int! bool: Boolean! }');

    final t = g.types['T']!;
    expect(t.getFieldByName('int')!.codeName, 'int_');
    expect(t.getFieldByName('bool')!.codeName, 'bool_');
  });
}
