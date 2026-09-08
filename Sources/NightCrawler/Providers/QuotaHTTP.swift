import Foundation

/// Account metadata only. Never forwards credentials through redirects or caches responses.
enum QuotaHTTP {
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    static func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.httpCookieStorage = nil
        config.urlCache = nil
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        var body = Data()
        for try await byte in bytes {
            guard body.count < 1_048_576 else { throw URLError(.dataLengthExceedsMaximum) }
            body.append(byte)
        }
        return (body, http)
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
