import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_serializer.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
import 'package:test/test.dart';

import 'error_test_support.dart';

GLParser _parser() => GLParser(
      naming: NamingConvention.typescript,
      parameterReservedWords: typescriptParameterReservedWords,
    )..parse(errorSchema);

String _error(String name) {
  final g = _parser();
  return TypeScriptSerializer(g, importPrefix: '').serializeErrorDefinition(g.errors[name]!);
}

void main() {
  group('TypeScript error class', () {
    test('extends the runtime base, imports it and restores the prototype', () {
      final out = _error('ArticleNotFound');
      expect(out, contains("import { GraphLinkDomainError } from '../client/graph-link-domain-error.js';"));
      expect(out, isNot(contains('graph-link-error')));
      final flatOut = flat(out);
      expect(flatOut, contains('export class ArticleNotFound extends GraphLinkDomainError {'));
      expect(flatOut, contains('Object.setPrototypeOf(this, ArticleNotFound.prototype);'));
      expect(flatOut, contains('super(init.message);'));
    });

    test('typed fields are readonly and assigned from the init object', () {
      final out = flat(_error('TitleTaken'));
      expect(out, contains('readonly title: string;'));
      expect(out, contains('readonly suggestions: string[] | null;'));
      expect(out, contains('constructor(init: { title: string; suggestions?: string[] | null; message?: string })'));
      expect(out, contains('this.title = init.title;'));
      expect(out, contains('this.suggestions = init.suggestions ?? null;'));
    });

    test('an error without fields only takes the optional message', () {
      expect(flat(_error('Forbidden')), contains('constructor(init: { message?: string })'));
    });

    test('fromJson decodes a record and takes the message', () {
      final out = flat(_error('TitleTaken'));
      expect(out, contains("static fromJson(json: Record<string, unknown>, message: string = ''): TitleTaken"));
      expect(out, contains('return new TitleTaken({'));
      expect(out, contains('message,'));
      expect(out, contains('title:'));
    });

    test('enum fields import their enum', () {
      final out = _error('Banned');
      expect(out, contains("from '../enums/reason.js';"));
    });

    test('it is a class, not an interface with a namespace', () {
      final out = _error('TitleTaken');
      expect(out, isNot(contains('export interface')));
      expect(out, isNot(contains('export namespace')));
    });
  });

  group('TypeScript runtime base', () {
    test('extends Error and holds only a message', () {
      final g = _parser();
      final model = TypeScriptClientSerializer(g, TypeScriptSerializer(g, importPrefix: '')).runtime.generateDomainErrorFile();
      final out = flat(model.body);
      expect(out, contains('export class GraphLinkDomainError extends Error {'));
      expect(out, contains("constructor(message: string = '')"));
      expect(out, contains('Object.setPrototypeOf(this, new.target.prototype);'));
      expect(out, isNot(contains('GraphLinkError')));
    });
  });
}
