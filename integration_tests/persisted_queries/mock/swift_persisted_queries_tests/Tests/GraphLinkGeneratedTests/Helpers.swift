import Foundation
@testable import GraphLinkGenerated

enum Helpers {
    static func newClient(_ server: ApqServer) -> GraphLinkClient {
        GraphLinkClient(
            adapter: server.post,
            getAdapter: server.get,
            wsAdapter: MockWebSocketAdapter(),
            multipartAdapter: MockMultipartAdapter().executeMultipart
        )
    }

    static func hashOf(_ request: [String: Any?]) -> [String: Any] {
        ((request["extensions"] as! [String: Any])["persistedQuery"]) as! [String: Any]
    }

    static let createUserInput = CreateUserInput(
        name: "Alice",
        email: "a@test.com",
        status: .active,
        address: AddressInput(street: "s", city: "c", country: "x")
    )
}

func n(_ pairs: (String, Any?)...) -> [String: Any?] {
    var result: [String: Any?] = [:]
    for (k, v) in pairs { result[k] = v }
    return result
}
