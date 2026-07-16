import Foundation
@testable import GraphLinkGenerated

enum Fixtures {
    static var port: Int {
        ProcessInfo.processInfo.environment["SERVER_PORT"].flatMap(Int.init) ?? 9997
    }

    static var SERVER_URL: URL { URL(string: "http://localhost:\(port)/graphql")! }
    static var WS_URL: URL { URL(string: "ws://localhost:\(port)/graphql")! }

    static func newClient() -> GraphLinkClient {
        GraphLinkClient.create(url: SERVER_URL, wsUrl: WS_URL)
    }
}
