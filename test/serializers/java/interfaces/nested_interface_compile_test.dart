import 'dart:io';

import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:test/test.dart';

const _package = 'com.example';

/// Serializes every interface/type (including projected types and projected
/// interfaces) with [serializer] and writes each one as a standalone .java
/// file directly under [srcDir] — no package-per-kind directory layout.
/// Every generated class shares a single package, so imports between our own
/// generated types are unnecessary and stripped; only third-party imports
/// (java.util.*, etc.) are kept. Then invokes `javac` against the whole dir.
ProcessResult _generateAndCompile(GLParser g, JavaSerializer serializer, Directory srcDir) {
  final defs = [
    ...g.interfaces.values,
    ...g.types.values,
    ...g.projectedInterfaces.values,
    ...g.projectedTypes.values,
  ];

  final files = <File>[];
  for (final def in defs) {
    final codeName = serializer.resolveCodeName(def.token);
    final body = serializer.serializeTypeDefinition(def);
    final filtered = body
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('import $_package.'))
        .join('\n');
    final file = File('${srcDir.path}/$codeName.java');
    file.writeAsStringSync('package $_package;\n\n$filtered');
    files.add(file);
  }

  return Process.runSync(
    'javac',
    ['-d', '${srcDir.path}/out', ...files.map((f) => f.path)],
  );
}

void main() {
  test('Base.nodeList ([Node!]!) narrowed to [Alpha!]! on Dog and [Beta!]! on Cat', () {
    const schema = '''
      interface Node {
        nodeId: ID!
      }

      type Alpha implements Node {
        nodeId: ID!
      }

      type Beta implements Node {
        nodeId: ID!
      }

      interface Base {
        id: ID!
        nodeList: [Node!]!
      }

      type Dog implements Base {
        id: ID!
        nodeList: [Alpha!]!
      }

      type Cat implements Base {
        id: ID!
        nodeList: [Beta!]!
      }

      type Query {
        getBase: Base!
      }
    ''';

    final g = GLParser(
      identityFields: ['id'],
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
    );
    g.parse(schema);

    expect(g.interfaces.keys, containsAll(['Base', 'Node']));
    expect(g.types.keys, containsAll(['Dog', 'Cat', 'Alpha', 'Beta']));
    expect(g.types['Dog']!.getFieldByName('nodeList')!.type.token, 'Alpha');
    expect(g.types['Cat']!.getFieldByName('nodeList')!.type.token, 'Beta');

    final serializer = JavaSerializer(g, importPrefix: _package, generateJsonMethods: true);
    final srcDir = Directory.systemTemp.createTempSync('glink_java_step2_');
    addTearDown(() => srcDir.deleteSync(recursive: true));

    final result = _generateAndCompile(g, serializer, srcDir);

    // ignore: avoid_print
    print('exitCode: ${result.exitCode}');
    // ignore: avoid_print
    print(result.stdout);
    // ignore: avoid_print
    print(result.stderr);
  });
}
