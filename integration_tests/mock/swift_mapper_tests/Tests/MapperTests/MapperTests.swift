import XCTest
import Persistence
@testable import GraphLinkGenerated

final class MapperTests: XCTestCase {
    private func entity() -> UserEntity {
        UserEntity(
            id: "1",
            fullName: "Ada Lovelace",
            addresses: [AddressEntity(street: "Main"), AddressEntity(street: "Side")],
            home: AddressEntity(street: "Home")
        )
    }

    func testExternalSourceCopiesFieldsAndMapsListAndNestedValue() {
        let user = UserEntityMapper.toUser(entity(), defaultNick: "anon")
        XCTAssertEqual(user.id, "1")
        XCTAssertEqual(user.fullName, "Ada Lovelace")
        XCTAssertEqual(user.addresses.map { $0.street }, ["Main", "Side"])
        XCTAssertEqual(user.home?.street, "Home")
    }

    func testExternalSourceNullTakesTheDefaultAndAPresentValueWins() {
        XCTAssertEqual(UserEntityMapper.toUser(entity(), defaultNick: "anon").nick, "anon")
        let other = UserEntity(id: "2", fullName: "B", nick: "bee")
        let user = UserEntityMapper.toUser(other, defaultNick: "anon")
        XCTAssertEqual(user.nick, "bee")
        XCTAssertNil(user.home)
        XCTAssertTrue(user.addresses.isEmpty)
    }

    func testExternalTargetIsBuiltWithNestedValues() {
        let back = UserMapper.toUserEntity(UserEntityMapper.toUser(entity(), defaultNick: "anon"))
        XCTAssertEqual(back.id, "1")
        XCTAssertEqual(back.fullName, "Ada Lovelace")
        XCTAssertEqual(back.nick, "anon")
        XCTAssertEqual(back.addresses.map { $0.street }, ["Main", "Side"])
        XCTAssertEqual(back.home?.street, "Home")
    }

    func testExternalTargetKeepsANullNestedValueNull() {
        let bare = UserEntity(id: "3", fullName: "C")
        XCTAssertNil(UserMapper.toUserEntity(UserEntityMapper.toUser(bare, defaultNick: "n")).home)
    }

    func testMapperStyleClassRenamesAFieldForOneTarget() {
        let summary = UserMapper.toUserSummary(UserEntityMapper.toUser(entity(), defaultNick: "anon"))
        XCTAssertEqual(summary.id, "1")
        XCTAssertEqual(summary.name, "Ada Lovelace")
    }
}
