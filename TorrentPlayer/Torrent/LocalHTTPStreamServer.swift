//
//  LocalHTTPStreamServer.swift
//  TorrentPlayer
//
//  Task #7: loopback HTTP server for AVPlayer progressive streaming.
//

import Foundation
import Network

/// Minimal HTTP/1.1 file server on 127.0.0.1 for a single growing torrent file.
///
/// Responses are streamed in chunks: headers go out after the first chunk is
/// ready, then each subsequent chunk waits for torrent bytes. A full GET must
/// not block on the entire `fileSize` up front (browsers/VLC hang otherwise).
final class LocalHTTPStreamServer: @unchecked Sendable {
    typealias ByteWaiter = @Sendable (_ offset: Int64, _ length: Int64) async -> Bool

    private let fileURL: URL
    private let fileSize: Int64
    private let contentType: String
    private let waitForBytes: ByteWaiter
    private let rangeWaitSeconds: Int
    private let chunkSize: Int64
    private var listener: NWListener?
    private(set) var port: NWEndpoint.Port?

    var streamURL: URL? {
        guard let port else { return nil }
        return URL(string: "http://127.0.0.1:\(port.rawValue)/stream")
    }

    init(
        fileURL: URL,
        fileSize: Int64,
        contentType: String = "application/octet-stream",
        rangeWaitSeconds: Int = 600,
        chunkSize: Int64 = 256 * 1024,
        waitForBytes: @escaping ByteWaiter = { _, _ in true }
    ) {
        self.fileURL = fileURL
        self.fileSize = fileSize
        self.contentType = contentType
        self.rangeWaitSeconds = rangeWaitSeconds
        self.chunkSize = max(chunkSize, 16 * 1024)
        self.waitForBytes = waitForBytes
    }

    func start() async throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: 0
        )
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume()
                case let .failed(error):
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }

        guard let port = listener.port else {
            listener.cancel()
            throw CocoaError(.fileReadUnknown)
        }
        self.listener = listener
        self.port = port
        TPLog.http("listening on 127.0.0.1:\(port.rawValue) file=\(fileURL.lastPathComponent) size=\(fileSize)")
    }

    func stop() {
        if let port {
            TPLog.http("stop port=\(port.rawValue)")
        }
        listener?.cancel()
        listener = nil
        port = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.receiveRequest(on: connection, buffer: Data())
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil || (isComplete && (data == nil || data?.isEmpty == true) && buffer.isEmpty) {
                connection.cancel()
                return
            }

            var next = buffer
            if let data { next.append(data) }

            guard let headerEnd = next.range(of: Data("\r\n\r\n".utf8)) else {
                if next.count > 64 * 1024 {
                    self.sendAndClose(Self.simpleResponse(status: 400, body: "Bad Request"), on: connection)
                } else {
                    self.receiveRequest(on: connection, buffer: next)
                }
                return
            }

            let headerData = next.subdata(in: next.startIndex..<headerEnd.lowerBound)
            guard let headerText = String(data: headerData, encoding: .utf8) else {
                self.sendAndClose(Self.simpleResponse(status: 400, body: "Bad Request"), on: connection)
                return
            }

            Task {
                await self.serve(headerText: headerText, on: connection)
            }
        }
    }

    private func serve(headerText: String, on connection: NWConnection) async {
        TPLog.http("request \(headerText.split(whereSeparator: \.isNewline).first ?? "?")")
        let lines = headerText.split(whereSeparator: \.isNewline).map(String.init)
        guard let requestLine = lines.first else {
            sendAndClose(Self.simpleResponse(status: 400, body: "Bad Request"), on: connection)
            return
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendAndClose(Self.simpleResponse(status: 400, body: "Bad Request"), on: connection)
            return
        }
        let method = String(parts[0])
        let path = String(parts[1])
        guard path == "/stream" || path.hasPrefix("/stream?") else {
            sendAndClose(Self.simpleResponse(status: 404, body: "Not Found"), on: connection)
            return
        }
        guard method == "GET" || method == "HEAD" else {
            sendAndClose(Self.simpleResponse(status: 405, body: "Method Not Allowed"), on: connection)
            return
        }

        let rangeHeader = lines.first { $0.lowercased().hasPrefix("range:") }
        let byteRange = rangeHeader.flatMap { Self.parseRange($0, fileSize: fileSize) }

        let start: Int64
        let end: Int64
        let isPartial: Bool
        if let byteRange {
            start = byteRange.lowerBound
            end = byteRange.upperBound
            isPartial = true
        } else {
            start = 0
            end = max(fileSize - 1, 0)
            isPartial = false
        }

        let length = max(end - start + 1, 0)
        guard length > 0, start >= 0, end < fileSize else {
            sendAndClose(Self.simpleResponse(status: 416, body: "Range Not Satisfiable"), on: connection)
            return
        }

        // Only wait for the first chunk before headers — never the whole file.
        let firstChunk = min(chunkSize, length)
        let ready = await waitWithTimeout(offset: start, length: firstChunk)
        guard ready else {
            TPLog.http("503 bytes not ready offset=\(start) length=\(firstChunk)")
            sendAndClose(Self.simpleResponse(status: 503, body: "Bytes Not Ready"), on: connection)
            return
        }

        var header = "HTTP/1.1 \(isPartial ? 206 : 200) \(isPartial ? "Partial Content" : "OK")\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Accept-Ranges: bytes\r\n"
        header += "Content-Length: \(length)\r\n"
        if isPartial {
            header += "Content-Range: bytes \(start)-\(end)/\(fileSize)\r\n"
        }
        header += "Connection: close\r\n\r\n"

        TPLog.http(
            "\(isPartial ? 206 : 200) \(method) offset=\(start) length=\(length) range=\(rangeHeader ?? "-")"
        )

        let headerSent = await send(Data(header.utf8), on: connection)
        guard headerSent else { return }

        if method == "HEAD" {
            connection.cancel()
            return
        }

        do {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }

            var offset = start
            while offset <= end {
                let chunkLen = min(chunkSize, end - offset + 1)
                let chunkReady = await waitWithTimeout(offset: offset, length: chunkLen)
                guard chunkReady else {
                    TPLog.http("stream stalled offset=\(offset) length=\(chunkLen)")
                    connection.cancel()
                    return
                }
                try handle.seek(toOffset: UInt64(offset))
                let body = try handle.read(upToCount: Int(chunkLen)) ?? Data()
                guard !body.isEmpty else {
                    connection.cancel()
                    return
                }
                let ok = await send(body, on: connection)
                guard ok else { return }
                offset += Int64(body.count)
            }
            connection.cancel()
        } catch {
            TPLog.http("read error: \(error.localizedDescription)")
            connection.cancel()
        }
    }

    private func waitWithTimeout(offset: Int64, length: Int64) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(rangeWaitSeconds)
        while ContinuousClock.now < deadline {
            if await waitForBytes(offset, length) { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    private func sendAndClose(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func send(_ data: Data, on connection: NWConnection) async -> Bool {
        await withCheckedContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if error != nil {
                    connection.cancel()
                    continuation.resume(returning: false)
                } else {
                    continuation.resume(returning: true)
                }
            })
        }
    }

    private static func simpleResponse(status: Int, body: String) -> Data {
        let reason: String = switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 416: "Range Not Satisfiable"
        case 503: "Service Unavailable"
        default: "Error"
        }
        let payload = Data(body.utf8)
        let header = """
        HTTP/1.1 \(status) \(reason)\r\n\
        Content-Type: text/plain\r\n\
        Content-Length: \(payload.count)\r\n\
        Connection: close\r\n\r\n
        """
        var data = Data(header.utf8)
        data.append(payload)
        return data
    }

    static func parseRange(_ header: String, fileSize: Int64) -> ClosedRange<Int64>? {
        let trimmed = header.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("bytes=") else { return nil }
        let spec = trimmed.dropFirst("bytes=".count)
        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        if parts[0].isEmpty, let suffix = Int64(parts[1]), suffix > 0 {
            let start = max(fileSize - suffix, 0)
            return start...(fileSize - 1)
        }

        guard let start = Int64(parts[0]), start >= 0, start < fileSize else { return nil }
        if parts[1].isEmpty {
            return start...(fileSize - 1)
        }
        guard let end = Int64(parts[1]), end >= start else { return nil }
        return start...min(end, fileSize - 1)
    }

    static func contentType(forPath path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "mp4", "m4v": "video/mp4"
        case "mov": "video/quicktime"
        case "mkv": "video/x-matroska"
        case "webm": "video/webm"
        case "avi": "video/x-msvideo"
        default: "application/octet-stream"
        }
    }

    static func diskURL(downloadsDirectory: URL, relativePath: String) -> URL {
        relativePath
            .split(separator: "/")
            .reduce(downloadsDirectory) { partial, component in
                partial.appendingPathComponent(String(component))
            }
    }
}
