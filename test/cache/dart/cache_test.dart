import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gq_queries.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  test("gqCache directive validation when ttl is invalid", () {
    final GQGrammar g = GQGrammar(
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
    );

    const text = '''
  type Person {
    id: ID!
    name: String!
  }

  type Query {
    getPerson: Person ${gqCache}(ttl: "invaidValue")
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('ttl on @gqCache directives should be a positive integer! found: "invaidValue"'),
      )),
    );
  });

  test("gqCache directive validation when ttl is null", () {
    final GQGrammar g = GQGrammar(
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
    );

    const text = '''
  type Person {
    id: ID!
    name: String!
  }

  type Query {
    getPerson: Person ${gqCache}()
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('ttl is required on @gqCache directives line: 7 column: 24'),
      )),
    );
  });

  test("default cache should be applied", () {
    final GQGrammar g = GQGrammar(
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
      defaultCacheTTL: 5000,
    );

    const text = '''
  type Person {
    id: ID!
    name: String!
  }

  type Query {
    getPerson: Person 
  }
''';

    var parsed = g.parse(text);
    expect(parsed is Success, true);
    GQQueryDefinition getPerson = g.queries['getPerson']!;
    var getPersonCache = getPerson.cacheDefinition;
    expect(getPersonCache, isNotNull);
    expect(getPersonCache!.ttl, 5000);
    expect(getPersonCache.tag, isNull);
    for (var elem in getPerson.elements) {
      expect(elem.cacheDefinition, isNotNull);
      expect(elem.cacheDefinition!.ttl, 5000);
      expect(elem.cacheDefinition!.tag, isNull);
    }
  });

  test("default cache should be applied on custom queries", () {
    final GQGrammar g = GQGrammar(
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
      defaultCacheTTL: 5000,
    );

    const text = '''
  type Person {
    id: ID!
    name: String!
  }

  type Query {
    getPerson: Person 
    getCount: Int
  }

  query MyGetPerson {
    getPerson {
      id
    }
    count: getCount
  }
''';

    var parsed = g.parse(text);
    expect(parsed is Success, true);
    GQQueryDefinition myGetPerson = g.queries['MyGetPerson']!;
    var cache = myGetPerson.cacheDefinition;
    expect(cache, isNotNull);
    expect(cache!.ttl, 5000);
    expect(cache.tag, isNull);
    for (var elem in myGetPerson.elements) {
      expect(elem.cacheDefinition, isNotNull);
      expect(elem.cacheDefinition!.ttl, 5000);
      expect(elem.cacheDefinition!.tag, isNull);
    }
  });

  test("cache should be applied on query root element and its children", () {
    final GQGrammar g = GQGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Query {
    getPerson: Person 
  }

  query MyQuery @gqCache(ttl: 5000, tag: "Person") {
    getPerson  {
      id
    }
  }
''';

    var parsed = g.parse(text);
    expect(parsed is Success, true);
    GQQueryDefinition myQuery = g.queries['MyQuery']!;
    var cache = myQuery.cacheDefinition;
    expect(cache, isNotNull);
    expect(cache!.ttl, 5000);
    expect(cache.tag, "Person");
    var qeuryElement = myQuery.elements.first;
    var elementCache = qeuryElement.cacheDefinition;
    expect(elementCache, isNotNull);
    expect(elementCache!.ttl, 5000);
    expect(elementCache.tag, "Person");
  });

  test("cache should be applied on auto generated queries", () {
    final GQGrammar g = GQGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Query {
    getPerson: Person @gqCache(ttl: 5000, tag: "Person")
  }
 
''';

    var parsed = g.parse(text);
    expect(parsed is Success, true);
    GQQueryDefinition getPerson = g.queries['getPerson']!;
    var cache = getPerson.cacheDefinition;
    expect(cache, isNotNull);
    expect(cache!.ttl, 5000);
    expect(cache.tag, "Person");
  });

  test("cache on child elements must override root cache", () {
    final GQGrammar g = GQGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Query {
    getPerson: Person
    count: Int
  }

  query MyQuery @gqCache(ttl: 5000, tag: "Person") {
    getPerson {
      id
    }
    count @gqCache(ttl: 6000, tag: "PersonCount")
  }
''';

    var parsed = g.parse(text);
    expect(parsed is Success, true);
    GQQueryDefinition myQuery = g.queries['MyQuery']!;
    var rootCahce = myQuery.cacheDefinition;
    expect(rootCahce, isNotNull);
    expect(rootCahce!.tag, "Person");
    expect(rootCahce.ttl, 5000);
    var countElement = myQuery.elements.where((e) => e.token == "count").first;
    var countCache = countElement.cacheDefinition;
    expect(countCache, isNotNull);
    expect(countCache!.tag, "PersonCount");
    expect(countCache.ttl, 6000);
  });

  test("gqCache directive validation when tag is invalid", () {
    final GQGrammar g = GQGrammar(
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
    );

    const text = '''
  type Person {
    id: ID!
  }

  type Query {
    getPerson: Person ${gqCache}(ttl: 5000, tag: "invalid tag!")
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains(
            'tag on @gqCache directives should be alphanumeric with underscores only! found: invalid tag!'),
      )),
    );
  });

  test("nocahce should override cache", () {
    final GQGrammar g = GQGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Query {
    getPerson: Person
    count: Int
  }

  query MyQuery @gqCache(ttl: 5000, tag: "Person") {
    getPerson @gqNoCache {
      id
    }
    count @gqCache(ttl: 6000, tag: "PersonCount")
  }
''';

    var parsed = g.parse(text);
    expect(parsed is Success, true);
    GQQueryDefinition myQuery = g.queries['MyQuery']!;
    var rootCahce = myQuery.cacheDefinition;
    expect(rootCahce, isNotNull);
    expect(rootCahce!.tag, "Person");
    expect(rootCahce.ttl, 5000);
    var getPersonElement = myQuery.elements.where((e) => e.token == "getPerson").first;
    expect(getPersonElement.cacheDefinition, isNull);
  });

  test("gqCache should not be applied to mutations (schema-level)", () {
    final GQGrammar g = GQGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Mutation {
    createPerson: Person @gqCache(ttl: 10)
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$gqCache is not allowed on mutations or subscriptions'),
      )),
    );
  });

  test("gqCache should not be applied to mutations (explicit mutation declaration)", () {
    final GQGrammar g = GQGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Mutation {
    createPerson: Person
  }

  mutation CreatePerson {
    createPerson @gqCache(ttl: 10) {
      id
    }
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$gqCache is not allowed on mutations or subscriptions'),
      )),
    );
  });

  test("gqCache should not be applied to subscriptions (schema-level)", () {
    final GQGrammar g = GQGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Subscription {
    onPersonCreated: Person @gqCache(ttl: 10)
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$gqCache is not allowed on mutations or subscriptions'),
      )),
    );
  });

  test("gqCache should not be applied to subscriptions (explicit subscription declaration)", () {
    final GQGrammar g = GQGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Subscription {
    onPersonCreated: Person
  }

  subscription OnPersonCreated {
    onPersonCreated @gqCache(ttl: 10) {
      id
    }
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$gqCache is not allowed on mutations or subscriptions'),
      )),
    );
  });

  test("gqNoCache should not be applied to mutations (schema-level)", () {
    final GQGrammar g = GQGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Mutation {
    createPerson: Person @gqNoCache
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$gqNoCache is not allowed on mutations or subscriptions'),
      )),
    );
  });

  test("gqNoCache should not be applied to mutations (explicit mutation declaration)", () {
    final GQGrammar g = GQGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Mutation {
    createPerson: Person
  }

  mutation CreatePerson {
    createPerson @gqNoCache {
      id
    }
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$gqNoCache is not allowed on mutations or subscriptions'),
      )),
    );
  });

  test("gqNoCache should not be applied to subscriptions (schema-level)", () {
    final GQGrammar g = GQGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Subscription {
    onPersonCreated: Person @gqNoCache
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$gqNoCache is not allowed on mutations or subscriptions'),
      )),
    );
  });

  test("gqNoCache should not be applied to subscriptions (explicit subscription declaration)", () {
    final GQGrammar g = GQGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Subscription {
    onPersonCreated: Person
  }

  subscription OnPersonCreated {
    onPersonCreated @gqNoCache {
      id
    }
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$gqNoCache is not allowed on mutations or subscriptions'),
      )),
    );
  });
}
