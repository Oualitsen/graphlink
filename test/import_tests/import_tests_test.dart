import 'package:graphlink/src/model/gl_collection_imports.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/java_imports.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/java_spring_server_serializer.dart';
import 'package:test/test.dart';

void main() async {
  test("outer input with embedded glExternal input", () {
    final GLParser g = GLParser(generateAllFieldsFragments: true);
    g.parse('''
  input Pageable @glExternal(glClass: "Pageable", glImport: "org.springframework.data.domain.Pageable") {
    _: Int
  }

  input PersonInput {
    name: String
    pageable: Pageable
  }
''');

    var personInput = g.inputs["PersonInput"]!;
    var serializer = DartSerializer(g, importPrefix: "myorg");
    var serialized = serializer.serializeInputDefinition(personInput);
    print(serialized);

    expect(serialized, isNot(contains("myorg/inputs/pageable.dart")));
    expect(serialized,
        contains("import 'org.springframework.data.domain.Pageable';"));
  });

  test("batch mapping service generation", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        mode: CodeGenerationMode.server,
        collectionImports: const GLCollectionImports(
            listImport: JavaImports.list, mapImport: JavaImports.map));
    g.parse('''
  type Author {
    id: ID!
    name: String!
    articles: [ArticleData] @glSkipOnServer(batch: true)
  }

  type Article {
    id: ID!
    title: String!
  }

  type ArticleData @glSkipOnServer(mapTo: "Article") {
    article: Article!
    published: Boolean!
    date: String!
  }

  type Query {
    getAuthor(id: ID!): Author
  }
''');

    var serializer = JavaSerializer(g, importPrefix: "com.myorg");
    for (var service in g.services.values) {
      print(serializer.serializeTypeDefinition(service));
      print("____________________");
    }

    var authorMappingSerial = serializer
        .serializeTypeDefinition(g.services["AuthorSchemaMappingsService"]!);
    expect(authorMappingSerial, contains("import com.myorg.types.Author;"));
    expect(authorMappingSerial, contains("import com.myorg.types.Article;"));

    var articleDataMappingSerial = serializer.serializeTypeDefinition(
        g.services["ArticleDataSchemaMappingsService"]!);
    expect(
        articleDataMappingSerial, contains("import com.myorg.types.Article;"));
  });

  test("repository query method annotation should not be duplicated", () {
    final GLParser g = GLParser(mode: CodeGenerationMode.server);
    g.parse('''

  directive @glRepository(
    glType: String!
    glIdType: String!
    glImport: String = "org.springframework.data.mongodb.repository.MongoRepository"
    glClass: String = "MongoRepository"
    glOnClient: Boolean = false
    glOnServer: Boolean = true
) on INTERFACE

  directive @glQuery(
    value: String!
    glClass: String = "@Query"
    glImport: String = "org.springframework.data.mongodb.repository.Query"
    glOnClient: Boolean = false
    glOnServer: Boolean = true
    glAnnotation: Boolean = true
) on FIELD_DEFINITION

  type Clinic {
    name: String
  }

  interface ClinicRepository @glRepository(glIdType: "String", glType: "Clinic") {
    findByZipCodeAndPhoneNumber( zipCode: String,  phoneNumber: String): [Clinic!]! @glQuery(value: "{ 'address.zipCode': ?0, 'phoneNumber': ?1 }")
}
''');

    var repo = g.repositories["ClinicRepository"]!;
    var serializer = JavaSpringServerSerializer(g, packageName: "com.myorg");
    var serialized = serializer.serializeRepository(repo);
    print(serialized);

    expect("@Query".allMatches(serialized).length, 1);
  });
}
