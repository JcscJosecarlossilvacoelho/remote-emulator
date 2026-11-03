import Foundation
import Network

/// A tiny HTTP/1.1 server bound to 127.0.0.1. Tailscale Serve puts it on the tailnet;
/// it is never reachable from the LAN or the internet directly.
final class HTTPServer: @unchecked Sendable {
    struct Request {
        let method: String
        let path: String
        let query: [String: String]
        let headers: [String: String]
        let body: Data

        func header(_ name: String) -> String? { headers[name.lowercased()] }
        var json: [String: Any] { (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:] }
    }

    struct Response {
        var status: Int
        var body: Data
        var contentType = "application/json"

        static func json(_ status: Int, _ object: Any) -> Response {
            let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
            return Response(status: status, body: data)
        }

        static func error(_ status: Int, _ message: String) -> Response { json(status, ["ok": false, "error": message]) }
    }

    typealias Handler = @Sendable (Request) async -> Response

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "remote-emulator.http")
    private let maxBody = 1_000_000

    var isRunning: Bool { listener != nil }

    func start(port: UInt16, handler: @escaping Handler) throws {
        stop()
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return connection.cancel() }
            connection.start(queue: self.queue)
            self.receive(connection, buffer: Data(), handler: handler)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func receive(_ connection: NWConnection, buffer: Data, handler: @escaping Handler) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, done, error in
            guard let self else { return connection.cancel() }
            var buffer = buffer
            if let data { buffer.append(data) }
            if buffer.count > self.maxBody + 16_384 {
                return self.send(.error(413, "Request too large"), on: connection)
            }
            if let request = Self.parse(buffer) {
                Task {
                    let response = await handler(request)
                    self.send(response, on: connection)
                }
            } else if done || error != nil {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer, handler: handler)
            }
        }
    }

    /// Returns a request once headers and the full body (Content-Length) have arrived.
    private static func parse(_ data: Data) -> Request? {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<end.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let parts = lines.removeFirst().split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = data[end.upperBound...]
        guard body.count >= length else { return nil }
        let target = URLComponents(string: String(parts[1]))
        var query: [String: String] = [:]
        target?.queryItems?.forEach { query[$0.name] = $0.value ?? "" }
        return Request(method: String(parts[0]), path: target?.path ?? "/", query: query,
                       headers: headers, body: Data(body.prefix(length)))
    }

    private func send(_ response: Response, on connection: NWConnection) {
        let reason = HTTPURLResponse.localizedString(forStatusCode: response.status).capitalized
        let head = "HTTP/1.1 \(response.status) \(reason)\r\nContent-Type: \(response.contentType)\r\n"
            + "Content-Length: \(response.body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + response.body, completion: .contentProcessed { _ in connection.cancel() })
    }
}
