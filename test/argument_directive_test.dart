import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  test("test argument with directives", () {
    final GLGrammar g = GLGrammar();

    var parser = g.buildFrom(g
        .field(
          acceptsArguments: true,
          canBeInitialized: true,
        )
        .end());
    var parsed = parser.parse("findById(id: ID! @depricated): String!");
    var directive = parsed.value.arguments.first.getDirectiveByName("@depricated");
    expect(directive, isNotNull);
  });
}
