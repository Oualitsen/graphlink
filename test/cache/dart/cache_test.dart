import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  test("glCache staleIfOffline must be a boolean", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Query {
    getPerson: Person $glCache(ttl: 60, staleIfOffline: "yes")
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$glCacheArgStaleIfOffline on $glCache must be a boolean! found: "yes"'),
      )),
    );
  });

  test("glCache directive validation when ttl is invalid", () {
    final GLGrammar g = GLGrammar(
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
    );

    const text = '''
  type Person {
    id: ID!
    name: String!
  }

  type Query {
    getPerson: Person ${glCache}(ttl: "invaidValue")
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('ttl on @glCache directives should be a positive integer! found: "invaidValue"'),
      )),
    );
  });

  test("glCache directive validation when ttl is null", () {
    final GLGrammar g = GLGrammar(
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
    );

    const text = '''
  type Person {
    id: ID!
    name: String!
  }

  type Query {
    getPerson: Person ${glCache}()
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('ttl is required on @glCache directives line: 7 column: 24'),
      )),
    );
  });

  test("default cache should be applied", () {
    final GLGrammar g = GLGrammar(
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
    GLQueryDefinition getPerson = g.queries['getPerson']!;
    expect(getPerson.cacheTTL, 5000);
    expect(getPerson.cacheTags, isEmpty);
    for (var elem in getPerson.elements) {
      expect(elem.cacheTTL, 5000);
      expect(elem.cacheTags, isEmpty);
    }
  });

  test("default cache should be applied on custom queries", () {
    final GLGrammar g = GLGrammar(
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
    GLQueryDefinition myGetPerson = g.queries['MyGetPerson']!;

    expect(myGetPerson.cacheTTL, 5000);
    expect(myGetPerson.cacheTags, isEmpty);
    for (var elem in myGetPerson.elements) {
      expect(elem.cacheTTL, 5000);
      expect(elem.cacheTags, isEmpty);
    }
  });

  test("cache should be applied on query root element and its children", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Query {
    getPerson: Person 
  }

  query MyQuery @glCache(ttl: 5000, tags: ["Person"]) {
    getPerson  {
      id
    }
  }
''';

    var parsed = g.parse(text);
    expect(parsed is Success, true);
    GLQueryDefinition myQuery = g.queries['MyQuery']!;
    expect(myQuery.cacheTTL, 5000);
    expect(myQuery.cacheTags, contains("Person"));
    var qeuryElement = myQuery.elements.first;
    expect(qeuryElement.cacheTTL, 5000);
    expect(qeuryElement.cacheTags, contains("Person"));
  });

  test("cache tags should be propagated to element level with union operation", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Query {
    getPerson: Person 
  }

  query MyQuery @glCache(ttl: 5000, tags: ["generic"]) {
    # following should end up with tags generic and specific
    getPerson  @glCache(ttl: 6000, tags: ["specific"]){ 
      id
    }
  }
''';

    var parsed = g.parse(text);
    expect(parsed is Success, true);
    GLQueryDefinition myQuery = g.queries['MyQuery']!;
    expect(myQuery.cacheTTL, 5000);
    expect(myQuery.cacheTags, contains("generic"));
    var qeuryElement = myQuery.elements.first;
    expect(qeuryElement.cacheTTL, 6000);
    expect(qeuryElement.cacheTags, containsAll(["specific", "generic"]));
  });

  test("invalidate cache tags should be propagated to element level with union operation", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Query {
    getPerson: Person 
  }

  type Mutation {
    createPerson: Person
    
  }

  query MyQuery @glCache(ttl: 5000, tags: ["generic"]) {
    # following should end up with tags generic and specific
    getPerson  @glCache(ttl: 6000, tags: ["specific"]){ 
      id
    }
  }
  mutation CrPeron @glCacheInvalidate(tags: ["generic"]) {
    createPerson @glCacheInvalidate(tags: ["specific"]) {id}
  }
''';

    var parsed = g.parse(text);
    expect(parsed is Success, true);
    GLQueryDefinition myQuery = g.queries['CrPeron']!;
    expect(myQuery.invalidateCacheTags, contains("generic"));
    var qeuryElement = myQuery.elements.first;
    expect(qeuryElement.invalidateCacheTags, containsAll(["specific", "generic"]));
  });

  test("invalidate all cache  should be propagated to element level", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Query {
    getPerson: Person 
  }

  type Mutation {
    createPerson: Person
    
  }

  query MyQuery @glCache(ttl: 5000, tags: ["generic"]) {
    # following should end up with tags generic and specific
    getPerson  @glCache(ttl: 6000, tags: ["specific"]){ 
      id
    }
  }
  mutation CrPeron @glCacheInvalidate(all: true) {
    createPerson @glCacheInvalidate(tags: ["specific"]) {id}
  }
''';

    var parsed = g.parse(text);
    expect(parsed is Success, true);
    GLQueryDefinition myQuery = g.queries['CrPeron']!;
    expect(myQuery.cacheInvalidateAll, true);
    var qeuryElement = myQuery.elements.first;
    expect(qeuryElement.cacheInvalidateAll, true);
  });

  test("cache should be applied on auto generated queries", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Query {
    getPerson: Person @glCache(ttl: 5000, tags: ["Person"])
  }
 
''';

    var parsed = g.parse(text);
    expect(parsed is Success, true);
    GLQueryDefinition getPerson = g.queries['getPerson']!;
    final getPersonElement = getPerson.elements.first;
    expect(getPersonElement.cacheTTL, 5000);
    expect(getPersonElement.cacheTags, ["Person"]);
  });

  test("cache on child elements must override root cache", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Query {
    getPerson: Person
    count: Int
  }

  query MyQuery @glCache(ttl: 5000, tags: ["Person"]) {
    getPerson {
      id
    }
    count @glCache(ttl: 6000, tags: ["PersonCount"])
  }
''';

    var parsed = g.parse(text);
    expect(parsed is Success, true);
    GLQueryDefinition myQuery = g.queries['MyQuery']!;
    expect(myQuery.cacheTags.first, "Person");
    expect(myQuery.cacheTTL, 5000);
    var countElement = myQuery.elements.where((e) => e.token == "count").first;
    expect(countElement.cacheTags.first, "PersonCount");
    expect(countElement.cacheTTL, 6000);
  });

  test("glCache directive validation when tag is invalid", () {
    final GLGrammar g = GLGrammar(
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
    );

    const text = '''
  type Person {
    id: ID!
  }

  type Query {
    getPerson: Person ${glCache}(ttl: 5000, tags: ["invalid tag!"])
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('tag on @glCache directives should be alphanumeric with underscores only! found: invalid tag!'),
      )),
    );
  });

  test("nocahce should override cache", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Query {
    getPerson: Person
    count: Int
  }

  query MyQuery @glCache(ttl: 5000, tags: ["Person"]) {
    getPerson @glNoCache {
      id
    }
    count @glCache(ttl: 6000, tags: ["PersonCount"])
  }
''';

    var parsed = g.parse(text);
    expect(parsed is Success, true);
    GLQueryDefinition myQuery = g.queries['MyQuery']!;
    expect(myQuery.cacheTags.first, "Person");
    expect(myQuery.cacheTTL, 5000);
    var getPersonElement = myQuery.elements.where((e) => e.token == "getPerson").first;
    expect(getPersonElement.cacheTTL, 0);
    expect(getPersonElement.cacheTags, isEmpty);
  });

  test("glCache should not be applied to mutations (schema-level)", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Mutation {
    createPerson: Person @glCache(ttl: 10)
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$glCache is not allowed on mutations or subscriptions'),
      )),
    );
  });

  test("glCache should not be applied to mutations (explicit mutation declaration)", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Mutation {
    createPerson: Person
  }

  mutation CreatePerson {
    createPerson @glCache(ttl: 10) {
      id
    }
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$glCache is not allowed on mutations or subscriptions'),
      )),
    );
  });

  test("glCache should not be applied to subscriptions (schema-level)", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Subscription {
    onPersonCreated: Person @glCache(ttl: 10)
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$glCache is not allowed on mutations or subscriptions'),
      )),
    );
  });

  test("glCache should not be applied to subscriptions (explicit subscription declaration)", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Subscription {
    onPersonCreated: Person
  }

  subscription OnPersonCreated {
    onPersonCreated @glCache(ttl: 10) {
      id
    }
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$glCache is not allowed on mutations or subscriptions'),
      )),
    );
  });

  test("glNoCache should not be applied to mutations (schema-level)", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Mutation {
    createPerson: Person @glNoCache
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$glNoCache is not allowed on mutations or subscriptions'),
      )),
    );
  });

  test("glNoCache should not be applied to mutations (explicit mutation declaration)", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Mutation {
    createPerson: Person
  }

  mutation CreatePerson {
    createPerson @glNoCache {
      id
    }
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$glNoCache is not allowed on mutations or subscriptions'),
      )),
    );
  });

  test("glNoCache should not be applied to subscriptions (schema-level)", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Subscription {
    onPersonCreated: Person @glNoCache
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$glNoCache is not allowed on mutations or subscriptions'),
      )),
    );
  });

  test("glNoCache should not be applied to subscriptions (explicit subscription declaration)", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Subscription {
    onPersonCreated: Person
  }

  subscription OnPersonCreated {
    onPersonCreated @glNoCache {
      id
    }
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$glNoCache is not allowed on mutations or subscriptions'),
      )),
    );
  });

  test("glCacheInvalidate should fail when no args provided", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Mutation {
    createPerson: Person @glCacheInvalidate()
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$glCacheInvalidate requires either $glCacheArgAll: true or a non-empty $glCacheTagList'),
      )),
    );
  });

  test("glCacheInvalidate should fail when all is false and tags is empty", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Mutation {
    createPerson: Person @glCacheInvalidate(all: false)
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$glCacheInvalidate requires either $glCacheArgAll: true or a non-empty $glCacheTagList'),
      )),
    );
  });

  test("glCacheInvalidate should fail when all is not a boolean", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Mutation {
    createPerson: Person @glCacheInvalidate(all: "yes")
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$glCacheArgAll on $glCacheInvalidate must be a boolean'),
      )),
    );
  });

  test("glCacheInvalidate should pass with all: true", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Mutation {
    createPerson: Person @glCacheInvalidate(all: true)
  }
''';

    expect(() => g.parse(text), returnsNormally);
  });

  test("glCacheInvalidate should fail when tags contains a non-string element", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Mutation {
    createPerson: Person @glCacheInvalidate(tags: ["persons", 12])
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$glCacheTagList on $glCacheInvalidate must contain only strings'),
      )),
    );
  });

  test("glCacheInvalidate should pass with non-empty tags", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Query {
    getPersons: Person @glCache(ttl: 300, tags: ["persons"])
  }

  type Mutation {
    createPerson: Person @glCacheInvalidate(tags: ["persons"])
  }
''';

    expect(() => g.parse(text), returnsNormally);
  });

  test("glCacheInvalidate should fail when tag is not declared on any glCache directive", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Query {
    getPersons: Person @glCache(ttl: 300, tags: ["persons"])
  }

  type Mutation {
    createPerson: Person @glCacheInvalidate(tags: ["undeclaredTag"])
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('Tag "undeclaredTag" used in $glCacheInvalidate is not declared on any $glCache directive'),
      )),
    );
  });

  test("glCache should fail when tag value is an empty string", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Query {
    getPersons: Person @glCache(ttl: 300, tags: [""])
  }

''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('tag on @glCache directives should be alphanumeric with underscores only! found:  line: 6 column: 25'),
      )),
    );
  });

  // --------

  test("glInvalidateCache should not be applied to queries (schema-level)", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Query {
    getPerson: Person @glCacheInvalidate(all: true)
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$glCacheInvalidate is not allowed on queries or subscriptions'),
      )),
    );
  });

  test("glInvalidateCache should not be applied to quries (explicit mutation declaration)", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Query {
    getPerson: Person
  }

  query getPerson {
    getPerson @glCacheInvalidate(all: true) {
      id
    }
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$glCacheInvalidate is not allowed on queries or subscriptions'),
      )),
    );
  });

  test("glCacheInvalidate should not be applied to subscriptions (schema-level)", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Subscription {
    onPersonCreated: Person @glCacheInvalidate(all: true)
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$glCacheInvalidate is not allowed on queries or subscriptions'),
      )),
    );
  });

  test("glCacheInvalidate should not be applied to subscriptions (explicit subscription declaration)", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Subscription {
    onPersonCreated: Person
  }

  subscription OnPersonCreated {
    onPersonCreated @glCacheInvalidate(all: true) {
      id
    }
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains('$glCacheInvalidate is not allowed on queries or subscriptions'),
      )),
    );
  });

  test("glCache and glNoCache should not be applied to same query at the same time (explicit declaration)", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Query {
    getPerson: Person
  }

  query GetPerson {
    getPerson @glCache(ttl: 40) @glNoCache {
      id
    }
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains("$glCache AND $glNoCache on the same query? Incredible. You're the human equivalent of a merge conflict."),
      )),
    );
  });

  test("glCache and glNoCache should not be applied to same query at the same time (implicit declaration)", () {
    final GLGrammar g = GLGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
  }

  type Query {
    getPerson: Person @glCache(ttl: 40) @glNoCache
  }

  query GetPerson {
    getPerson {
      id
    }
  }
''';

    expect(
      () => g.parse(text),
      throwsA(isA<ParseException>().having(
        (e) => e.errorMessage,
        'errorMessage',
        contains("$glCache AND $glNoCache on the same query? Incredible. You're the human equivalent of a merge conflict."),
      )),
    );
  });
}
