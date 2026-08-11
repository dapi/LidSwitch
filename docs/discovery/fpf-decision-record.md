# FPF decision record: направление LidSwitch

Дата: 2026-08-11. Метод: FPF `C.11 Decsn-CAL`.
Статус: продуктовые предпосылки ратифицированы владельцем 2026-08-11.

Этот документ превращает два feasibility-исследования в три отдельных решения.
Он не заменяет исходные исследования:

- [Mac App Store feasibility](./mac-app-store-feasibility.md);
- [iPhone companion feasibility](./iphone-companion-feasibility.md).

## Граница решения

`DecisionSubject` — владелец продукта LidSwitch. Уровень решения — продуктовый:
что финансировать следующим, при каких условиях и что не обещать пользователю.
Документ дает рекомендуемый `ChoiceResult`; принятие продуктовых предпосылок
остается за владельцем.

Разделены три вопроса:

1. Какую архитектуру дистрибуции развивать для следующего Mac-релиза?
2. Следует ли сейчас подавать LidSwitch в Mac App Store?
3. Следует ли начинать iPhone companion и с каким объемом?

Это важно: эксперимент, способный открыть Store в будущем, не должен задерживать
уже выбранную модернизацию direct build. А реализация companion не является тем
же решением, что проверка его сетевых и security-предпосылок.

## Общая система предпочтений

Используется пороговое правило, а не произвольная сумма баллов.

Жесткие критерии — вариант выбывает, если нарушен хотя бы один:

1. Не создает заведомого конфликта с опубликованными правилами выбранного канала.
2. Сохраняет заявленную основную ценность варианта.
3. Не представляет undocumented/private dependency как поддерживаемый публичный
   контракт: такая зависимость изолирована, явно маркирована и работает
   fail-closed при неизвестном состоянии.
4. Для remote control имеет fail-closed модель: authentication, replay
   protection, короткий TTL и явный user consent.
5. Не превращает best-effort канал в обещание безопасности или SLA.

После прохождения порогов предпочтение, в порядке важности:

1. безопасность пользователя и системы;
2. поддерживаемость на будущих macOS/iOS;
3. сохранение основной ценности LidSwitch;
4. минимальная операционная и продуктовая сложность;
5. скорость выхода.

Текущее `BeliefState` — проверенные официальные документы Apple и инспекция
текущего кода, но без письменного решения App Review и без real-device CloudKit
измерений. `OutcomeModel` — причинная модель: выбранная архитектура определяет
не только вероятность review, но также поверхность root-атаки, совместимость,
offline-поведение и объем обещаний пользователю.

## Состояние доказательств

| Утверждение | Уверенность | Область и ограничение |
|---|---|---|
| Mac App Store требует App Sandbox и запрещает root escalation | Высокая | Прямой текст актуальных App Review Guidelines; решение конкретного review не гарантируется |
| Текущие `sudoers` и `AuthorizationExecuteWithPrivileges` несовместимы с sandbox-моделью | Высокая | Подтверждено кодом и документацией Apple; deprecated API может продолжать работать в direct build |
| `SMAppService` улучшает direct helper architecture | Высокая | Публичный API Apple для embedded helpers; его наличие не является store-policy исключением |
| `disablesleep` и `powermode` — стабильный публичный контракт | Низкая | Ключи отсутствуют в поставляемой Apple man page; работа сегодня не доказывает будущую совместимость |
| Публичный thermal API дает severity, а не °C | Высокая для выбранного API | По найденным официальным API; утверждение «никакого API никогда нет» не делается |
| CloudKit private database подходит функционально | Средне-высокая | Auth/storage/subscriptions документированы; latency и background delivery для LidSwitch еще не измерены |
| Signed command + TTL блокирует replay и поздний sleep | Средняя до эксперимента | Архитектура обоснована, реализация и clock/reconnect edge cases еще не проверены |
| iPhone warning будет своевременным | Низкая | Apple прямо не гарантирует push delivery; это нельзя повысить кодом клиента до safety SLA |

Доказательства подлежат повторной проверке при изменении App Review Guidelines,
выходе новой major macOS, появлении публичного lid/temperature API или изменении
требований продукта.

## Решение 1: архитектура следующего Mac-релиза

### Замороженный набор вариантов

| ID | Вариант |
|---|---|
| M1 | Оставить текущий `sudo` + root helper + `sudoers` |
| M2 | Direct Developer ID build с embedded `SMAppService` daemon и XPC |
| M3 | Sandboxed monitor-only Mac App Store edition |
| M4 | Mac App Store app плюс отдельно устанавливаемый helper |

### Сравнение по порогам

| Вариант | Основная функция | Security debt | Канал без policy-конфликта | Результат |
|---|---|---|---|---|
| M1 | Сохраняет | Не проходит: persistent passwordless root path | Только direct | Выбывает перед M2 |
| M2 | Сохраняет | Проходит при XPC client validation и allowlist | Direct | Проходит |
| M3 | Не сохраняет управление lid policy | Низкий | Store | Выбывает как другой продукт |
| M4 | Сохраняет после второй установки | Высокая сложность и trust cost | Не проходит self-contained Store model | Выбывает |

### Ценность следующей проверки

Письменный ответ Apple о Store не меняет ближайший выбор между M1 и M2: M2
предпочтительнее для direct build независимо от ответа. Probe уже относится к
будущему каналу, а не к архитектуре ближайшего релиза.

### Choice rule и результат

Правило: среди вариантов, сохраняющих core value и проходящих security/channel
пороги, выбрать вариант с минимальным постоянным root exposure.

**`ChoiceResult = choose now: M2`.** Модернизировать Mac helper до
`SMAppService` + authenticated XPC, подписать Developer ID и notarize. Не ждать
Store-ответа перед этой работой.

Следующий вопрос уже не выбор, а план исполнения: spike `check-version`, затем
миграция allowlist операций, update/uninstall и regression matrix.

## Решение 2: подача текущего продукта в Mac App Store

### Замороженный набор вариантов

| ID | Вариант |
|---|---|
| S1 | Подать текущую сборку |
| S2 | Подать после замены installer на `SMAppService`, сохранив root/`pmset` |
| S3 | Не подавать текущий full-function продукт |

### Сравнение и probe-worthiness

- S1 нарушает несколько явных Store-порогов.
- S2 устраняет deprecated installer, но не устраняет root escalation и
  undocumented `pmset` keys.
- S3 сохраняет ресурсы и не создает ложного ожидания review-ready состояния.

Дешевый письменный запрос Apple способен изменить будущий набор вариантов, но
не делает S1 или S2 допустимыми сегодня. Его результатом может стать новый
вариант с подтвержденным исключением либо окончательное закрытие Store-направления.

### Choice rule и результат

Правило: не подавать build, пока он заведомо не проходит опубликованные hard
gates; отсутствие письменного отказа не считается разрешением.

**`ChoiceResult = choose now: S3`.** Не подавать текущий full-function LidSwitch
в Mac App Store и не финансировать Store port.

**Отдельный future-opening probe:** задать Apple DTS/App Review точный письменный
вопрос о `SMAppService` root daemon + `pmset disablesleep`. Probe ограничить двумя
днями подготовки; он не блокирует M2. Store-вопрос открывается заново только при
положительном ответе и наличии публично поддерживаемого lid-policy механизма.

## Решение 3: iPhone companion

### Замороженный набор вариантов

| ID | Вариант |
|---|---|
| I0 | Не делать companion |
| I1 | CloudKit read-only: last seen, lid mode, charge, thermal severity |
| I2 | I1 + paired signed remote sleep и best-effort thermal alert |
| I3 | Собственный backend + APNs |
| I4 | CloudKit companion с точной температурой через private APIs |

### Сравнение по порогам

| Вариант | Product value | Public contracts | Safety/security | Scope | Результат |
|---|---|---|---|---|---|
| I0 | Не реализует запрос | Проходит | Проходит | Минимальный | Резервный исход |
| I1 | Частичный | Проходит | Проходит | Малый | Допустимый fallback |
| I2 | Полный MVP в заявленных границах | Проходит, если «температура» = severity | Пока не доказано экспериментом | Средний | Условный лидер |
| I3 | Полный и более наблюдаемый | Проходит | Можно построить надежнее, но push все равно best effort | Большой | Избыточен для MVP |
| I4 | Формально дает °C | Не проходит | Private dependency | Средний | Выбывает |

### Какой пробел еще может изменить выбор

I2 выигрывает по ценности и размеру только если одновременно верны три
проверяемые предпосылки:

1. Подписанные mock commands никогда не исполняются после TTL, повторно или для
   другого Mac.
2. Status/ack дают приемлемый foreground UX на реальных сетях.
3. Продукт честно маркирует push как best effort и сохраняет local Mac alert как
   главный safety path.

Пункты 1–2 требуют дешевого 2–3-дневного spike и способны понизить выбор до I1
или I0. Поэтому дальнейшая проверка имеет высокую ценность информации при
ограниченной стоимости. Background delivery не имеет критерия «100%»: Apple не
дает такой гарантии, и эксперимент не может превратить наблюдаемую выборку в SLA.

### Choice rule и результат

Правило: выбирать I2 только после прохождения security и foreground-UX gates;
при провале remote-command gate откатиться к I1, а не ослаблять authentication,
TTL или replay protection.

**`ChoiceResult = probe again`.** Выполнить ровно CloudKit/security spike из
[companion feasibility](./iphone-companion-feasibility.md#ближайший-эксперимент).

Closure после spike:

- все invalid/replay/expired commands отклонены и foreground status приемлем —
  **choose I2**;
- command safety не доказана, но read-only status полезен — **choose I1**;
- owner требует °C, гарантированный alert или cross-account в первой версии —
  **reject current set** и заново сформировать варианты/бюджет;
- I2 выбран — дальнейший UI/implementation plan является исполнением, не новым
  выбором.

## Итоговый портфель

| Поток | FPF disposition | Что делать сейчас |
|---|---|---|
| Mac architecture | `choose now` | M2: direct notarized build, `SMAppService` + XPC |
| Mac App Store submission | `choose now` | S3: не подавать и не финансировать port сейчас |
| iPhone companion | `probe again` | 2–3-дневный CloudKit/security spike; затем I2/I1/reject по gates |

Это не скрытая рекомендация делать оба production-потока одновременно.
Mock-command CloudKit spike можно провести независимо, но production remote
control не должен подключаться к текущему `sudoers` helper. При одном доступном
execution slot сначала M2, затем реализация выбранного companion-варианта.

## Ратифицированные продуктовые предпосылки

Владелец продукта утвердил 2026-08-11:

1. Core value важнее присутствия в Mac App Store.
2. Security и поддерживаемые публичные API важнее точной температуры в °C.
3. Best-effort remote alert приемлем как удобство, но не как safety guarantee.
4. Первый companion ограничен одним Mac, одним iPhone и одним iCloud account.
5. Автоматический sleep на `critical` не входит в MVP без отдельного opt-in
   решения о риске потери несохраненной работы.

Изменение любой предпосылки повторно открывает соответствующий `ChoiceResult`.
В частности, требование Store-first меняет набор Mac-вариантов, а требование °C
или гарантированного remote alert требует отклонить текущий companion OptionSet,
а не ослаблять public-API и safety gates.
