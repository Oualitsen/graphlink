import Foundation

struct TimeoutError: Error {}

func firstValue<T: Sendable>(
    from stream: AsyncThrowingStream<T, Error>,
    timeoutSeconds: UInt64
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            for try await value in stream {
                return value
            }
            throw TimeoutError()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
