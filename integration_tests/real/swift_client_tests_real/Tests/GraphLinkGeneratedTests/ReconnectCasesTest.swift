import Foundation
import XCTest
@testable import GraphLinkGenerated

private let port = 9936

private final class Stream: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [String] = []
    private var _error: Error?
    private var _completed = false
    private var task: Task<Void, Never>?

    init(_ client: GraphLinkClient, label: String, count: Int) {
        task = Task { [self] in
            do {
                for try await event in client.subscriptions.labelTicks(label: label, count: count) {
                    lock.lock(); _events.append(event.labelTicks); lock.unlock()
                }
                lock.lock(); _completed = !Task.isCancelled; lock.unlock()
            } catch {
                lock.lock(); _error = error; lock.unlock()
            }
        }
    }

    var events: [String] { lock.lock(); defer { lock.unlock() }; return _events }
    var error: Error? { lock.lock(); defer { lock.unlock() }; return _error }
    var completed: Bool { lock.lock(); defer { lock.unlock() }; return _completed }
    func cancel() { task?.cancel() }
}

final class ReconnectCasesTest: XCTestCase {
    private var processes: [Process] = []
    private var ws: DefaultGraphLinkWebSocketAdapter?
    private var client: GraphLinkClient!
    private var streams: [Stream] = []

    override func setUpWithError() throws {
        try startServer()
    }

    override func tearDown() {
        streams.forEach { $0.cancel() }
        streams = []
        ws?.close()
        processes.forEach { $0.terminate() }
        processes = []
        killPort()
        super.tearDown()
    }

    private func killPort() {
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/bin/bash")
        kill.arguments = ["-c", "lsof -ti :\(port) -sTCP:LISTEN | xargs kill -9 2>/dev/null || true"]
        try? kill.run()
        kill.waitUntilExit()
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func portIsOpen() -> Bool {
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        probe.arguments = ["-z", "localhost", "\(port)"]
        try? probe.run()
        probe.waitUntilExit()
        return probe.terminationStatus == 0
    }

    private func startServer() throws {
        killPort()
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        server.arguments = ["python3", FileManager.default.currentDirectoryPath + "/../fault_server/server.py", "--port", "\(port)", "--live"]
        let errors = Pipe()
        server.standardOutput = FileHandle.nullDevice
        server.standardError = errors
        try server.run()
        processes.append(server)
        let deadline = Date().addingTimeInterval(30)
        while !portIsOpen() {
            if !server.isRunning {
                let output = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                XCTFail("the server on port \(port) exited with status \(server.terminationStatus): \(output)")
                throw CancellationError()
            }
            if Date() > deadline {
                XCTFail("the server on port \(port) did not open the port within 30 s")
                throw CancellationError()
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    private func until(_ what: String, timeout: TimeInterval = 60, _ check: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !check() {
            if Date() > deadline { XCTFail("timed out: \(what)"); throw CancellationError() }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func connect(headers: (@Sendable () -> [String: String])? = nil, maxAttempts: Int? = 10, maxDelay: TimeInterval = 30) {
        let adapter = DefaultGraphLinkWebSocketAdapter(
            url: URL(string: "ws://localhost:\(port)/graphql")!,
            headersProvider: headers,
            maxReconnectAttempts: maxAttempts,
            maxReconnectDelay: maxDelay
        )
        ws = adapter
        let http = DefaultGraphLinkURLSessionAdapter(url: URL(string: "http://localhost:\(port)/graphql")!)
        client = GraphLinkClient(adapter: http.execute, wsAdapter: adapter, multipartAdapter: MockMultipartAdapter().executeMultipart)
    }

    private func subscribe(_ label: String, count: Int = 1000) -> Stream {
        let stream = Stream(client, label: label, count: count)
        streams.append(stream)
        return stream
    }

    private func starts(_ label: String) async throws -> Int {
        try await client.queries.labelTickStarts(label: label).labelTickStarts
    }

    private func awaitEvent(_ stream: Stream, _ label: String) async throws {
        let seen = stream.events.count
        try await until("an event for \(label) after the restart") {
            stream.events.dropFirst(seen).contains { $0.hasPrefix("\(label)-") }
        }
    }

    func test_resubscribesWithTheSameVariables() async throws {
        connect()
        let bob = subscribe("bob")
        try await until("first event") { !bob.events.isEmpty }
        XCTAssertEqual(bob.events.first, "bob-1")

        try startServer()
        try await awaitEvent(bob, "bob")
        let count = try await starts("bob")
        XCTAssertEqual(count, 1)
    }

    func test_doesNotResubscribeACompletedSubscription() async throws {
        connect()
        let done = subscribe("done", count: 2)
        try await until("completion") { done.completed }
        XCTAssertEqual(done.events.count, 2)

        try startServer()
        try await Task.sleep(nanoseconds: 6_000_000_000)
        let count = try await starts("done")
        XCTAssertEqual(count, 0)
        XCTAssertEqual(done.events.count, 2)
    }

    func test_doesNotReviveACancelledSubscription() async throws {
        connect()
        let cancelled = subscribe("cancelled")
        try await until("first event") { !cancelled.events.isEmpty }
        cancelled.cancel()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        try startServer()
        try await Task.sleep(nanoseconds: 6_000_000_000)
        let count = try await starts("cancelled")
        XCTAssertEqual(count, 0)
    }

    func test_resumesEveryOpenSubscriptionOnOneSocket() async throws {
        connect()
        let a = subscribe("a")
        let b = subscribe("b")
        try await until("first events") { !a.events.isEmpty && !b.events.isEmpty }

        try startServer()
        try await awaitEvent(a, "a")
        try await awaitEvent(b, "b")
        let startsOfA = try await starts("a")
        let startsOfB = try await starts("b")
        XCTAssertEqual(startsOfA, 1)
        XCTAssertEqual(startsOfB, 1)
    }

    func test_aRestartDuringConnectionInitSubscribesOnce() async throws {
        connect(headers: { ["Ack-Delay": "3000"] })
        let initStream = subscribe("init")
        try await Task.sleep(nanoseconds: 1_000_000_000)

        try startServer()
        try await awaitEvent(initStream, "init")
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let count = try await starts("init")
        XCTAssertEqual(count, 1)
    }

    func test_aServerDownLongerThanTheAckTimeoutStillResumes() async throws {
        connect(headers: { ["Ack-Delay": "3000"] })
        let initStream = subscribe("init")
        try await Task.sleep(nanoseconds: 1_000_000_000)

        killPort()
        try await Task.sleep(nanoseconds: 8_000_000_000)
        try startServer()
        try await awaitEvent(initStream, "init")
        XCTAssertNil(initStream.error)
        let count = try await starts("init")
        XCTAssertEqual(count, 1)
    }

    func test_givesUpWithAVisibleError() async throws {
        connect(maxAttempts: 2, maxDelay: 1)
        let giveUp = subscribe("giveup")
        try await until("first event") { !giveUp.events.isEmpty }
        killPort()

        try await until("an error or an end after the reconnect attempts ran out") { giveUp.error != nil || giveUp.completed }
        XCTAssertNotNil(giveUp.error)
    }
}
