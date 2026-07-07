import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/java_spring_server_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
type Message { id: ID! content: String! }

type MessageRead @glSkipOnServer(mapTo: "Message", batch: true) {
    message: Message!
    read: Boolean!
}

type Query { getMessageReadList: [MessageRead] }
''';

void main() {
  test("batch mapping result map is keyed by the source parent, not the domain object", () {
    final g = GLParser(mode: CodeGenerationMode.server);
    g.parse(_schema);

    final serializer = JavaSpringServerSerializer(g, packageName: "");
    final ctrl = g.controllers[g.controllerMappingName("MessageRead")]!;
    final out = serializer.serializeController(ctrl);

    // Spring's @BatchMapping iterates the source parents it passed in and does
    // map.get(source). The sources arrive as Map<String, Object>, so the
    // returned map must be keyed by Map<String, Object>, not the domain Message.
    expect(out, contains("CompletableFuture<Map<Map<String, Object>, Boolean>> read("));

    // Body must call the service once, then re-key its Map<Message, Boolean>
    // result onto the source list via index correlation.
    expect(
        out,
        stringContainsInOrder([
          "__gl_serviceResult__ = ",
          "for (int __gl_i__ = 0; __gl_i__ < valueAsMap.size(); __gl_i__++)",
          "result.put(valueAsMap.get(__gl_i__), __gl_serviceResult__.get(value.get(__gl_i__)))",
        ]));

    // The old broken pattern (keying by the reconstructed domain object) is gone.
    expect(out, isNot(contains("result.put(entry.getKey()")));
    expect(out, isNot(contains(".entrySet()")));
  });
}
