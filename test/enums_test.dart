import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

final GLGrammar g = GLGrammar();

void main() {
  test("Enum  test", () {
    var parser = g.buildFrom(g.enumDefinition().end());
    var result = parser.parse('''
      
      enum Gender @sikp(if: true) {
        "Documenation 1"
        Male 
        """ 
        Documenation 1
        
        """
        Female
      }
    
    ''');
    expect(result is Success, true);
  });
}
