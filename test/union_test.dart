import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/serializers/graphq_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:graphlink/src/model/gl_union.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  test("Union serialization", () {
    final GLGrammar g = GLGrammar();
    final serialzer = GLGraphqSerializer(g);
    var union = GLUnionDefinition("type".toToken(), false, ["User".toToken()], []);

    expect(serialzer.serializeUnionDefinition(union), "union type = User");
  });

  test("Union serialization with multiple types", () {
    final GLGrammar g = GLGrammar();
    final serialzer = GLGraphqSerializer(g);
    var union = GLUnionDefinition("type".toToken(), false, ["User".toToken(), "Client".toToken()], []);
    expect(serialzer.serializeUnionDefinition(union), "union type = User | Client");
  });

  test("Parse union 1", () {
    final GLGrammar g = GLGrammar();

    var parser = g.buildFrom<GLUnionDefinition>(g.unionDefinition().end());
    var result = parser.parse('''
    union MyTyp = User | Client
    ''');
    expect(result is Success, true);
    expect(result.value.token, "MyTyp");
    expect(result.value.typeNames.length, 2);
  });

  test("Parse union 2", () {
    final GLGrammar g = GLGrammar();

    var parser = g.buildFrom<GLUnionDefinition>(g.unionDefinition().end());
    var result = parser.parse('''
    union type = User
    ''');
    expect(result is Success, true);
    expect(result.value.token, "type");
    expect(result.value.typeNames.length, 1);
  });
}
