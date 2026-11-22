import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/client_serializers/go/go_client_serializer.dart';
import 'package:graphlink/src/serializers/go/go_serializer.dart';
import 'package:test/test.dart';

import 'error_test_support.dart';

GLParser _parser() => GLParser(naming: NamingConvention.go, reservedWords: goReservedWords)..parse(errorSchema);

String _error(String name) {
  final g = _parser();
  return GoSerializer(g, packageName: 'generated').serializeErrorDefinition(g.errors[name]!);
}

void main() {
  group('Go error value', () {
    test('embeds the runtime base and carries typed fields', () {
      final out = _error('TitleTaken');
      expect(out, startsWith('package generated'));
      expect(lines(out), containsAllInOrder([
        'type TitleTaken struct {',
        'GraphLinkDomainError',
        'Title string `json:"title"`',
        'Suggestions []string `json:"suggestions"`',
        '}',
      ]));
    });

    test('a pointer to it is an error and names the type', () {
      final out = flat(_error('TitleTaken'));
      expect(out, contains('func (v *TitleTaken) Error() string {'));
      expect(out, contains('if v.Message == "" { return "TitleTaken" }'));
      expect(out, contains('return "TitleTaken: " + v.Message'));
    });

    test('FromJson decodes a map, reports field errors and takes the message', () {
      final out = flat(_error('TitleTaken'));
      expect(out, contains('func TitleTakenFromJson(m map[string]any, message string) (*TitleTaken, error) {'));
      expect(out, contains('v := &TitleTaken{GraphLinkDomainError: GraphLinkDomainError{Message: message}}'));
      expect(out, contains('if v.Title, err = glString(m["title"]); err != nil { return nil, glFieldError("TitleTaken", "title", err) }'));
      expect(out, contains('return v, nil'));
    });

    test('an error without fields has no decoding variable', () {
      final out = flat(_error('Forbidden'));
      expect(out, contains('type Forbidden struct { GraphLinkDomainError }'));
      expect(out, isNot(contains('var err error')));
    });

    test('enum fields use the enum decoder', () {
      expect(flat(_error('Banned')), contains('v.Reason, err = ReasonFromJson(m["reason"])'));
    });
  });

  group('Go runtime base', () {
    test('is a struct holding a message that implements error', () {
      final g = _parser();
      final model = GoClientSerializer(g, GoSerializer(g)).generateDomainErrorFile();
      final out = flat(model.body);
      expect(out, contains('type GraphLinkDomainError struct {'));
      expect(out, contains('Message string'));
      expect(out, contains('func (e *GraphLinkDomainError) Error() string {'));
      expect(out, contains('return e.Message'));
      expect(out, isNot(contains('GraphLinkError')));
    });
  });
}
