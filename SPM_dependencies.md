# SPM-зависимости TorrentPlayer

Источник версий: [`Package.resolved`](TorrentPlayer.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved) и [`Vendor/swift-torrent/Package.swift`](Vendor/swift-torrent/Package.swift).

## Сводка

| Категория | Количество |
|---|---|
| Прямые пакеты приложения (Xcode) | 2 — `SwiftTorrent`, `SwiftVLC` |
| Прямые зависимости SwiftTorrent | 2 — `swift-nio`, `swift-crypto` |
| Транзитивные remote-пакеты (SwiftTorrent) | 4 — atomics, collections, system, asn1 |
| Модули, которые реально `import`-ятся | `SwiftTorrent`, `SwiftVLC`, `NIOCore`, `NIOPosix`, `Crypto` |

`swift-nio-extras` удалён (не использовался) — вместе с ним ушла основная масса транзитивов (HTTP2, SSL, certificates, lifecycle и т.д.).

## Диаграмма

```mermaid
flowchart TB
  App[TorrentPlayer.app]

  subgraph directApp [Прямые зависимости приложения]
    ST[SwiftTorrent<br/>Vendor/swift-torrent]
    VLC[SwiftVLC 1.0.0]
  end

  subgraph directST [Прямые зависимости SwiftTorrent]
    NIO[swift-nio 2.101.3]
    Crypto[swift-crypto 3.15.1]
  end

  subgraph products [Используемые продукты]
    NIOCoreProd[NIOCore + NIOPosix<br/>peers DHT trackers disk I/O]
    CryptoProd[Crypto<br/>SHA1 SHA256 info-hash pieces]
    VLCProd[Player VideoView Volume<br/>StreamingPlayerView]
  end

  subgraph transitive [Транзитивные — нет import в коде]
    Atomics[swift-atomics 1.3.1]
    Collections[swift-collections 1.6.0]
    System[swift-system 1.7.4]
    ASN1[swift-asn1 1.7.1]
  end

  App --> ST
  App --> VLC
  ST --> NIO
  ST --> Crypto
  VLC --> VLCProd
  NIO --> NIOCoreProd
  Crypto --> CryptoProd

  NIO --> Atomics
  NIO --> Collections
  NIO --> System
  Crypto --> ASN1
```

## Прямые зависимости

| Пакет | Версия / источник | Роль | Назначение в проекте | Ключевые файлы |
|---|---|---|---|---|
| **SwiftTorrent** | local `Vendor/swift-torrent` | Прямая (app) | BitTorrent-движок: magnet, metadata, peers, DHT, trackers, sequential download, streaming | `TorrentPlayer/Torrent/TorrentEngine.swift`, `TPLog.swift`, `TorrentFileItem.swift` |
| **SwiftVLC** | 1.0.0 (`harflabs/SwiftVLC`) | Прямая (app) | Встроенный VLC для контейнеров вроде MKV/AVI (`Player`, `VideoView`, `Volume`) | `TorrentPlayer/Screens/StreamingPlayerView.swift` |
| **swift-nio** | 2.101.3 | Прямая (SwiftTorrent) | TCP peer-соединения, UDP DHT/trackers, event loops, disk I/O thread pool | `Session/`, `Peer/`, `DHT/`, `Tracker/`, `Storage/DiskIO.swift` |
| **swift-crypto** | 3.15.1 | Прямая (SwiftTorrent) | SHA-1 / SHA-256 для info-hash, piece verify, BEP-9 metadata | `Torrent/InfoHash.swift`, `PiecePicker/PieceManager.swift`, `Peer/MetadataExchange.swift` |

Продукты в `Package.swift` SwiftTorrent: `NIO`, `NIOCore`, `NIOPosix`, `Crypto`.  
`import NIO` в исходниках нет; фактически используются `NIOCore` и `NIOPosix`.

## Транзитивные зависимости

Не импортируются кодом приложения или Vendor. Попадают в граф из-за package-level зависимостей `swift-nio` и `swift-crypto`.

| Пакет | Версия | Почему в графе |
|---|---|---|
| swift-atomics | 1.3.1 | Зависимость `swift-nio` |
| swift-collections | 1.6.0 | Зависимость `swift-nio` |
| swift-system | 1.7.4 | Зависимость `swift-nio` |
| swift-asn1 | 1.7.1 | Зависимость `swift-crypto` |

## Заметки

- **`swift-nio-extras` удалён**: продукт `NIOExtras` не использовался, но тянул ~10 лишних пакетов.
- **SwiftVLC** внутри использует binary `libvlc` xcframework; его SPM-deps для docs/tests (`swift-docc-plugin`, `swift-custom-dump`) в app lockfile как runtime не фигурируют.
- Тестовые таргеты Xcode не линкуют SPM-продукты напрямую; `SwiftTorrent` доступен через app / `@testable import`.
- После смены зависимостей в Xcode: File → Packages → Reset Package Caches / Resolve Package Versions, чтобы обновить workspace `Package.resolved`.
