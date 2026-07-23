# Vendored SwiftTorrent

Local copy of [warppipe/swift-torrent](https://github.com/warppipe/swift-torrent) with app-specific patches.

## Patches

- Dependencies: dropped unused `swift-nio-extras` / `NIOExtras` (was imported but never called; pulled a large transitive SPM graph).
- `HTTPTracker.swift`: build announce query with raw percent-encoded `info_hash` / `peer_id`. Upstream used `URLQueryItem`, which double-encodes binary params and causes tracker announces (e.g. torrents.ru) to return no peers — magnets then time out waiting for metadata.
- `PeerConnection.swift`: wait for the remote BitTorrent handshake before reading `supportsExtensions`. Upstream raced the inbound decode, so extension handshakes (BEP-9 ut_metadata) were never sent.
- Sequential / selected-file download (task #6):
  - `FileStorage.pieceRange(forFileIndex:)` maps a file to its piece index range (including boundary pieces).
  - `PiecePicker` supports `sequential` mode restricted to an interested range (lowest missing index first); `clearPriority()` restores rarest-first over all pieces.
  - After metadata, picker starts with an empty interested range (no piece requests) until `TorrentHandle.prioritizeFile` sets the selected file.
  - `prioritizeFile` updates the live picker in `PeerManager`, cancels in-flight block requests, and refills peer pipelines.
- Streaming readiness (task #7):
  - `FileStorage.leadingPieceRange` / `pieceRange(fileOffset:length:)` map file byte ranges to piece indices.
  - `TorrentHandle.waitForLeadingBytes` / `waitForFileBytes` poll until contiguous pieces are on disk.
  - After magnet metadata: disconnect metadata-era peers, re-announce with real `left`, send empty bitfield on connect.
  - Create `PeerState` before TCP handshake completes so early bitfield/unchoke messages are not dropped.
  - Piece completion requires all block offsets (not just buffer length) before SHA-1 verify.
  - Ignore duplicate BEP-9 metadata completions (was resetting picker to 0..<0 and disconnecting peers in a loop).
  - `TorrentLog` (OSLog + optional file) for peer/piece/session diagnostics.
- Peer connectivity:
  - `Session.startListening()` binds TCP `listenPort` and accepts inbound BitTorrent handshakes (`IncomingPeerHandler` → `PeerManager.acceptIncoming`).
  - Tracker announces advertise `settings.listenPort` (was hard-coded 6881).
  - DHT `get_peers` is wired: after each torrent start, `Session` runs iterative `DHTTraversal.getPeers` and feeds addresses into `TorrentHandle.addPeer`.
- Seeding (opt-in via app Settings, default off):
  - `SessionSettings.seedingEnabled` → `PeerManager`: honest completed bitfield, unchoke on interested, serve `.request` from `DiskIO.readPiece`, bump `totalUploaded`.
  - When off: empty bitfield + ignore requests (download-only), matching prior behavior.
