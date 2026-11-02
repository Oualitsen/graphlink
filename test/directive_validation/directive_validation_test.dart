import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

const _base = 'type Product { id: ID! }\n';

void accepts(String schema) => expect(() => GLParser().parse('$_base$schema'), returnsNormally);

void rejects(String schema, Pattern message) => expect(
    () => GLParser().parse('$_base$schema'),
    throwsA(isA<ParseException>().having((e) => e.toString(), 'message', contains(message))));

void main() {
  group('undeclared directives', () {
    test('a directive that is not built in and not declared is an error naming the fix', () {
      rejects('type Query { p: Product @auth }', "Directive @auth is not declared: add 'directive @auth on ...'");
    });

    test('a declared user directive is accepted', () {
      accepts('directive @auth on FIELD_DEFINITION\ntype Query { p: Product @auth }');
    });

    test('built-in GraphLink and standard directives need no declaration', () {
      accepts('''
        scalar Upload @glUpload
        type Query { p: Product @glCache(ttl: 10) @glSkipOnServer }
        type Old { a: String @deprecated(reason: "x") }
      ''');
    });

    test('the error points at the directive', () {
      try {
        GLParser().parse('$_base\ntype Query { p: Product @nope }');
        fail('should throw');
      } on ParseException catch (e) {
        expect(e.toString(), contains('line'));
      }
    });
  });

  group('argument names', () {
    test('a misspelled argument of a built-in directive is an error listing the valid ones', () {
      rejects('type Query { p: Product @glRest(path: "/p", methdo: PUT) }', "Unknown argument 'methdo' of @glRest");
      rejects('type Query { p: Product @glRest(path: "/p", methdo: PUT) }', 'valid: path, method, contentType');
    });

    test('a directive without arguments says so', () {
      rejects('type Query { p: Product @glNoCache(x: 1) }', 'it takes no arguments');
    });

    test('a missing required argument is an error', () {
      rejects('input In @glMapsTo { a: String }\ntype Query { p: Product }', "Missing required argument 'type' of @glMapsTo");
      rejects('interface I @glRestDiscriminator { id: ID! }\ntype Query { p: Product }', "Missing required argument 'field'");
    });

    test('arguments of a user directive are checked against its declaration', () {
      const declaration = 'directive @auth(role: String!, level: Int) on FIELD_DEFINITION\n';
      accepts('${declaration}type Query { p: Product @auth(role: "admin", level: 2) }');
      rejects('${declaration}type Query { p: Product @auth(rol: "admin") }', "Unknown argument 'rol' of @auth");
      rejects('${declaration}type Query { p: Product @auth }', "Missing required argument 'role' of @auth");
    });

    test('a defaulted required-looking argument may be omitted', () {
      accepts('directive @tag(name: String! = "x") on FIELD_DEFINITION\ntype Query { p: Product @tag }');
    });
  });

  group('value kinds', () {
    test('wrong kinds are errors that name the argument and what is expected', () {
      rejects('type Query { p: Product @glRest(path: 5) }', "Argument 'path' of @glRest must be a string");
      rejects('type Query { p: Product @glRest(path: "/p", method: PATCHY) }', 'must be one of GET, POST, PUT, PATCH, DELETE');
      rejects('type Query { p: Product @glRest(path: "/p", response: XML) }', 'must be one of JSON, TEXT, BINARY');
      rejects('type Query { p: Product @glSkipOnServer(batch: "yes") }', "Argument 'batch' of @glSkipOnServer must be true or false");
      rejects('type Z @glExpand(depth: "deep") { a: String }\ntype Query { p: Product }', "Argument 'depth' of @glExpand must be an Int");
    });

    test('enum values may be written bare or quoted', () {
      accepts('type Query { p: Product @glRest(path: "/p", method: PUT) }');
      accepts('type Query { p: Product @glRest(path: "/p", method: "PUT") }');
    });

    test('a list argument checks its items', () {
      rejects('type Z @glEqualsHashcode(fields: [1]) { a: String }\ntype Query { p: Product }', 'must be a string');
      rejects('type Z @glEqualsHashcode(fields: "a") { a: String }\ntype Query { p: Product }', 'must be a list');
    });

    test('user directive arguments are checked by their declared scalar types', () {
      const declaration = 'directive @limit(max: Int, on: Boolean, label: String) on FIELD_DEFINITION\n';
      accepts('${declaration}type Query { p: Product @limit(max: 3, on: true, label: "x") }');
      rejects('${declaration}type Query { p: Product @limit(max: "3") }', 'must be an Int');
      rejects('${declaration}type Query { p: Product @limit(label: 3) }', 'must be a string');
    });

    test('@glCache accepts seconds or a duration string; its own checks keep their messages', () {
      accepts('type Query { p: Product @glCache(ttl: 30) }');
      accepts('type Query { p: Product @glCache(ttl: "30s") }');
    });
  });

  group('variables', () {
    test('a variable is accepted wherever a value is expected', () {
      accepts('''
        type Query { p: Product }
        query q(\$hide: Boolean!) { p { id @skip(if: \$hide) } }
      ''');
    });
  });

  group('redeclaring built-in directives', () {
    test('a compatible declaration is accepted', () {
      accepts('directive @glCache(ttl: Int, tags: [String!]) on FIELD_DEFINITION\ntype Query { p: Product @glCache(ttl: 5) }');
    });

    test('an annotation-style declaration with the annotation arguments is accepted', () {
      accepts('''
        directive @glRepository(glType: String!, glIdType: String!, glImport: String = "x", glClass: String = "Repo", glOnClient: Boolean = false) on INTERFACE
        interface Repo @glRepository(glType: "Product", glIdType: "String") { _: String }
        type Query { p: Product }
      ''');
    });

    test('a declaration with an argument the built-in does not have is an error', () {
      rejects('directive @glCache(ttl: Int, bogus: Int) on FIELD_DEFINITION\ntype Query { p: Product }',
          "@glCache is built in and has no argument 'bogus'");
    });
  });

  test('validation is skipped when parsing with validate: false', () {
    expect(() => GLParser().parse('type Query { p: String @nope }', validate: false), returnsNormally);
  });
}
