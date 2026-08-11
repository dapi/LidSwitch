# M2 spike: `SMAppService` daemon + authenticated XPC

Дата: 2026-08-11. Ветка: `agent/lidswitch-discovery`.
Статус: **реализация готова; live lifecycle gate ожидает Developer ID + notarization**.

## Цель

Проверить минимальный вертикальный срез будущей M2-архитектуры, не перенося
power operations и не удаляя текущий helper:

1. embedded launch daemon регистрируется через `SMAppService`;
2. app вызывает единственную XPC-операцию `check-version`;
3. daemon исполняется как root;
4. daemon принимает только подписанный LidSwitch client;
5. install/update/unregister проходят через системный lifecycle.

## Что реализовано

- Новый `LidSwitchDaemon` без GUI, shell execution, файлового или сетевого
  доступа. Ответ: `m2-spike-v1;euid=<uid>`.
- Plist в `Contents/Library/LaunchDaemons` с `BundleProgram` и on-demand
  `MachServices`.
- Общий Objective-C-compatible XPC protocol.
- Двусторонняя проверка code signature через системные
  `NSXPCListener.setConnectionCodeSigningRequirement` и
  `NSXPCConnection.setCodeSigningRequirement`.
- В Developer ID build requirement связывает peer с точным bundle ID и Team ID.
  В ad-hoc build fallback проверяет только bundle ID и явно маркируется как
  **not production-safe**.
- Диагностический раздел `M2 daemon spike` в меню: status, register/open
  approval settings, check version, unregister.
- CLI диагностика тем же подписанным app executable:

  ```sh
  /Applications/LidSwitch.app/Contents/MacOS/LidSwitch --m2-daemon-status
  /Applications/LidSwitch.app/Contents/MacOS/LidSwitch --m2-check-version
  ```

- Отдельный `LidSwitchUnauthorizedProbe`, подписываемый той же build identity,
  но с другим signing identifier, для негативного XPC-теста.
- `Scripts/verify-m2-spike.sh` проверяет layout, plist, подписи, несовпадение
  identifier unauthorized probe, одинаковый Team ID всех peer binaries в
  Developer ID build и существующие core checks.
- Legacy `LidSwitchHelper`, его UI и `/etc/sudoers.d` workflow не изменены и не
  удаляются этим spike.

## Основание Apple

- `SMAppService.daemon(plistName:)` ищет plist именно в
  `Contents/Library/LaunchDaemons`
  ([Apple documentation](https://developer.apple.com/documentation/servicemanagement/smappservice/daemon%28plistname%3A%29)).
- `BundleProgram` задает bundle-relative executable; Apple рекомендует держать
  daemon-owning app в `/Applications`. В текущем SDK также указано, что apps с
  LaunchDaemons должны быть notarized
  ([SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)).
- LaunchDaemon становится runnable только после admin approval
  ([register](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29)).
- Apple предоставляет code-signing requirements непосредственно на XPC
  connection/listener
  ([connection](https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement%28_%3A%29),
  [listener](https://developer.apple.com/documentation/foundation/nsxpclistener/setconnectioncodesigningrequirement%28_%3A%29)).
- При изменении daemon executable/plist его нужно re-register; для измененного
  executable Apple рекомендует сначала unregister
  ([Apple DTS](https://developer.apple.com/forums/thread/783539)).

## Автоматически проверено

На macOS 26.5.1 (25F80), Swift 6.3.2:

```text
swift build
Build complete

./Scripts/verify-m2-spike.sh debug
PASS: M2 bundle layout, launchd plist, signatures, peer identity checks,
      status path, and existing core checks
All LidSwitchCore checks passed

./Scripts/verify-m2-spike.sh release
PASS: M2 bundle layout, launchd plist, signatures, peer identity checks,
      status path, and existing core checks

./Scripts/package-release.sh
LidSwitch-0.7.0-macos-arm64.zip
shasum: OK
```

Проверены:

- оба новых executable собираются;
- daemon и legacy helper находятся в ожидаемых местах;
- launchd plist валиден и содержит точные label/path/Mach service;
- app bundle проходит strict code-signature verification;
- daemon satisfies `identifier "me.dapi.LidSwitch.Daemon"`;
- probe satisfies только свой identifier
  `me.dapi.LidSwitch.UnauthorizedProbe`;
- unauthorized probe не satisfies app identifier requirement;
- при наличии Team ID verifier требует его точного совпадения у app, daemon и
  probe;
- legacy core checks остаются зелеными.
- release archive содержит daemon и launchd plist, но не содержит diagnostic
  unauthorized probe; распакованный app проходит strict signature verification.

## Что нельзя честно подтвердить на текущей машине

В login keychain нет ни одной valid code-signing identity:

```text
security find-identity -v -p codesigning
0 valid identities found
```

Поэтому локальная сборка ad-hoc, не notarized. `SMAppService.status` для нее
возвращает `Not found in app bundle`, хотя `Bundle.main` и static layout корректны.
Live registration намеренно не запускалась: это не дало бы production-grade
проверку и могло бы оставить сломанную Background Task Management registration.

Это не дефект, который следует обходить ослаблением подписи. Apple требует
code-signed app для `SMAppService`, admin approval для daemon и notarization для
app с LaunchDaemon. Production authentication также требует реальный Team ID;
bundle-ID-only ad-hoc signature можно подделать другой ad-hoc сборкой.

## Live lifecycle gate

Нужен Mac с установленным Developer ID Application certificate и настроенным
`notarytool` profile.

1. Собрать с hardened runtime:

   ```sh
   LIDSWITCH_CODESIGN_IDENTITY="Developer ID Application: …" \
     ./Scripts/build-app.sh release
   ```

2. Notarize и staple app, затем поместить его в `/Applications`.
3. Открыть LidSwitch → `M2 daemon spike` → Register, разрешить background item
   с admin authentication.
4. Проверить authorized path:

   ```sh
   /Applications/LidSwitch.app/Contents/MacOS/LidSwitch --m2-check-version
   # expected: m2-spike-v1;euid=0
   ```

5. Запустить уже подписанный build script тем же Team ID
   `.build/release/LidSwitchUnauthorizedProbe`; он имеет identifier
   `me.dapi.LidSwitch.UnauthorizedProbe`, должен завершиться `PASS` и не получить
   reply.
6. Заменить daemon executable новой подписанной версией, выполнить
   unregister/register и подтвердить новый reply без повторного расширения
   полномочий.
7. Unregister из меню; `sudo launchctl list me.dapi.LidSwitch.Daemon` должен
   сообщить, что service отсутствует. Legacy helper должен продолжить работать.

## Gate и решение

Текущий результат — **GO к notarized live test**, но еще не GO к переносу
`disablesleep`/energy operations.

M2 считается доказанным только если одновременно:

- authorized call возвращает ожидаемую версию и `euid=0`;
- same-Team wrong-identifier probe отклонен;
- update загружает новую daemon version после documented re-registration;
- unregister удаляет job, не затрагивая legacy helper;
- после reboot approved daemon снова доступен on demand.

До закрытия этих пунктов текущий helper остается production path.
