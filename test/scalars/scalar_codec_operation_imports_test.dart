import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_scalar_codec_extension.dart';
import 'package:graphlink/src/model/scalar_codec.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/go/go_client_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_client_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/swift/swift_client_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_serializer.dart';
import 'package:graphlink/src/serializers/gl_client_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/go/go_serializer.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:graphlink/src/serializers/swift/swift_serializer.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
import 'package:graphlink/src/serializers/dart/dart_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
scalar Stamp

type Query { eventsSince(at: Stamp!): [String!]! }
type Mutation { touch(at: Stamp!): Boolean }
type Subscription { ticks(since: Stamp!): String! }
''';

class _Target {
  final String import;
  final String expected;
  final GLClientSerializer Function(GLParser) client;
  final GLSerializer Function(GLParser) ser;
  final String preamble;
  final Map<String, GLClassModel?> Function(GLClientSerializer)? files;
  _Target({required this.import, required this.expected, required this.client, required this.ser, this.preamble = '', this.files});
}

void main() {
  test('Dart: an operation file imports the codec of its argument', () {
    final codec = GLScalarCodec.fromConfig('Stamp', {
      'type': 'DateTime',
      'import': 'package:intl/intl.dart',
      'fromJson': 'DateFormat.yMd().parse({} as String)',
      'toJson': 'DateFormat.yMd().format({})',
    });
    final g = GLParser(autoGenerateQueries: true, generateAllFieldsFragments: true, scalarCodecs: {'Stamp': codec})..parse(_schema);
    final serializer = DartSerializer(g, importPrefix: '', typeMapOverrides: {'Stamp': codec.type});
    final client = DartClientSerializer(g, serializer);

    final files = {
      'queries': serializer.serializeGlClass(client.getQueriesClass()!),
      'mutations': serializer.serializeGlClass(client.getMutationsClass()!),
      'subscriptions': serializer.serializeGlClass(client.getSubscriptionsClass()!),
    };
    for (final entry in files.entries) {
      expect(entry.value, contains('DateFormat.yMd().format('), reason: '${entry.key} file encodes the argument');
      expect(entry.value, contains("import 'package:intl/intl.dart';"), reason: '${entry.key} file needs the codec import');
    }
  });

  final others = <String, _Target>{
    'Java': _Target(
      import: 'java.time.OffsetDateTime',
      expected: 'import java.time.OffsetDateTime;',
      preamble: '$javaJsonEncoderDecorder\n$javaClientAdapterNoParamSync\n$javaGraphLinkWebSocketAdapter',
      client: (g) => JavaClientSerializer(g, JavaSerializer(g, importPrefix: '')),
      ser: (g) => JavaSerializer(g, importPrefix: ''),
    ),
    'Kotlin': _Target(
      import: 'java.time.OffsetDateTime',
      expected: 'import java.time.OffsetDateTime',
      preamble: kotlinJsonEncoderDecoder + kotlinClientAdapterGql,
      client: (g) => KotlinClientSerializer(g, KotlinSerializer(g, importPrefix: 'com.example')),
      ser: (g) => KotlinSerializer(g, importPrefix: 'com.example'),
    ),
    'TypeScript': _Target(
      import: 'luxon',
      expected: "import 'luxon';",
      files: (c) {
        final ts = c as TypeScriptClientSerializer;
        return {'queries': ts.generateQueriesFile(), 'mutations': ts.generateMutationsFile(), 'subscriptions': ts.generateSubscriptionsFile()};
      },
      client: (g) => TypeScriptClientSerializer(g, TypeScriptSerializer(g, importPrefix: '')),
      ser: (g) => TypeScriptSerializer(g, importPrefix: ''),
    ),
    'Python': _Target(
      import: 'from decimal import Decimal',
      expected: 'from decimal import Decimal',
      client: (g) => PythonClientSerializer(g, PythonSerializer(g)),
      ser: (g) => PythonSerializer(g),
    ),
    'Swift': _Target(
      import: 'MyDates',
      expected: 'import MyDates',
      client: (g) => SwiftClientSerializer(g, SwiftSerializer(g, importPrefix: 'GraphLinkGenerated')),
      ser: (g) => SwiftSerializer(g, importPrefix: 'GraphLinkGenerated'),
    ),
    'Go': _Target(
      import: 'math/big',
      expected: '"math/big"',
      client: (g) => GoClientSerializer(g, GoSerializer(g)),
      ser: (g) => GoSerializer(g),
    ),
  };

  for (final entry in others.entries) {
    test('${entry.key}: an operation file imports the codec of its argument', () {
      final codec = GLScalarCodec.fromConfig('Stamp', {
        'type': 'Instant',
        'import': entry.value.import,
        'fromJson': 'parse({})',
        'toJson': 'render({})',
      });
      final g = GLParser(autoGenerateQueries: true, generateAllFieldsFragments: true, scalarCodecs: {'Stamp': codec})..parse(entry.value.preamble + _schema);
      final client = entry.value.client(g);
      final serializer = entry.value.ser(g);
      final files = entry.value.files?.call(client) ??
          {
            'queries': client.getQueriesClass(),
            'mutations': client.getMutationsClass(),
            'subscriptions': client.getSubscriptionsClass(),
          };
      for (final f in files.entries) {
        expect(f.value, isNotNull, reason: f.key);
        expect(serializer.serializeGlClass(f.value!), contains(entry.value.expected), reason: '${entry.key} ${f.key} file');
      }
    });
  }

  test('IR: REST operation arguments contribute their codec imports', () {
    final codec = GLScalarCodec.fromConfig('Stamp', {'type': 'Instant', 'import': 'time.lib', 'fromJson': 'p({})', 'toJson': 'r({})'});
    final g = GLParser(scalarCodecs: {'Stamp': codec})
      ..parse('''
scalar Stamp
type Query { events(since: Stamp! @glRestParam): [String!]! @glRest(path: "/events") }
type Mutation { touch(at: Stamp!): Boolean @glRest(method: POST, path: "/touch/{at}") }
''');
    expect(g.scalarImportsOfOperationType(GLQueryType.query), {'time.lib'});
    expect(g.scalarImportsOfOperationType(GLQueryType.mutation), {'time.lib'});
    expect(g.scalarImportsOfOperationType(GLQueryType.subscription), isEmpty);
  });
}
