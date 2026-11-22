import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
import 'package:test/test.dart';

import 'error_test_support.dart';

const _schema = '''
type Item { id: ID! }
type Conflict @glError(status: 409, value: "CONFLICT") { reason: String! }
type Forbidden @glError(field: "extensions.kind", value: "forbidden") { }
type Query { item(id: ID!): Item! @glThrows(errors: [Conflict, Forbidden]) }
''';

GLParser _parse(NamingConvention naming, {Set<String> reserved = const {}}) =>
    GLParser(mode: CodeGenerationMode.server, naming: naming, reservedWords: reserved)..parse(_schema);

void main() {
  test('TypeScript: the server class imports the base next to it and carries its wire', () {
    final g = _parse(NamingConvention.typescript);
    final out = flat(TypeScriptSerializer(g, importPrefix: '').serializeErrorDefinition(g.errors['Conflict']!));
    expect(out, contains("from './graph-link-domain-error.js'"));
    expect(out, contains('static readonly wire = { field: ["extensions", "code"], restField: ["code"], value: "CONFLICT", status: 409 };'));
    expect(out, contains('toJson(): Record<string, unknown> { return { "reason": this.reason,'));
  });

  test('TypeScript: a status-only error has no REST discriminator', () {
    final g = GLParser(mode: CodeGenerationMode.server)
      ..parse('type G @glError(status: 410) { } type Query { a: String @glThrows(errors: [G]) }');
    final out = flat(TypeScriptSerializer(g, importPrefix: '').serializeErrorDefinition(g.errors['G']!));
    expect(out, contains('restField: null'));
  });

  test('TypeScript: a client class has no wire', () {
    final g = GLParser()..parse(_schema);
    final out = TypeScriptSerializer(g, importPrefix: '').serializeErrorDefinition(g.errors['Conflict']!);
    expect(out, isNot(contains('wire')));
    expect(out, contains("'../client/graph-link-domain-error.js'"));
  });

  test('Python: the server class has to_json and wire and imports the runtime', () {
    final g = _parse(NamingConvention.python);
    final out = flat(PythonSerializer(g, runtimeDir: 'runtime').serializeErrorDefinition(g.errors['Conflict']!));
    expect(out, contains('from ..runtime.graph_link_domain_error import GraphLinkDomainError'));
    expect(out, contains('wire = {"field": ["extensions", "code"], "rest_field": ["code"], "value": "CONFLICT", "status": 409}'));
    expect(out, contains('def to_json(self) -> Dict[str, Any]: return {"reason": self.reason}'));
  });

  test('Java: the server class overrides the wire of the abstract base from the errors package', () {
    final g = _parse(NamingConvention.java, reserved: javaReservedWords);
    final out = flat(JavaSerializer(g, importPrefix: 'com.example').serializeErrorDefinition(g.errors['Conflict']!));
    expect(out, contains('import com.example.errors.GraphLinkDomainError;'));
    expect(out, contains('public Map<String, Object> toJson() {'));
    expect(out, contains('map.put("reason", reason);'));
    expect(out, contains('public List<String> wireField() { return Arrays.asList("extensions", "code"); }'));
    expect(out, contains('public Integer wireStatus() { return 409; }'));
  });

  test('Kotlin: the server class overrides the wire of the abstract base', () {
    final g = _parse(NamingConvention.kotlin, reserved: kotlinReservedWords);
    final out = flat(KotlinSerializer(g, importPrefix: 'com.example').serializeErrorDefinition(g.errors['Conflict']!));
    expect(out, contains('import com.example.errors.GraphLinkDomainError'));
    expect(out, contains('override fun toJson(): Map<String, Any?> = mapOf("reason" to reason)'));
    expect(out, contains('override fun wireStatus(): Int? = 409'));
  });
}
