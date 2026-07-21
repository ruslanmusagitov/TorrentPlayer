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
- Установка на личные устройства (локально и/или TestFlight)

### Вне цели

- Публикация в App Store / Mac App Store
- Download-then-play как основной сценарий
- Каталог/поиск торрентов, аккаунты, облако

### Уточнения

- Просмотр = стриминг (sequential download), не полный download-then-play
- Горизонт = личный MVP (не стор)
- История торрентов входит в результаты

## Результаты

Цель достигнута к сроку, когда **все** пункты = да:

1. На iOS, iPadOS и macOS можно вставить magnet и получить список файлов торрента.
2. При нескольких видео в торренте можно выбрать файл для воспроизведения.
3. Воспроизведение начинается до полной загрузки файла (streaming/sequential) на тестовом magnet с известным видео — на каждой из трёх платформ.
4. Есть play/pause и отображение прогресса буфера/загрузки.
5. Можно просмотреть историю ранее добавленных торрентов (magnet / название).
6. Приложение устанавливается и запускается на личных устройствах (локальная сборка и/или TestFlight), без App Store.

## План

Подход по умолчанию: torrent-движок через SPM/обёртку libtorrent → sequential piece priority → локальный HTTP (или growing file) → `AVPlayer`.

| Задача | Issue | Результат цели | Результат задачи | Объём |
| ------ | ----- | -------------- | ---------------- | ----- |
| 1. Записать спецификацию в `docs/goal.md` | [#1](https://github.com/ruslanmusagitov/TorrentPlayer/issues/1) | все | файл с целью, результатами, сроком, планом | < 0.5 д |
| 2. Каркас UI: ввод magnet, список файлов, плеер, история (заглушки) | [#2](https://github.com/ruslanmusagitov/TorrentPlayer/issues/2) | 1, 2, 5 | навигация собирается на iOS/iPadOS/macOS | < 1 д |
| 3. Подключить torrent-движок и поднять сессию (сначала macOS) | [#3](https://github.com/ruslanmusagitov/TorrentPlayer/issues/3) | 1 | magnet принимается движком без краша | < 1 д |
| 4. По magnet показать список файлов (имя, размер) | [#4](https://github.com/ruslanmusagitov/TorrentPlayer/issues/4) | 1 | список файлов в UI на macOS | < 1 д |
| 5. Фильтр видеорасширений + UI выбора файла | [#5](https://github.com/ruslanmusagitov/TorrentPlayer/issues/5) | 2 | пользователь выбирает одно видео | < 0.5 д |
| 6. Sequential download выбранного файла (приоритет кусков) | [#6](https://github.com/ruslanmusagitov/TorrentPlayer/issues/6) | 3 | файл качается от начала к концу | < 1 д |
| 7. Мост стриминга в AVPlayer (локальный HTTP или growing file) | [#7](https://github.com/ruslanmusagitov/TorrentPlayer/issues/7) | 3 | playback стартует до 100% на macOS | < 1 д |
| 8. Play/pause и индикатор прогресса загрузки/буфера | [#8](https://github.com/ruslanmusagitov/TorrentPlayer/issues/8) | 4 | контролы и прогресс работают | < 0.5 д |
| 9. Модель истории в SwiftData + запись при добавлении magnet | [#9](https://github.com/ruslanmusagitov/TorrentPlayer/issues/9) | 5 | записи сохраняются между запусками | < 0.5 д |
| 10. Экран истории: список и повторное открытие | [#10](https://github.com/ruslanmusagitov/TorrentPlayer/issues/10) | 5 | из истории снова открывается торрент | < 0.5 д |
| 11. Довести torrent+player до рабочего e2e на iOS | [#11](https://github.com/ruslanmusagitov/TorrentPlayer/issues/11) | 1–4, 6 | сценарий magnet→play на iPhone | < 1 д |
| 12. Проверить тот же сценарий на iPadOS | [#12](https://github.com/ruslanmusagitov/TorrentPlayer/issues/12) | 1–4, 6 | сценарий magnet→play на iPad | < 0.5 д |
| 13. Финальная проверка macOS + чеклист локальной установки/TestFlight | [#13](https://github.com/ruslanmusagitov/TorrentPlayer/issues/13) | 6 | все 6 результатов отмечены да/нет | < 0.5 д |

Порядок: 1 → 2 → … → 13. После каждой задачи — строка в «Обратная связь».

## Обратная связь

| Выполненная задача | Фактический результат | Влияние на цель | Решение | Причина |
| ------------------ | --------------------- | --------------- | ------- | ------- |
| 1. Записать спецификацию в `docs/goal.md` | Файл создан, цель/результаты/срок/план зафиксированы | Спецификация готова к выполнению задач 2–13 | принять | Подтверждено пользователем |
