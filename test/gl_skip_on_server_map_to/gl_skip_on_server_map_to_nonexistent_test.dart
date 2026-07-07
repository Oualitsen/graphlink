import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:test/test.dart';

void main() {
  test('mapTo referencing a nonexistent type (no batch mapping) throws', () {
    final g = GLParser(mode: CodeGenerationMode.server);
    expect(
      () => g.parse('''
        type Query { getUser: User }
        type User @glSkipOnServer(mapTo: "DoesNotExist") {
          name: String
        }
      '''),
      throwsA(isA<ParseException>()),
    );
  });

  test('mapTo referencing a nonexistent type WITH batch mapping throws', () {
    final g = GLParser(mode: CodeGenerationMode.server);
    expect(
      () => g.parse('''
        type ConversationUnread @glSkipOnServer(mapTo: "DoesNotExist", batch: true) {
          view: ConversationView!
          unread: Int!
        }

        type ConversationView {
          customName: String
        }

        type Query {
          getConversation: ConversationUnread
        }
      '''),
      throwsA(isA<ParseException>()),
    );
  });
}
