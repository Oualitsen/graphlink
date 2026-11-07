import 'dart:io';
import 'dart:math';

import 'package:graphlink/src/model/gl_logical_file.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

const _core = '''
type Author {
  id: ID!
  name: String!
  latestArticles(limit: Int!): [Article!]! @glSkipOnServer(batch: false)
}
type Article {
  id: ID!
  title: String!
  author: Author! @glSkipOnServer(batch: false)
}
type Query {
  getAuthor(id: ID!): Author
  getArticle(id: ID!): Article!
  listArticles: [Article!]!
}
''';

const _extension = '''
type ArticleInfo @glSkipOnServer(batch: false, mapTo: "Article") {
  id: ID!
  title: String!
}
extend type Query {
  getProjectedArticle: Article!
  getArticleInfo: ArticleInfo
}
''';

Map<String, List<String>> _operations(List<GLLogicalFile> files) {
  final g = GLParser(generateAllFieldsFragments: true, autoGenerateQueries: true)
    ..parseFiles(files);
  return {
    for (final def in g.queries.values)
      '${def.type.name}:${def.token}':
          (def.arguments.map((a) => '${a.token}: ${a.type.inlineType.token}').toList()..sort())
  };
}

void main() {
  final coreFile = GLLogicalFile(_core, 'core.gql');
  final extensionFile = GLLogicalFile(_extension, 'mapping.gql');

  test('operations do not depend on the order of the schema files', () {
    final extensionFirst = _operations([extensionFile, coreFile]);
    final coreFirst = _operations([coreFile, extensionFile]);
    expect(coreFirst, extensionFirst);
  });

  test('operations reaching a field with arguments get them in both orders', () {
    for (final files in [
      [extensionFile, coreFile],
      [coreFile, extensionFile]
    ]) {
      final ops = _operations(files);
      for (final name in ['getArticle', 'listArticles', 'getProjectedArticle']) {
        final key = ops.keys.firstWhere((k) => k.endsWith(':$name'));
        expect(ops[key]!.any((a) => a.startsWith('\$fieldArgs')), isTrue,
            reason: '$name with ${files.first.path} first');
      }
    }
  });

  test('the server integration schema generates the same in any file order', () {
    final dir = Directory('server_integration_tests/schema');
    final files = [
      for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.gql')))
        GLLogicalFile(f.readAsStringSync(), f.path)
    ]..sort((a, b) => a.path.compareTo(b.path));
    final expected = _operations(files);
    for (var seed = 0; seed < 8; seed++) {
      final shuffled = [...files]..shuffle(Random(seed));
      expect(_operations(shuffled), expected, reason: 'seed $seed');
    }
    expect(_operations(files.reversed.toList()), expected);
  });
}
