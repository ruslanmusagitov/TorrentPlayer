# Vendored SwiftTorrent

Local copy of [warppipe/swift-torrent](https://github.com/warppipe/swift-torrent) with app-specific patches.

## Patches

- `HTTPTracker.swift`: build announce query with raw percent-encoded `info_hash` / `peer_id`. Upstream used `URLQueryItem`, which double-encodes binary params and causes tracker announces (e.g. torrents.ru) to return no peers — magnets then time out waiting for metadata.
- `PeerConnection.swift`: wait for the remote BitTorrent handshake before reading `supportsExtensions`. Upstream raced the inbound decode, so extension handshakes (BEP-9 ut_metadata) were never sent.
