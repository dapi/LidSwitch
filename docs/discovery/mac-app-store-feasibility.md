# Feasibility: LidSwitch в Mac App Store

Дата проверки: 2026-08-11. Статус: decision-ready.

FPF-выбор и правило закрытия решения вынесены в
[общий decision record](./fpf-decision-record.md).

## Решение

**NO-GO для публикации текущего продукта в Mac App Store.** Текущая ценность
LidSwitch зависит от изменения системных power settings с правами root, а правила
магазина прямо требуют App Sandbox и запрещают запрос эскалации до root. Замена
самописной установки helper на `SMAppService` улучшит прямую дистрибуцию, но не
устранит store-policy конфликт.

**GO для прямой дистрибуции с Developer ID и notarization.** Перед расширением
продукта стоит заменить устаревшую установку через
`AuthorizationExecuteWithPrivileges` и `/etc/sudoers.d` на embedded launch daemon,
регистрируемый через `SMAppService`, с узким XPC-интерфейсом.

Вывод основан на опубликованных правилах, а не является гарантией решения App
Review. Изменить NO-GO может только новый публичный API Apple или письменное
подтверждение применимого исключения от Apple.

## Что существует сейчас

Текущая сборка:

- запускает `/usr/bin/pmset -a disablesleep 0|1` и
  `/usr/bin/pmset -a powermode 0|1|2` из root-owned helper;
- при установке копирует helper в `/Library/PrivilegedHelperTools` и создает
  постоянное правило `NOPASSWD` в `/etc/sudoers.d/lidswitch`;
- получает root один раз через `AuthorizationExecuteWithPrivileges`;
- не имеет App Sandbox entitlement;
- читает `SleepDisabled`, `AppleSmartBattery` и другие IORegistry properties,
  часть которых не оформлена как документированный публичный контракт Apple.

Локальная проверка поставляемой Apple man page `pmset(1)` на macOS 26.5.1
(25F80) показала: `pmset` и необходимость root для изменения settings описаны,
но ключи `disablesleep` и `powermode` в man page не перечислены. Следовательно,
это не только вопрос привилегий: основная функция опирается на недокументированные
ключи и может измениться без совместимости или стать причиной отказа App Review.
Apple Support также направляет пользователей именно к man page за списком
поддерживаемых команд [`pmset`](https://support.apple.com/en-ie/guide/mac-help/-mchl40376151/mac).

## Ограничения Apple

1. Для Mac App Store обязателен App Sandbox
   ([App Sandbox](https://developer.apple.com/documentation/security/app-sandbox),
   [настройка capability](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)).
2. В sandbox запрещено использовать Authorization Services
   ([Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)).
3. Mac App Store app должна быть единым self-contained bundle, не может
   устанавливать код или ресурсы в shared locations и не может запрашивать root
   ([App Review Guidelines 2.4.5 (ii), (v)](https://developer.apple.com/app-store/review/guidelines/)).
4. Общие правила также запрещают исполнять или устанавливать код, меняющий
   функциональность вне app bundle/container
   ([App Review Guidelines 2.5.2](https://developer.apple.com/app-store/review/guidelines/)).
5. Embedded command-line tool sandboxed app должен наследовать sandbox; это не
   способ вынести привилегии из контейнера
   ([Apple sandbox guidance](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)).
6. Используемый сейчас `AuthorizationExecuteWithPrivileges` deprecated; Apple
   рекомендует launchd helper и Service Management
   ([API documentation](https://developer.apple.com/documentation/security/authorizationexecutewithprivileges)).
7. `SMAppService` действительно умеет регистрировать embedded login items,
   agents и daemons, включая замену ручной установки в `/Library/LaunchDaemons`
   ([SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)).
   Но эта техническая возможность не отменяет отдельный запрет App Review на
   root escalation.
8. Приложение не должно создавать чрезмерный нагрев или риск повреждения
   устройства
   ([App Review Guidelines 2.4.2](https://developer.apple.com/app-store/review/guidelines/)).
   Для LidSwitch обязательны явное предупреждение и безопасное состояние перед
   переноской Mac в закрытой сумке.

## Варианты архитектуры

| Вариант | Сохраняет основную функцию | Шанс Mac App Store | Оценка |
|---|---:|---:|---|
| Текущий `sudo` + helper + `sudoers` | Да | Практически нулевой | Не подавать в Store; модернизировать даже для direct distribution |
| `SMAppService` launch daemon + XPC | Да | Практически нулевой из-за root и undocumented `pmset` keys | Рекомендуется для Developer ID build |
| Sandboxed app без helper | Нет: может мониторить, но не менять `disablesleep` | Реальный | Отдельный урезанный продукт, а не текущий LidSwitch |
| MAS shell + отдельно скачиваемый helper | Формально да после второй установки | Очень низкий | Не рекомендовать: нарушает self-contained модель и ухудшает доверие/UX |
| Публичный API предотвращения idle sleep | Нет: idle sleep не равен политике закрытия крышки | Возможен | Не считать заменой без аппаратного эксперимента и подтверждения Apple |

`ProcessInfo`/power assertions могут предотвращать idle sleep во время работы
процесса, но Apple описывает их именно как механизм idle sleep
([ProcessInfo](https://developer.apple.com/documentation/foundation/processinfo)).
Нет основания считать это публичной заменой system-wide `disablesleep` при
закрытой крышке.

## Рекомендуемая direct-distribution архитектура

- App и helper остаются в одном подписанном app bundle.
- `SMAppService` регистрирует launch daemon; никаких файлов в `sudoers` и
  passwordless `sudo`.
- App общается с daemon только по XPC. Интерфейс — закрытый enum операций без
  произвольных аргументов: read version, set lid mode, set energy mode.
- Daemon проверяет code-signing identity входящего XPC connection и повторно
  валидирует каждую операцию. Apple DTS рекомендует проверять XPC connection и
  user intent; bundle protection защищает embedded daemon
  ([официальный ответ Apple DTS](https://developer.apple.com/forums/thread/801222)).
- Установка/обновление helper требует явного системного consent. Отмена не
  ломает read-only состояние приложения.
- Helper не читает пользовательские файлы, сеть или CloudKit и не принимает
  shell strings/paths.
- Приложение хранит last-known state только как UI cache; источником истины
  остается фактическое состояние macOS.

Это уменьшает поверхность атаки, но не превращает undocumented `pmset` keys в
поддерживаемый API. На каждом major macOS нужен hardware regression test и
fail-closed: неизвестное состояние не должно показываться как «безопасно».

## Поведение без сети

Основная функция полностью локальна и не должна зависеть от сети. Установка и
работа helper, чтение состояния, переключение и предупреждение о нагреве должны
работать offline. Notarization нужна при выпуске, но временная недоступность сети
после установки не должна менять lid policy. Обновление не должно автоматически
переустанавливать helper без системного consent.

## Риски

- **Review blocker:** root escalation, запись в shared locations и отсутствие
  sandbox — прямые конфликты с опубликованными правилами.
- **Compatibility:** `disablesleep`, `powermode` и IORegistry property names не
  документированы как публичный стабильный контракт.
- **Security:** постоянный `NOPASSWD` плюс root executable повышают последствия
  подмены или ошибки проверки клиента; текущий CLI-вызов не аутентифицирует
  вызывающий процесс.
- **Safety:** оставленный включенным Mac с закрытой крышкой в сумке может
  разрядиться и перегреться.
- **Product split:** отдельная monitor-only Store edition создаст две разные
  ценности, поддержку и ожидания пользователей.

## Рекомендуемый MVP

Не делать Mac App Store edition. Ближайший релиз прямой дистрибуции:

1. Developer ID signing + hardened runtime + notarization.
2. `SMAppService`/XPC helper вместо `AuthorizationExecuteWithPrivileges`, ручного
   копирования и `sudoers`.
3. Тот же минимальный allowlist; проверка подписи клиента и явный consent.
4. Диагностика unsupported state и безопасное предупреждение при каждом
   включении closed-lid work.
5. Матрица реальных Apple silicon MacBook × поддерживаемые версии macOS.

## Ближайший эксперимент

**Policy/technical spike, максимум 2 рабочих дня, без продуктового кода:**

1. Собрать sandboxed probe, который только читает публичные power-source данные
   и пытается вызвать текущие пути; сохранить sandbox violation logs.
2. Отдельно собрать Developer ID probe с embedded `SMAppService` daemon и одним
   безвредным XPC `check-version`, проверить install/update/uninstall и проверку
   code signature на чистом Mac.
3. Отправить Apple DTS/App Review письменный вопрос с точной архитектурой:
   допускается ли Mac App Store app с `SMAppService` root launch daemon для
   `pmset disablesleep`? До положительного письменного ответа бюджет на Store
   port не выделять.

Критерий успеха: не «helper технически запускается», а Apple письменно допускает
архитектуру и подтвержден публичный стабильный способ менять нужную lid policy.
Без обоих условий решение остается NO-GO.

## Решения владельца продукта

1. Принять direct distribution как основной канал или финансировать отдельную
   monitor-only Store edition с другой ценностью.
2. Подтвердить, что модернизация helper и notarization приоритетнее iPhone
   companion: новый remote-контур не должен строиться поверх текущего `sudoers`.
3. Утвердить safety policy для closed-lid work: частота предупреждений и
   допустимость автоматического отключения режима при critical thermal state.
