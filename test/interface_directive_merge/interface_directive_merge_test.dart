import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

const schema = '''
directive @Id on FIELD_DEFINITION
directive @CreatedDate on FIELD_DEFINITION
directive @LastModifiedDate on FIELD_DEFINITION
directive @CreatedBy on FIELD_DEFINITION

interface BasicEntity {
  id: ID! @Id
  creationDate: Int! @CreatedDate
}

interface UserBase implements BasicEntity {
  id: ID! @Id
  creationDate: Int! @CreatedDate
  lastUpdate: Int! @LastModifiedDate
  createdBy: String @CreatedBy
}

type User implements UserBase & BasicEntity {
  id: ID! @Id
  creationDate: Int! @CreatedDate
  lastUpdate: Int! @LastModifiedDate
  createdBy: String @CreatedBy
  email: String!
}

type Query {
  basic: BasicEntity
  userBaseSubset: UserBase
  user: User
}

query GetBasic {
  basic {
    id
    creationDate
  }
}

query GetUserBaseSubset {
  userBaseSubset {
    id
    creationDate
  }
}
''';

void main() {
  test("UserBase implements BasicEntity and redeclares its audit-directive fields", () {
    final GLParser g = GLParser();
    g.parse(schema);

    final userBase = g.interfaces["UserBase"]!;
    expect(userBase.getFieldByName("id"), isNotNull);
    expect(userBase.getFieldByName("creationDate"), isNotNull);
    expect(userBase.getFieldByName("lastUpdate"), isNotNull);
    expect(userBase.getFieldByName("createdBy"), isNotNull);
  });

  test(
      "merging projected interfaces with an identical field shape from different interface origins does not throw on a shared directive",
      () {
    // Regression test: GetBasic and GetUserBaseSubset both select exactly
    // {id, creationDate}, producing two structurally-identical projected
    // interfaces derived from BasicEntity and UserBase respectively. The
    // projection merge used to re-add @Id/@CreatedDate onto a field that
    // already carried them and throw "Directive already exists".
    final GLParser g = GLParser();
    g.parse(schema);
  });
}
