import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_lexer.dart';
import 'package:graphlink/src/model/new_parser/gl_lexter_token.dart';
import 'package:graphlink/src/model/new_parser/gl_token_type.dart';
import 'package:test/test.dart';

// Helper: tokenize and return all tokens except EOF
List<GLLexerToken> lex(String source) {
  final tokens = GLLexer(source).tokenize();
  return tokens.where((t) => t.type != GLTokenType.eof).toList();
}

void main() {
  group('GLLexer — whitespace skipping (EOF offset)', () {
    test('empty string produces EOF at offset 0', () {
      final lexer = GLLexer('');
      final tokens = lexer.tokenize();
      expect(tokens.length, 1);
      expect(tokens[0].type, GLTokenType.eof);
      expect(tokens[0].offset, 0);
    });

    test('only spaces', () {
      final lexer = GLLexer('   ');
      final tokens = lexer.tokenize();
      expect(tokens[0].type, GLTokenType.eof);
      expect(tokens[0].offset, 3);
    });

    test('tabs and commas are treated as whitespace', () {
      final lexer = GLLexer('\t,,\t');
      final tokens = lexer.tokenize();
      expect(tokens[0].type, GLTokenType.eof);
      expect(tokens[0].offset, 4);
    });

    test('single newline', () {
      final lexer = GLLexer('\n');
      final tokens = lexer.tokenize();
      expect(tokens[0].type, GLTokenType.eof);
      expect(tokens[0].offset, 1);
    });

    test('mixed spaces and newlines', () {
      final lexer = GLLexer('  \n  \n  ');
      final tokens = lexer.tokenize();
      expect(tokens[0].type, GLTokenType.eof);
      expect(tokens[0].offset, 8);
    });

    test('windows line endings \\r\\n', () {
      final lexer = GLLexer('  \r\n  ');
      final tokens = lexer.tokenize();
      expect(tokens[0].type, GLTokenType.eof);
      expect(tokens[0].offset, 6);
    });
  });

  group('GLLexer — comment skipping (EOF offset)', () {
    test('comment only, no trailing newline', () {
      final lexer = GLLexer('# this is a comment');
      final tokens = lexer.tokenize();
      expect(tokens[0].type, GLTokenType.eof);
      expect(tokens[0].offset, 19);
    });

    test('comment followed by newline', () {
      final lexer = GLLexer('# comment\n');
      final tokens = lexer.tokenize();
      expect(tokens[0].type, GLTokenType.eof);
      expect(tokens[0].offset, 10);
    });

    test('multiple comment lines', () {
      final lexer = GLLexer('# line 1\n# line 2\n');
      final tokens = lexer.tokenize();
      expect(tokens[0].type, GLTokenType.eof);
      expect(tokens[0].offset, 18);
    });

    test('spaces before comment', () {
      final lexer = GLLexer('   # comment\n   ');
      final tokens = lexer.tokenize();
      expect(tokens[0].type, GLTokenType.eof);
      expect(tokens[0].offset, 16);
    });
  });

  group('GLLexer — punctuation', () {
    test('each single-char punctuation token', () {
      final tokens = lex('{ } ( ) [ ] : ! = | @ &');
      expect(tokens.map((t) => t.type).toList(), [
        GLTokenType.openBrace,
        GLTokenType.closeBrace,
        GLTokenType.openParen,
        GLTokenType.closeParen,
        GLTokenType.openBracket,
        GLTokenType.closeBracket,
        GLTokenType.colon,
        GLTokenType.bang,
        GLTokenType.equals,
        GLTokenType.pipe,
        GLTokenType.at,
        GLTokenType.amp,
      ]);
    });

    test('punctuation values are correct', () {
      final tokens = lex('{ }');
      expect(tokens[0].value, '{');
      expect(tokens[1].value, '}');
    });

    test('punctuation offsets are correct', () {
      final tokens = lex('{ }');
      expect(tokens[0].offset, 0);
      expect(tokens[1].offset, 2);
    });
  });

  group('GLLexer — spread', () {
    test('spread token', () {
      final tokens = lex('...');
      expect(tokens.length, 1);
      expect(tokens[0].type, GLTokenType.spread);
      expect(tokens[0].value, '...');
      expect(tokens[0].offset, 0);
    });

    test('spread inside expression', () {
      final tokens = lex('{...}');
      expect(tokens[1].type, GLTokenType.spread);
      expect(tokens[1].offset, 1);
    });

    test('invalid spread throws', () {
      expect(() => lex('..'), throwsA(isA<ParseException>()));
    });

    test('single dot throws', () {
      expect(() => lex('.'), throwsA(isA<ParseException>()));
    });
  });

  group('GLLexer — strings', () {
    test('simple string', () {
      final tokens = lex('"hello"');
      expect(tokens[0].type, GLTokenType.string);
      expect(tokens[0].value, '"hello"');
      expect(tokens[0].offset, 0);
    });

    test('string with escaped quote', () {
      final tokens = lex(r'"say \"hi\""');
      expect(tokens[0].type, GLTokenType.string);
      expect(tokens[0].value, '"say "hi""');
    });

    test('unterminated string throws', () {
      expect(() => lex('"hello'), throwsA(isA<ParseException>()));
    });

    test('string with newline throws', () {
      expect(() => lex('"hello\nworld"'), throwsA(isA<ParseException>()));
    });

    test('block string', () {
      final tokens = lex('"""hello world"""');
      expect(tokens[0].type, GLTokenType.blockString);
      expect(tokens[0].value, '"""hello world"""');
      expect(tokens[0].offset, 0);
    });

    test('block string with newlines', () {
      final tokens = lex('"""line1\nline2"""');
      expect(tokens[0].type, GLTokenType.blockString);
      expect(tokens[0].value, '"""line1\nline2"""');
    });

    test('block string with inner quotes', () {
      final tokens = lex('"""say "hi" to me"""');
      expect(tokens[0].type, GLTokenType.blockString);
    });

    test('unterminated block string throws', () {
      expect(() => lex('"""hello'), throwsA(isA<ParseException>()));
    });
  });

  group('GLLexer — numbers', () {
    test('integer', () {
      final tokens = lex('42');
      expect(tokens[0].type, GLTokenType.int_);
      expect(tokens[0].value, '42');
      expect(tokens[0].offset, 0);
    });

    test('negative integer', () {
      final tokens = lex('-7');
      expect(tokens[0].type, GLTokenType.int_);
      expect(tokens[0].value, '-7');
    });

    test('float', () {
      final tokens = lex('3.14');
      expect(tokens[0].type, GLTokenType.float_);
      expect(tokens[0].value, '3.14');
    });

    test('float with exponent', () {
      final tokens = lex('3.14e10');
      expect(tokens[0].type, GLTokenType.float_);
      expect(tokens[0].value, '3.14e10');
    });

    test('float with negative exponent', () {
      final tokens = lex('3e-12');
      expect(tokens[0].type, GLTokenType.float_);
      expect(tokens[0].value, '3e-12');
    });

    test('float with uppercase E', () {
      final tokens = lex('2.5E3');
      expect(tokens[0].type, GLTokenType.float_);
      expect(tokens[0].value, '2.5E3');
    });

    test('number offset is at start', () {
      final tokens = lex('  42');
      expect(tokens[0].offset, 2);
    });
  });

  group('GLLexer — identifiers and keywords', () {
    test('simple identifier', () {
      final tokens = lex('foo');
      expect(tokens[0].type, GLTokenType.identifier);
      expect(tokens[0].value, 'foo');
      expect(tokens[0].offset, 0);
    });

    test('identifier with underscore and digits', () {
      final tokens = lex('_foo_42');
      expect(tokens[0].type, GLTokenType.identifier);
      expect(tokens[0].value, '_foo_42');
    });

    test('all keywords resolve correctly', () {
      final cases = {
        'type': GLTokenType.kwType,
        'input': GLTokenType.kwInput,
        'interface': GLTokenType.kwInterface,
        'enum': GLTokenType.kwEnum,
        'scalar': GLTokenType.kwScalar,
        'union': GLTokenType.kwUnion,
        'directive': GLTokenType.kwDirective,
        'fragment': GLTokenType.kwFragment,
        'query': GLTokenType.kwQuery,
        'mutation': GLTokenType.kwMutation,
        'subscription': GLTokenType.kwSubscription,
        'extend': GLTokenType.kwExtend,
        'schema': GLTokenType.kwSchema,
        'on': GLTokenType.kwOn,
        'implements': GLTokenType.kwImplements,
        'repeatable': GLTokenType.kwRepeatable,
        'true': GLTokenType.kwTrue,
        'false': GLTokenType.kwFalse,
        'null': GLTokenType.kwNull,
      };
      for (final entry in cases.entries) {
        final tokens = lex(entry.key);
        expect(tokens[0].type, entry.value,
            reason: "'${entry.key}' should be ${entry.value}");
      }
    });

    test('keyword-like prefix is an identifier', () {
      final tokens = lex('types');
      expect(tokens[0].type, GLTokenType.identifier);
    });

    test('invalid character throws', () {
      expect(() => lex('\$'), throwsA(isA<ParseException>()));
    });
  });

  group('GLLexer — mixed input', () {
    test('simple type definition tokens', () {
      final tokens = lex('type Foo { bar: String }');
      expect(tokens.map((t) => t.type).toList(), [
        GLTokenType.kwType,
        GLTokenType.identifier,
        GLTokenType.openBrace,
        GLTokenType.identifier,
        GLTokenType.colon,
        GLTokenType.identifier,
        GLTokenType.closeBrace,
      ]);
    });

    test('tokens after comment are correct', () {
      final tokens = lex('# comment\ntype');
      expect(tokens[0].type, GLTokenType.kwType);
    });

    test('multiple tokens have correct offsets', () {
      final tokens = lex('foo bar');
      expect(tokens[0].offset, 0);
      expect(tokens[1].offset, 4);
    });
  });

  group('GLLexer — locationOf()', () {
    test('offset 0 is line 1 column 1', () {
      final lexer = GLLexer('   ');
      lexer.tokenize();
      final loc = lexer.locationOf(0);
      expect(loc.line, 1);
      expect(loc.column, 1);
    });

    test('mid-line offset gives correct column', () {
      // "   " — offset 2 is line 1, col 3
      final lexer = GLLexer('   ');
      lexer.tokenize();
      final loc = lexer.locationOf(2);
      expect(loc.line, 1);
      expect(loc.column, 3);
    });

    test('offset on second line after single newline', () {
      // "  \n  " — offset 3 is line 2, col 1
      final lexer = GLLexer('  \n  ');
      lexer.tokenize();
      final loc = lexer.locationOf(3);
      expect(loc.line, 2);
      expect(loc.column, 1);
    });

    test('offset on third line', () {
      // " \n \n " — offset 4 is line 3, col 1
      final lexer = GLLexer(' \n \n ');
      lexer.tokenize();
      final loc = lexer.locationOf(4);
      expect(loc.line, 3);
      expect(loc.column, 1);
    });

    test('column is correct on second line', () {
      // " \n   " — offset 4 is line 2, col 3
      final lexer = GLLexer(' \n   ');
      lexer.tokenize();
      final loc = lexer.locationOf(4);
      expect(loc.line, 2);
      expect(loc.column, 3);
    });

    test('windows \\r\\n counts as one line', () {
      // "  \r\n  " — offset 4 is line 2, col 1
      final lexer = GLLexer('  \r\n  ');
      lexer.tokenize();
      final loc = lexer.locationOf(4);
      expect(loc.line, 2);
      expect(loc.column, 1);
    });

    test('offset after comment line is on next line', () {
      // "# hi\n  " — offset 5 is line 2, col 1
      final lexer = GLLexer('# hi\n  ');
      lexer.tokenize();
      final loc = lexer.locationOf(5);
      expect(loc.line, 2);
      expect(loc.column, 1);
    });
  });
}
