import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

const _schema = '''
type Product { id: ID! name: String }

type Query {
  health: String @glRest(path: "/health")
}

extend type Query @glRestPrefix(path: "/products") {
  products: [Product!]!
  product(id: ID!): Product @glRest(path: "/{id}")
}

extend type Query @glRestPrefix(path: "/shops/{shopId}") {
  shop(shopId: ID!): Product
}

extend type Mutation @glRestPrefix(path: "/products", method: PUT) {
  rename(id: ID!, name: String @glRestParam): Product @glRest(path: "/{id}/name")
}

type Mutation {
  ping: String
}
''';

void main() {
  late GLParser g;

  setUp(() {
    g = GLParser()..parse(_schema);
  });

  test('prefix is copied onto every field of its block', () {
    final query = g.types['Query']!;
    for (final name in ['products', 'product']) {
      final prefix = query.getFields().firstWhere((f) => f.name.token == name).getDirectiveByName(glRestPrefix);
      expect(prefix, isNotNull, reason: name);
      expect(prefix!.getArgValueAsString(glRestPathArg), '/products');
    }
  });

  test('each block keeps its own prefix', () {
    final shop = g.types['Query']!.getFields().firstWhere((f) => f.name.token == 'shop');
    expect(shop.getDirectiveByName(glRestPrefix)!.getArgValueAsString(glRestPathArg), '/shops/{shopId}');
  });

  test('the prefix keeps its method argument', () {
    final rename = g.types['Mutation']!.getFields().firstWhere((f) => f.name.token == 'rename');
    expect(rename.getDirectiveByName(glRestPrefix)!.getArgValueAsString(glRestMethodArg), 'PUT');
  });

  test('fields outside a prefix block carry no prefix', () {
    final health = g.types['Query']!.getFields().firstWhere((f) => f.name.token == 'health');
    expect(health.hasDirective(glRestPrefix), isFalse);
    final ping = g.types['Mutation']!.getFields().firstWhere((f) => f.name.token == 'ping');
    expect(ping.hasDirective(glRestPrefix), isFalse);
  });

  test('the prefix is not left on the merged type', () {
    expect(g.types['Query']!.hasDirective(glRestPrefix), isFalse);
    expect(g.types['Mutation']!.hasDirective(glRestPrefix), isFalse);
  });
}
