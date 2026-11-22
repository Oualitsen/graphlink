const errorSchema = '''
enum Reason { gone banned }
scalar DateTime
type Article { id: ID! title: String }
type ArticleNotFound @glError { id: ID! }
type TitleTaken @glError { title: String! suggestions: [String!] }
type Banned @glError { reason: Reason! at: DateTime until: Int }
type Forbidden @glError { }
type Query { article(id: ID!): Article }
''';

String flat(String source) => source.replaceAll(RegExp(r'\s+'), ' ').trim();

Iterable<String> lines(String source) => source.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
