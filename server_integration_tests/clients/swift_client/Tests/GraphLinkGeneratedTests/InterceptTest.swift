import XCTest
@testable import GraphLinkGenerated

final class InterceptTest: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newClient()
    }

    func testGreetInterceptedAppendsTheRunBeforeMarkerToTheNameArgument() async throws {
        let res = try await client.queries.greetIntercepted(name: "Ada")
        XCTAssertEqual(res.greetIntercepted.message, "Hello, Ada(runBefore)")
    }

    func testGreetPlainIsNotInterceptedNoMarkerAppended() async throws {
        let res = try await client.queries.greetPlain(name: "Ada")
        XCTAssertEqual(res.greetPlain.message, "Hello, Ada")
    }

    func testGreetingReceivedBakesTheMarkerIntoEveryEmittedGreeting() async throws {
        let stream = client.subscriptions.greetingReceived()

        let eventTask = Task {
            try await firstValue(from: stream, timeoutSeconds: 10)
        }

        try await Task.sleep(nanoseconds: 300_000_000)

        _ = try await client.mutations.sendGreeting(name: "Ada")

        let event = try await eventTask.value
        XCTAssertEqual(event.greetingReceived.message, "Hello, Ada(runBefore)")
    }

    func testTeamMembersInterceptedMappingAllowsRoleAuth() async throws {
        let res = try await client.queries.listTeams(fieldArgs: ListTeamsFieldArgs(membersRole: "auth"))
        let members = Set(res.listTeams.first!.members.map { $0.name })
        XCTAssertEqual(members, Set(["Ada", "Grace"]))
    }

    func testTeamMembersInterceptedMappingDeniesAnyOtherRole() async throws {
        do {
            _ = try await client.queries.listTeams(fieldArgs: ListTeamsFieldArgs(membersRole: "wrong"))
            XCTFail("expected throw")
        } catch is GraphLinkException {
            // expected
        }
    }
}
