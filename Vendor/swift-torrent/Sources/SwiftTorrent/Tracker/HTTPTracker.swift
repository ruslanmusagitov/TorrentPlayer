import Foundation

/// HTTP tracker client (BEP-3).
public struct HTTPTracker: Sendable {
    public let announceURL: String

    public init(announceURL: String) {
        self.announceURL = announceURL
    }

    /// Announce to the tracker.
    public func announce(params: AnnounceParams) async throws -> AnnounceResponse {
        guard var components = URLComponents(string: announceURL) else {
            throw TrackerError.invalidURL
        }

        // Build percent-encoded query manually. URLQueryItem would re-encode
        // an already-encoded info_hash / peer_id and break tracker announces.
        var parts: [String] = []
        if let existing = components.percentEncodedQuery, !existing.isEmpty {
            parts.append(existing)
        }

        parts.append("info_hash=\(percentEncodeBytes(params.infoHash.bytes))")
        parts.append("peer_id=\(percentEncodeBytes(params.peerID))")
        parts.append("port=\(params.port)")
        parts.append("uploaded=\(params.uploaded)")
        parts.append("downloaded=\(params.downloaded)")
        parts.append("left=\(params.left)")
        parts.append("compact=1")
        parts.append("numwant=\(params.numWant)")
        if let event = params.event {
            parts.append("event=\(event)")
        }

        components.percentEncodedQuery = parts.joined(separator: "&")

        guard let url = components.url else {
            throw TrackerError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        return try parseAnnounceResponse(data)
    }

    /// Percent-encode raw bytes for BitTorrent tracker query params (BEP-3).
    private func percentEncodeBytes(_ data: Data) -> String {
        data.map { String(format: "%%%02X", $0) }.joined()
    }

    private func parseAnnounceResponse(_ data: Data) throws -> AnnounceResponse {
        let decoder = BencodeDecoder()
        let value = try decoder.decode(data)

        if let failure = value["failure reason"]?.utf8String {
            throw TrackerError.failure(failure)
        }

        let interval = value["interval"]?.integerValue.map(Int.init) ?? 1800
        let seeders = value["complete"]?.integerValue.map(Int.init) ?? 0
        let leechers = value["incomplete"]?.integerValue.map(Int.init) ?? 0

        var peers: [(String, UInt16)] = []

        if let peersData = value["peers"]?.stringValue {
            // Compact format: 6 bytes per peer (4 IP + 2 port)
            var offset = 0
            while offset + 6 <= peersData.count {
                let ip = "\(peersData[offset]).\(peersData[offset + 1]).\(peersData[offset + 2]).\(peersData[offset + 3])"
                let port = UInt16(peersData[offset + 4]) << 8 | UInt16(peersData[offset + 5])
                peers.append((ip, port))
                offset += 6
            }
        } else if let peersList = value["peers"]?.listValue {
            // Dictionary format
            for peerValue in peersList {
                if let ip = peerValue["ip"]?.utf8String,
                   let port = peerValue["port"]?.integerValue {
                    peers.append((ip, UInt16(port)))
                }
            }
        }

        return AnnounceResponse(
            interval: interval, seeders: seeders, leechers: leechers, peers: peers
        )
    }
}

public struct AnnounceParams: Sendable {
    public let infoHash: InfoHash
    public let peerID: Data
    public let port: UInt16
    public let uploaded: Int64
    public let downloaded: Int64
    public let left: Int64
    public let numWant: Int
    public let event: String?  // "started", "stopped", "completed"

    public init(infoHash: InfoHash, peerID: Data, port: UInt16,
                uploaded: Int64 = 0, downloaded: Int64 = 0, left: Int64,
                numWant: Int = 50, event: String? = nil) {
        self.infoHash = infoHash
        self.peerID = peerID
        self.port = port
        self.uploaded = uploaded
        self.downloaded = downloaded
        self.left = left
        self.numWant = numWant
        self.event = event
    }
}

public struct AnnounceResponse: Sendable {
    public let interval: Int
    public let seeders: Int
    public let leechers: Int
    public let peers: [(String, UInt16)]
}

public enum TrackerError: Error, Equatable {
    case invalidURL
    case failure(String)
    case invalidResponse
    case connectionFailed
}
