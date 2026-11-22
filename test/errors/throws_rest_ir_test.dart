import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_error_extension.dart';
import 'package:test/test.dart';

const _base = '''
type Product { id: ID! name: String }
type NotFound @glError(status: 404) { id: ID }
type Gone @glError(status: 410) { }
type Coded @glError(status: 409, value: "CONFLICT") { reason: String }
type ByField @glError(field: "error.kind", value: "x") { }
type Plain @glError { }
type Other @glError { }
''';

GLParser _parse(String body) => GLParser()..parse('$_base$body');

void _fails(String body, Pattern message) {
  expect(() => _parse(body), throwsA(isA<ParseException>().having((e) => e.toString(), 'message', contains(message))));
}

void main() {
  group('REST errors', () {
    test('a REST operation lists the errors it throws', () {
      final g = _parse('type Query { product(id: ID!): Product @glRest(path: "/p/{id}") @glThrows(errors: [NotFound, Gone]) }');
      final op = g.restOperations.values.single;
      expect(g.restThrownErrorsOf(op).map((e) => e.name), ['NotFound', 'Gone']);
    });

    test('a REST operation without the directive throws nothing', () {
      final g = _parse('type Query { product(id: ID!): Product @glRest(path: "/p/{id}") }');
      expect(g.restThrownErrorsOf(g.restOperations.values.single), isEmpty);
    });

    test('a status alone decides, no body discriminator', () {
      final g = _parse('type Query { p: Product @glRest(path: "/p") @glThrows(errors: [Gone]) }');
      final gone = g.errors['Gone']!;
      expect(gone.matchesStatusOnly, isTrue);
      expect(gone.restField, isNull);
    });

    test('without a status the discriminator is the top level code', () {
      final g = _parse('type Query { p: Product @glRest(path: "/p") @glThrows(errors: [Plain]) }');
      expect(g.errors['Plain']!.restField, ['code']);
    });

    test('an explicit value keeps the default REST field next to the status', () {
      final g = _parse('type Query { p: Product @glRest(path: "/p") @glThrows(errors: [Coded]) }');
      final coded = g.errors['Coded']!;
      expect(coded.matchesStatusOnly, isFalse);
      expect(coded.restField, ['code']);
      expect(coded.value, 'CONFLICT');
    });

    test('an explicit field is resolved against the body', () {
      final g = _parse('type Query { p: Product @glRest(path: "/p") @glThrows(errors: [ByField]) }');
      expect(g.errors['ByField']!.restField, ['error', 'kind']);
    });

    test('two status-only errors with the same status are ambiguous', () {
      _fails('''
        type Gone2 @glError(status: 410) { }
        type Query { p: Product @glRest(path: "/p") @glThrows(errors: [Gone, Gone2]) }
      ''', 'ambiguous');
    });

    test('the same status with different discriminators is fine', () {
      final g = _parse('''
        type Dup @glError(status: 409, value: "OTHER") { }
        type Query { p: Product @glRest(path: "/p") @glThrows(errors: [Coded, Dup]) }
      ''');
      expect(g.restThrownErrorsOf(g.restOperations.values.single).length, 2);
    });

    test('two errors with the same default code and no status are ambiguous', () {
      _fails('''
        type Same @glError(value: "Plain") { }
        type Query { p: Product @glRest(path: "/p") @glThrows(errors: [Plain, Same]) }
      ''', 'ambiguous');
    });

    test('REST errors are not compared on the GraphQL path', () {
      final g = _parse('type Query { p: Product @glRest(path: "/p") @glThrows(errors: [Plain, Other]) }');
      expect(g.restThrownErrorsOf(g.restOperations.values.single).length, 2);
    });
  });
}
