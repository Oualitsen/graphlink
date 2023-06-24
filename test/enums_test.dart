import 'package:test/test.dart';
import 'package:retrofit_graphql/graphql_parser/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

final GQGrammar g = GQGrammar();

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
    expect(result.isSuccess, true);
  });
}
