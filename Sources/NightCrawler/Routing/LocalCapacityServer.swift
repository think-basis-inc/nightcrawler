import Foundation
import Network

final class LocalCapacityServer: @unchecked Sendable {
    static let port: UInt16 = 17_890

    private let queue = DispatchQueue(label: "ai.thinkbasis.nightcrawler.capacity")
    private let snapshot: @MainActor @Sendable () -> CapacitySnapshot
    private var listener: NWListener?

    init(snapshot: @escaping @MainActor @Sendable () -> CapacitySnapshot) {
        self.snapshot = snapshot
    }

    func start() throws {
        guard listener == nil, let port = NWEndpoint.Port(rawValue: Self.port) else { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)

        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        let timeout = DispatchWorkItem { connection.cancel() }
        queue.asyncAfter(deadline: .now() + 2, execute: timeout)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, _, _ in
            guard let self, let data else {
                connection.cancel()
                return
            }
            Task { @MainActor in
                let response = LocalCapacityHTTP.response(for: data, snapshot: self.snapshot())
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }
}

enum LocalCapacityHTTP {
    static func response(for request: Data, snapshot: CapacitySnapshot) -> Data {
        guard let requestText = String(data: request, encoding: .utf8) else {
            return response(status: "400 Bad Request", body: ["error": "bad_request"])
        }
        let lines = requestText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return response(status: "400 Bad Request", body: ["error": "bad_request"])
        }

        let host = lines.dropFirst().first { $0.lowercased().hasPrefix("host:") }.map {
            String($0.dropFirst("host:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }
        let allowedHosts: Set<String> = [
            "127.0.0.1", "127.0.0.1:\(LocalCapacityServer.port)",
            "localhost", "localhost:\(LocalCapacityServer.port)",
        ]
        guard let host, allowedHosts.contains(host) else {
            return response(status: "403 Forbidden", body: ["error": "forbidden_host"])
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return response(status: "400 Bad Request", body: ["error": "bad_request"])
        }
        guard parts[0] == "GET" else {
            return response(status: "405 Method Not Allowed", body: ["error": "method_not_allowed"])
        }

        switch parts[1] {
        case "/health":
            return response(status: "200 OK", body: ["status": "ok"])
        case "/v1/capacity":
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            guard let body = try? encoder.encode(snapshot) else {
                return response(status: "500 Internal Server Error", body: ["error": "encoding_failed"])
            }
            return response(status: "200 OK", body: body)
        default:
            return response(status: "404 Not Found", body: ["error": "not_found"])
        }
    }

    private static func response(status: String, body: [String: String]) -> Data {
        let encoded = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data("{}".utf8)
        return response(status: status, body: encoded)
    }

    private static func response(status: String, body: Data) -> Data {
        var result = Data(
            "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8
        )
        result.append(body)
        return result
    }
}
