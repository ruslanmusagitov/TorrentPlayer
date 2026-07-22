# TorrentPlayer — спецификация цели

Формат: [decision-system](../.cursor/rules/decision-system.mdc).

## Глобальная цель

| Поле | Значение |
| ---- | -------- |
| Цель | Сделать личное кроссплатформенное приложение (iOS, iPadOS, macOS), которое по magnet-ссылке начинает воспроизводить видео по мере скачивания (sequential/streaming), без публикации в App Store |
| Результаты | см. ниже |
| Срок | 2026-08-04 |

### В рамках цели

- Multiplatform SwiftUI на базе существующего `TorrentPlayer.xcodeproj`
- Magnet → метаданные → выбор видеофайла → воспроизведение во время загрузки
- История ранее добавленных торрентов
- Resume докачки (прогресс кусков переживает перезапуск)
- Установка на личные устройства (локально и/или TestFlight)
- UI по neo-brutalist макетам из `design/` (Kinetic Torrent)

### Вне цели

- Публикация в App Store / Mac App Store
- Download-then-play как основной сценарий
- Каталог/поиск торрентов, аккаунты, облако

### Уточнения

- Просмотр = стриминг (sequential download), не полный download-then-play
- Горизонт = личный MVP (не стор)
- История торрентов входит в результаты

### Дизайн

Источник: [`design/`](../design/).

| Что | Путь |
| --- | ---- |
| Токены / стиль (Kinetic Torrent) | [`design/kinetic_torrent/DESIGN.md`](../design/kinetic_torrent/DESIGN.md) |
| Load Magnet | [`design/load_magnet/`](../design/load_magnet/) (`code.html`, `screen.png`) |
| Select File | [`design/select_file/`](../design/select_file/) |
| Streaming Player | [`design/streaming_player/`](../design/streaming_player/) |
| Torrent History | [`design/torrent_history/`](../design/torrent_history/) |

UI-задачи сверяют визуал и структуру с этими файлами (цвета, типографика, hard shadows, 0 radius).

## Результаты

Цель достигнута к сроку, когда **все** пункты = да:

1. На iOS, iPadOS и macOS можно вставить magnet и получить список файлов торрента.
2. При нескольких видео в торренте можно выбрать файл для воспроизведения.
3. Воспроизведение начинается до полной загрузки файла (streaming/sequential) на тестовом magnet с известным видео — на каждой из трёх платформ.
4. Есть play/pause и отображение прогресса буфера/загрузки.
5. Можно просмотреть историю ранее добавленных торрентов (magnet / название).
6. Приложение устанавливается и запускается на личных устройствах (локальная сборка и/или TestFlight), без App Store.
7. После перезапуска докачка выбранного файла продолжается с уже скачанных кусков (resume), без полной перекачки.

## План

Подход по умолчанию: torrent-движок через SPM/обёртку libtorrent → sequential piece priority → локальный HTTP (или growing file) → `AVPlayer`.

| Задача | Issue | Результат цели | Дизайн | Результат задачи | Объём |
| ------ | ----- | -------------- | ------ | ---------------- | ----- |
| 1. Записать спецификацию в `docs/goal.md` | [#1](https://github.com/ruslanmusagitov/TorrentPlayer/issues/1) | все | — | файл с целью, результатами, сроком, планом | < 0.5 д |
| 2. Каркас UI по макетам: Load Magnet, Select File, Player, History (заглушки) + токены из DESIGN.md | [#2](https://github.com/ruslanmusagitov/TorrentPlayer/issues/2) | 1, 2, 5 | все 4 экрана + DESIGN.md | навигация и визуальный каркас на iOS/iPadOS/macOS | < 1 д |
| 3. Подключить torrent-движок и поднять сессию (сначала macOS) | [#3](https://github.com/ruslanmusagitov/TorrentPlayer/issues/3) | 1 | — | magnet принимается движком без краша | < 1 д |
| 4. По magnet показать список файлов (имя, размер) | [#4](https://github.com/ruslanmusagitov/TorrentPlayer/issues/4) | 1 | `design/select_file/` | список файлов в UI на macOS в стиле макета | < 1 д |
| 5. Фильтр видеорасширений + UI выбора файла | [#5](https://github.com/ruslanmusagitov/TorrentPlayer/issues/5) | 2 | `design/select_file/` | пользователь выбирает одно видео как в макете | < 0.5 д |
| 6. Sequential download выбранного файла (приоритет кусков) | [#6](https://github.com/ruslanmusagitov/TorrentPlayer/issues/6) | 3 | — | файл качается от начала к концу | < 1 д |
| 7. Мост стриминга в AVPlayer (локальный HTTP или growing file) | [#7](https://github.com/ruslanmusagitov/TorrentPlayer/issues/7) | 3 | — | playback стартует до 100% на macOS | < 1 д |
| 8. Play/pause и индикатор прогресса загрузки/буфера | [#8](https://github.com/ruslanmusagitov/TorrentPlayer/issues/8) | 4 | `design/streaming_player/` | контролы и прогресс работают и соответствуют макету | < 0.5 д |
| 9. Модель истории в SwiftData + запись при добавлении magnet | [#9](https://github.com/ruslanmusagitov/TorrentPlayer/issues/9) | 5 | — | записи сохраняются между запусками | < 0.5 д |
| 10. Экран истории: список и повторное открытие | [#10](https://github.com/ruslanmusagitov/TorrentPlayer/issues/10) | 5 | `design/torrent_history/` | список истории как в макете; из истории снова открывается торрент | < 0.5 д |
| 14. Resume: сохранять прогресс кусков между запусками | [#21](https://github.com/ruslanmusagitov/TorrentPlayer/issues/21) | 7 | — | повторный старт / открытие из истории докачивает с места остановки | < 1 д |
| 11. Довести torrent+player до рабочего e2e на iOS | [#11](https://github.com/ruslanmusagitov/TorrentPlayer/issues/11) | 1–4, 6, 7 | — | сценарий magnet→play на iPhone | < 1 д |
| 12. Проверить тот же сценарий на iPadOS | [#12](https://github.com/ruslanmusagitov/TorrentPlayer/issues/12) | 1–4, 6, 7 | — | сценарий magnet→play на iPad | < 0.5 д |
| 13. Финальная проверка macOS + чеклист локальной установки/TestFlight | [#13](https://github.com/ruslanmusagitov/TorrentPlayer/issues/13) | 6 | — | все 7 результатов отмечены да/нет | < 0.5 д |

Порядок: 1 → … → 10 → 14 → 11 → 12 → 13. После каждой задачи — строка в «Обратная связь».

## Обратная связь

| Выполненная задача | Фактический результат | Влияние на цель | Решение | Причина |
| ------------------ | --------------------- | --------------- | ------- | ------- |
| 1. Записать спецификацию в `docs/goal.md` | Файл создан, цель/результаты/срок/план зафиксированы | Спецификация готова к выполнению задач 2–13 | принять | Подтверждено пользователем |
| 1b. Уточнение плана: дизайн | В `docs/goal.md` добавлены секция Дизайн и привязки к `design/` у задач 2, 4, 5, 8, 10 | UI-задачи имеют единый источник макетов | принять | Локальный экспорт Stitch в `design/` |
| 2. Каркас UI по макетам | Токены Kinetic Torrent + 4 экрана-заглушки + навигация (sidebar/bottom); сборка macOS и iOS | Каркас для результатов 1, 2, 5 | принять | Merge PR #14 |
| 3. Torrent-движок и сессия (macOS) | SwiftTorrent SPM + TorrentEngine; magnet принимается без краша; unit-тесты | Основа для результата 1 | принять (после merge MR) | Issue #3 |
| 4. Список файлов по magnet (macOS) | Metadata → имена/размеры в Select File; патчи tracker/handshake; e2e на реальный magnet | Результат 1 на macOS | принять | Merge PR #16 |
| 5. Фильтр видео + UI выбора файла | videoFiles фильтр; selectedFile на engine; Select File выбирает одно видео; Stream Now только с видео; ошибка 2-го magnet показывается | Результат 2 | принять | Merge PR #17 |
| 6. Sequential download выбранного файла | PiecePicker sequential + file piece range; TorrentEngine prioritize после metadata и selectFile; vendor unit-тесты | Движение к результату 3 (порядок кусков) | принять | Merge PR #18 |
| 7. Мост стриминга в AVPlayer | Local HTTP + StreamingByteGate; AVPlayer для mp4/mov; MKV → VLC; playback до 100% на macOS (файл растёт, открывается частично) | Результат 3 на macOS | принять | Merge PR #19 |
| 1c. Уточнение плана: resume | Добавлены результат цели 7 и задача 14 ([#21](https://github.com/ruslanmusagitov/TorrentPlayer/issues/21)); порядок 10 → 14 → 11 | Докачка переживает перезапуск | принять | Запрос пользователя |
| 14. Resume: прогресс кусков | SwiftTorrent apply `resumeData` + `TorrentEngine` save/load в Application Support/Resume; unit-тесты | Результат цели 7 на macOS | принять (после merge PR) | Issue #21 |
| 15. Встроить SwiftVLC для MKV/AVI | SPM SwiftVLC; in-process VideoView по local HTTP; external VLC.app убран; play/pause из UI | Результат 3/4 для non-AVPlayer на macOS | принять (после merge PR) | Issue #22 |
