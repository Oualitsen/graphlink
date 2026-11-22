import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_annotation_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_resolver_binding_extension.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/python/python_annotation_serializer.dart';
import 'package:graphlink/src/serializers/typescript/typescript_annotation_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
directive @auth(role: String, glClass: String = "Auth", glImport: String = "import { Auth } from './auth'",
  glOnClient: Boolean = false, glOnServer: Boolean = true, glAnnotation: Boolean = true) on FIELD_DEFINITION

type Book { id: ID! }
type Query { book(id: ID!): Book @auth(role: "admin") }
''';

GLParser _parse() => GLParser(mode: CodeGenerationMode.server)..parse(_schema);

void main() {
  test('root fields bind by operation type, type fields as type fields', () {
    final g = _parse();
    expect(g.rootResolverBinding(GLQueryType.query, 'book'), const GLResolverBinding(GLResolverKind.query, 'book'));
    expect(g.rootResolverBinding(GLQueryType.mutation, 'add').kind, GLResolverKind.mutation);
    expect(g.rootResolverBinding(GLQueryType.subscription, 'ticks').kind, GLResolverKind.subscription);
    expect(g.typeFieldResolverBinding('books').kind, GLResolverKind.typeField);
  });

  test('an annotation becomes a generated decorator carrying its import', () {
    final g = _parse();
    final field = g.services.values.first.fields.first;
    g.convertAnnotationsToDecorators([field], TypeScriptAnnotationSerializer.serializeAnnotation);
    expect(g.decoratorImportsOf([field]), ["import { Auth } from './auth'"]);
  });

  test('the TypeScript renderer emits an object literal, the Python one keyword arguments', () {
    final g = _parse();
    final annotation = g.services.values.first.fields.first.getAnnotations(mode: CodeGenerationMode.server).single;
    expect(TypeScriptAnnotationSerializer.serializeAnnotation(annotation), '@Auth({ role: "admin" })');
    expect(PythonAnnotationSerializer.serializeAnnotation(annotation), '@Auth(role="admin")');
  });
}
