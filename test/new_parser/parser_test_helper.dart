import 'package:graphlink/src/gl_grammar.dart';
import 'package:graphlink/src/model/new_parser/gl_lexer.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/language.dart';

GLGrammar parse(String source) {
  final grammar = GLGrammar(mode: CodeGenerationMode.server);
  final lexer = GLLexer(source);
  final tokens = lexer.tokenize();
  final parser = GLParser(tokens, lexer, grammar);
  parser.doParse(validate: false);
  return grammar;
}
