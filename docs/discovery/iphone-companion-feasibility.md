# Feasibility: минимальный iPhone companion для LidSwitch

Дата проверки: 2026-08-11. Статус: decision-ready.

## Решение

**GO с ограниченным MVP**, если:

- Mac и iPhone используют один iCloud account;
- «температура» в продукте означает публичный `thermalState`, а не градусы;
- remote sleep — best-effort команда только для бодрствующего и доступного Mac,
  с коротким сроком действия и явным подтверждением пользователя;
- локальное предупреждение на Mac остается главным: iPhone alert не является
  гарантированным каналом безопасности.

**NO-GO**, если MVP обязан показывать точную температуру в °C, гарантированно
доставлять перегрев-alert или будить/усыплять Mac при любой сетевой ситуации.
Apple не публикует API точной температуры Mac, а CloudKit/APNs работают по
модели best effort.

## Границы данных

Минимальная карточка Mac:

- имя устройства, app version;
- `lastUpdated` и производный статус «на связи / данные устарели»;
- текущий LidSwitch mode: closed-lid work on/off/unknown;
- заряд в процентах и питание battery/AC;
- thermal state: normal / elevated / serious / critical;
- последняя принятая remote-sleep команда и ее результат.

Заряд и источник питания доступны через публичный IOKit Power Sources API:
он предоставляет состояние батарей/UPS и уведомления об изменениях
([IOPowerSources.h](https://developer.apple.com/documentation/iokit/iopowersources_h)).
Для companion следует использовать этот контракт, а не недокументированные
`AppleSmartBattery` IORegistry keys текущего forecast-кода.

Публичный thermal API возвращает только четыре уровня. `critical` означает, что
устройство существенно ограничивает производительность и должно остыть
([ProcessInfo.ThermalState](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum));
изменения можно получать через notification
([ProcessInfo](https://developer.apple.com/documentation/foundation/processinfo)).
Называть эти уровни градусами или вычислять °C из private SMC/IORegistry данных
нельзя: это будет ложная точность и unsupported dependency.

## Варианты связи

| Вариант | Вне домашней сети | Свой backend | Auth | Оценка |
|---|---:|---:|---|---|
| CloudKit private database + subscriptions | Да | Нет | iCloud account + pairing key | **Рекомендуется для MVP** |
| Bonjour/Network.framework по LAN | Нет | Нет | Нужно проектировать pairing/TLS | Полезное последующее ускорение, не remote companion |
| Собственный API + APNs provider | Да | Да | Своя учетная запись/device tokens | Больше контроля и observability, слишком дорого для MVP |

CloudKit private database доступна только текущему пользователю и требует
iCloud account
([privateCloudDatabase](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase)).
Это дает минимальную account-level аутентификацию без собственного сервера.
Чувствительные поля следует создавать сразу через `CKRecord.encryptedValues`:
они шифруются на устройстве перед загрузкой и не индексируются
([Encrypting User Data](https://developer.apple.com/documentation/cloudkit/encrypting-user-data),
[encryptedValues](https://developer.apple.com/documentation/cloudkit/ckrecord/encryptedvalues)).

## Рекомендуемая архитектура MVP

```text
Mac menu-bar app ── status / alert / ack ──▶ CloudKit private zone
Mac menu-bar app ◀── short-lived command ── iPhone app
                                      └──── CloudKit subscription → push hint
```

Разделить записи по одному владельцу записи:

- `MacStatus/{macID}` — пишет Mac; iPhone читает и кеширует;
- `ThermalEvent/{eventID}` — пишет Mac; iPhone получает visual push hint;
- `Command/{commandID}` — пишет iPhone; Mac читает;
- `CommandAck/{commandID}` — пишет Mac; iPhone читает.

Так меньше CloudKit conflicts. Push — только сигнал перечитать записи, а не
источник истины: Apple предупреждает, что CloudKit может coalesce notifications
([CKQuerySubscription](https://developer.apple.com/documentation/cloudkit/ckquerysubscription)).
На foreground, pull-to-refresh и после push обе стороны всегда fetch-ят текущее
состояние. Локальный cache обязателен: CloudKit предоставляет лишь минимальное
offline caching
([CloudKit overview](https://developer.apple.com/documentation/cloudkit)).

Mac обновляет status по событиям и heartbeat, например раз в 60 секунд, но не
чаще без измеренной необходимости. iPhone считает данные stale после 2–3
пропущенных heartbeat. Отсутствие heartbeat означает только «Mac недоступен»;
оно не доказывает, что Mac спит, выключен или потерял сеть.

## Security и аутентификация remote sleep

iCloud private database ограничивает круг аккаунтом, но удаленный power control
требует device-level защиты:

1. iPhone создает P-256 signing key в Secure Enclave; Apple CryptoKit
   поддерживает создание ключа с `SecAccessControl` и ECDSA signature
   ([SecureEnclave.P256.Signing.PrivateKey](https://developer.apple.com/documentation/cryptokit/secureenclave/p256/signing/privatekey)).
2. Pairing запускается на обоих устройствах, показывает один короткий код и
   требует подтверждения на Mac. Mac сохраняет (pins) public key локально; его
   нельзя молча заменить записью из CloudKit.
3. Перед отправкой sleep iPhone требует Face ID/Touch ID/passcode через user
   presence. Apple рекомендует user presence для чувствительных действий
   ([Keychain access control](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility)).
4. Подписывается канонический payload:
   `version, commandID, macID, action=sleep, issuedAt, expiresAt, nonce`.
5. Mac проверяет pinned key, signature, target, clock window, TTL ≤ 60 секунд и
   отсутствие `commandID`/nonce в persistent replay cache. Команда выполняется
   ровно один раз.
6. Remote control по умолчанию выключен; его включает локальный пользователь
   Mac. Unpair удаляет pinned key и отклоняет все старые команды.

Private key не синхронизировать между устройствами. Device-only key material
недоступен после переноса backup на другое устройство
([`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly));
после замены iPhone нужна повторная pairing.

Для сна не нужно расширять root helper: документированный `IOPMSleepSystem`
разрешает запрос root **или console user**, которым является активное menu-bar
приложение
([IOPMSleepSystem](https://developer.apple.com/documentation/iokit/1557121-iopmsleepsystem)).
Это сохраняет сетевой код вне privileged helper. Перед вызовом Mac создает
`accepted` ack в CloudKit; после начала сна нельзя обещать подтверждение
фактического перехода.

## Перегрев-alert

- На Mac при переходе в `serious`/`critical` немедленно показать local
  notification и предложить выключить closed-lid work; для `critical` продукту
  нужен отдельный owner-approved auto-sleep policy.
- Mac пишет `ThermalEvent`. iPhone subscription может запросить visual
  high-priority notification; такие уведомления требуют разрешения пользователя
  ([CKDatabaseNotification](https://developer.apple.com/documentation/cloudkit/ckdatabasenotification)).
- Текст push должен быть консервативным: «Mac сообщает критическое тепловое
  состояние; откройте LidSwitch», а не точная температура.
- Push нельзя считать сигнализацией безопасности. APNs — best effort, может
  задерживать, объединять или не доставлять notifications
  ([Sending notification requests to APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)).

## Поведение без сети

**Mac offline:** локальное переключение, thermal monitoring и local alert
продолжаются. Последний status сохраняется локально; при возврате сети
публикуется только актуальный snapshot и еще не устаревшие события.

**iPhone offline:** показывает кеш с абсолютным временем обновления и заметной
меткой `Stale`. Refresh возвращает понятную ошибку. Кнопка Sleep disabled, если
нет сети или status уже stale; команда не ставится в долговечную очередь.

**Сеть пропала после отправки:** созданная команда все равно истекает через 60
секунд. Mac никогда не исполняет просроченный sleep после позднего reconnect.
iPhone показывает `Pending` до TTL, затем `Not confirmed`; отсутствие ack не
равно неисполнению.

**Mac уже спит/off:** command consumer не работает, поэтому remote sleep и тем
более remote wake невозможны. MVP не обещает Wake-on-LAN.

CloudKit network failures повторяются с exponential backoff и jitter; для
rate-limit/service-unavailable учитывается `retryAfterSeconds`
([CKError.retryAfterSeconds](https://developer.apple.com/documentation/cloudkit/ckerror/retryafterseconds)).
Background/silent pushes не гарантируются и могут быть throttled
([Pushing background updates](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)).

## Риски

- **Semantic:** пользователь ожидает °C, а публичный API дает только thermal
  severity. Это нужно решить названием и onboarding.
- **Delivery:** предупреждение может прийти поздно или не прийти; local Mac alert
  остается единственным оперативным каналом.
- **False state:** heartbeat не различает сон, power-off и отсутствие сети.
- **Remote-control abuse:** украденный разблокированный iPhone или replay может
  усыпить Mac; нужны user presence, signature, TTL, pinning и one-time IDs.
- **Data loss/account:** без iCloud companion недоступен; reset iCloud encrypted
  keys требует очистки zone и повторной pairing.
- **Current Mac internals:** lid mode/forecast используют undocumented keys;
  companion не должен расширять зависимость и обязан публиковать `unknown` при
  невозможности чтения.
- **Safety policy:** автоматический сон на `critical` может прервать работу, но
  отсутствие сна может увеличить нагрев. Это продуктовая, не техническая
  развилка.

## Рекомендуемый MVP

Один Mac + один iPhone на одном iCloud account:

1. Read-only card: last seen, lid mode, charge/power, thermal severity.
2. Cached state, stale/offline UI и manual refresh.
3. `serious`/`critical` visual notification как best effort плюс local Mac alert.
4. Opt-in paired remote sleep с user presence, signed command, 60-second TTL и
   ack `accepted/rejected/expired`.
5. Никаких точных градусов, remote wake, нескольких Mac/iPhone, sharing между
   Apple IDs, собственного backend и LAN fast path.

## Ближайший эксперимент

**CloudKit reliability spike на реальном Mac + iPhone, 2–3 дня, без полноценного
UI и без настоящего сна на первом этапе:**

1. Создать private custom zone и четыре record types из схемы выше; sensitive
   payload fields сразу сделать encrypted.
2. Синтетически менять charge/thermal values и измерить foreground fetch,
   background push и visual alert latency на Wi‑Fi, cellular, после airplane
   mode и после force-quit iPhone app.
3. Прогнать 100 подписанных mock-sleep commands, включая duplicate, tampered,
   wrong-target и expired; ни одна невалидная команда не должна дать accepted.
4. Затем разрешить один реальный `IOPMSleepSystem` call и проверить, что ack
   сохранен до сна, а просроченная команда после wake/reconnect не исполняется.

Критерии GO: median foreground status < 5 секунд при доступной сети; ни одного
replay/expired execution; понятный stale UX; product owner принимает, что push
не имеет SLA и thermal state заменяет °C. Результаты background push записываются
как наблюдение, но не превращаются в гарантию.

## Решения владельца продукта

1. Принять формулировку «тепловое состояние» без градусов или остановить MVP.
2. Ограничить первую версию одним Mac и одним iPhone на одном iCloud account либо
   сразу финансировать multi-device/sharing и более сложную модель отзыва ключей.
3. Подтвердить best-effort характер iPhone alerts и remote sleep без SLA.
4. Выбрать реакцию на `critical`: только alert, предложение remote sleep или
   автоматический локальный sleep. Последний вариант требует отдельного явного
   opt-in из-за риска потери несохраненной работы.
