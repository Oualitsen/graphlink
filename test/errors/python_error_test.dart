import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_client_serializer.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:test/test.dart';

import 'error_test_support.dart';

GLParser _parser() => GLParser(naming: NamingConvention.python, reservedWords: pythonReservedWords)..parse(errorSchema);

String _error(String name) {
  final g = _parser();
  return PythonSerializer(g).serializeErrorDefinition(g.errors[name]!);
}

void main() {
  group('Python error class', () {
    test('is a plain class on the runtime base, not a pydantic model', () {
      final out = _error('ArticleNotFound');
      expect(out, contains('from ..client.graph_link_domain_error import GraphLinkDomainError'));
      expect(out, isNot(contains('GraphLinkError')));
      expect(lines(out), contains('class ArticleNotFound(GraphLinkDomainError):'));
      expect(out, isNot(contains('GraphLinkModel')));
      expect(out, isNot(contains('BaseModel')));
      expect(out, isNot(contains('ConfigDict')));
    });

    test('typed fields are annotated and set by a keyword-only constructor', () {
      final out = _error('TitleTaken');
      expect(lines(out), containsAll(['title: str', 'suggestions: Optional[List[str]]']));
      final flatOut = flat(out);
      expect(flatOut, contains('def __init__(self, *, title: str, suggestions: Optional[List[str]] = None, message: str = "") -> None:'));
      expect(flatOut, contains('super().__init__(message)'));
      expect(lines(out), containsAll(['self.title = title', 'self.suggestions = suggestions']));
    });

    test('an error without fields only has the message', () {
      final out = flat(_error('Forbidden'));
      expect(out, contains('def __init__(self, *, message: str = "") -> None:'));
    });

    test('from_json decodes a dict, checks required keys and takes the message', () {
      final out = _error('TitleTaken');
      final flatOut = flat(out);
      expect(lines(out), contains('@classmethod'));
      expect(flatOut, contains('def from_json(cls, json: Dict[str, Any], message: str = "") -> "TitleTaken":'));
      expect(flatOut, contains('if key not in json:'));
      expect(flatOut, contains('missing required field'));
      expect(flatOut, contains('title=json["title"]'));
      expect(flatOut, contains('message=message'));
    });

    test('enum fields are imported and decoded', () {
      final out = _error('Banned');
      expect(out, contains('from ..enums.reason import Reason'));
      expect(flat(out), contains('reason=Reason.from_json(json["reason"])'));
    });

    test('keyword-named fields get a safe identifier but keep their wire key', () {
      final g = GLParser(naming: NamingConvention.python, reservedWords: pythonReservedWords)
        ..parse('type Odd @glError { class: String! } type Query { a: String }');
      final out = PythonSerializer(g).serializeErrorDefinition(g.errors['Odd']!);
      expect(out, contains('class_: str'));
      expect(out, contains('json["class"]'));
    });
  });

  group('Python runtime base', () {
    test('extends Exception and holds only a message', () {
      final g = _parser();
      final model = PythonClientSerializer(g, PythonSerializer(g)).runtime.generateDomainErrorFile();
      final out = flat(model.body);
      expect(out, contains('class GraphLinkDomainError(Exception):'));
      expect(out, contains('message: str'));
      expect(out, contains('super().__init__(message)'));
      expect(out, isNot(contains('GraphLinkError')));
    });
  });
}
