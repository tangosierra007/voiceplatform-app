# Handback: mobile-engine (WS3)

## 3.1 `feat/linphone-plugin`

Branch `feat/linphone-plugin` from `main` at `0524434`. One PR, not merged.

### What's built

`packages/vp_linphone`, a Flutter plugin (Android only), Kotlin with Pigeon 29.0.11 (dev dependency) for the typed channel.

- **Dart:** `VpLinphoneEngine implements CallEngine` (`lib/src/engine.dart`). Every method and stream in `contracts/call_engine.dart`; platform errors map to `NotRegistered`, `MicrophoneDenied`, `NoSuchCall` and `InvalidState`. `IncomingHeaders` parses the X-VP-* headers into `IncomingInfo`. `LogScrubber` re-scrubs the exported log. `inputLevel` maps liblinphone's record volume (dBm0) linearly from -60..0 to 0..1.
- **Pigeon:** `pigeons/messages.dart` -> `lib/src/messages.g.dart`, `Messages.g.kt` (committed; regenerate with `dart run pigeon --input pigeons/messages.dart`). The password crosses the channel once, in `register`, and is never sent back.
- **Kotlin:**
  - `EngineService`: the foreground service that owns the one `Core`. Type `phoneCall` while it runs, `phoneCall|microphone` during a call when RECORD_AUDIO is granted. Started by `start()`, stopped by `stop()`, and not sticky.
  - `LinphoneEngine`: the Core and all the SIP work, on the main looper.
  - `VpLinphonePlugin`: the Pigeon host API, with events back over the Flutter API.
  - Pure helpers for JVM tests: `Mapping`, `Rules`, `LogScrubber`, `CallLogFile`.
- **Core set-up:**
  - The config has no file (`createConfigFromString("")`), so liblinphone writes no auth info to disk.
  - Client TLS only: UDP and TCP listeners off, a random TLS port. Server certificate and CN verified.
  - SRTP SDES offered and never mandatory.
  - Video off, chat off, liblinphone's own push handling off.
  - DTMF by RFC 4733 only (no SIP INFO).
  - Incoming timeout 600 s, so the platform's no-answer timer decides when ringing stops.
- **Codecs:** opus, G722, PCMA, PCMU in that order, plus telephone-event. Every other payload type is disabled.
- **Registration:**
  - Identity `sip:<authUsername>@<domain>`. Server (Request-URI) `sip:<domain>;transport=tls`.
  - One route: the account's `outboundProxy` with `;lr`, forced to TLS. Plain `sip:` URIs throughout.
  - The RFC 8599 params (`pn-provider`, `pn-prid`, `pn-param`) go on the Contact as URI parameters.
  - `updatePush` swaps those params on the live account and refreshes the REGISTER; calls are untouched.
  - `+sip.instance` is the account's `instanceId` (`urn:uuid:<device id>`, from `sip-credentials`). liblinphone takes the instance from the config's `[misc] uuid` only when a Core is created, so `register()` with a new id rebuilds the Core (refused with `InvalidState` while a call is up). A malformed id is refused. To check in the live SIP tests: the Contact carries exactly `+sip.instance="<urn:uuid:...>"`.
  - `unregister` sends REGISTER expires 0 (it waits up to 5 s), then removes the account and every AuthInfo.
- **Calls:**
  - `call()` sends `X-VP-Caller-Id` when a caller ID is given.
  - `decline` = 486 Busy Here. `toVoicemail` = 302 to `sip:<voicemailUser>@<domain>`; `voicemailUser` is a `VpLinphoneEngine` constructor option, default `*97`. The platform should supply the target later (for example in `sip-credentials`).
  - `hold` and `resume` pause and resume the call. `setMuted` disables the mic engine-wide.
  - `sendDtmf` sends RFC 4733 digits.
  - `transferBlind` = REFER (`transferTo`). `transferAttended` = REFER with Replaces (`transferToAnother`); the held call shows `transferring` until it ends.
  - `merge` creates a local audio conference (it adds to one if a call is already in a conference).
  - `setAudioRoute` picks from liblinphone's audio devices (earpiece, speaker, Bluetooth, wired/USB). `car` is refused until Telecom arrives (3.2).
- **Emergency (rule 8):** `call()` never refuses 000, 112 or 106 (with or without a leading 0, ignoring spaces and punctuation). It skips the registration and microphone checks and places the call. The one case it can't place is when no account was ever registered, because there is no domain to send it to; it throws `NotRegistered`.
- **Snapshots:**
  - `encrypted` is true only when the account's transport is TLS and the call's current media encryption is SRTP.
  - `hdAudio` is true for opus or G722 as the used payload type.
  - `answeredElsewhere` comes from a CANCEL with `Reason: SIP;cause=200` (liblinphone's call-log status `AcceptedElsewhere`, or error info SIP 200).
- **Logs:**
  - `Factory.enableLogcatLogs(false)`, log collection disabled, liblinphone log level **Warning**. At Message level belle-sip dumps whole SIP messages, Authorization headers included.
  - Every liblinphone line goes through `LogScrubber` before it reaches memory or disk.
  - The scrubber removes: Authorization and Proxy-Authorization values; digest params (response, nonce, cnonce, opaque, nc); password, passwd, pwd, ha1 and secret pairs; `pn-prid` and other tokens; Bearer tokens; the exact current password and push token; email addresses (SIP URIs are kept); and runs of 6 or more digits, allowing up to two of space, dash or brackets between digits.
- **`exportLastCallLog()`:** `noBackupFilesDir/vp_linphone/lastcall.log`, which rotates once at 512 KB. Each file starts with a 200-line in-memory lead-in, runs from the first call starting until 3 s after the last call ends, and is scrubbed again on export (Kotlin, then Dart). Timestamps are written as `2026 Oct 27 03:15:00.123Z` so the digit rule never eats them.
- **Manifest (merged from the plugin):**
  - Declared: INTERNET, ACCESS_NETWORK_STATE, RECORD_AUDIO, MANAGE_OWN_CALLS, POST_NOTIFICATIONS, FOREGROUND_SERVICE, FOREGROUND_SERVICE_PHONE_CALL, FOREGROUND_SERVICE_MICROPHONE, BLUETOOTH_CONNECT, WAKE_LOCK, VIBRATE, and the service.
  - MANAGE_OWN_CALLS is needed for a `phoneCall` foreground service on Android 14 and later.
  - Removed from liblinphone's AAR: FOREGROUND_SERVICE_CAMERA, FOREGROUND_SERVICE_DATA_SYNC, ACCESS_NOTIFICATION_POLICY, CHANGE_WIFI_MULTICAST_STATE and CAMERA (the app declares CAMERA itself for QR; checked: an app-level CAMERA survives the plugin's remove marker). BLUETOOTH is limited to `maxSdkVersion=30`.
  - Final merged permissions of the example APK (`aapt2 dump permissions`): INTERNET, ACCESS_NETWORK_STATE, RECORD_AUDIO, MANAGE_OWN_CALLS, POST_NOTIFICATIONS, FOREGROUND_SERVICE, FOREGROUND_SERVICE_PHONE_CALL, FOREGROUND_SERVICE_MICROPHONE, BLUETOOTH_CONNECT, WAKE_LOCK, VIBRATE, BLUETOOTH (maxSdkVersion 30), MODIFY_AUDIO_SETTINGS, ACCESS_WIFI_STATE, and AndroidX's own `<package>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.
- **Example:** `packages/vp_linphone/example` is a bench app (Start, Stop, Export log, event list) with minSdk 29 and target 36. It never registers.

### Tests

- `flutter analyze` (package and example): no issues.
- `flutter test` (package): 49 tests pass.
  - `incoming_headers_test.dart`: the parser.
  - `log_scrubber_test.dart`: the same sample lines as Kotlin, including an Authorization header, the password and full numbers.
  - `engine_test.dart`: the Dart side against a fake host API.
  - `channel_test.dart`: real Pigeon messages on a mock platform channel, including the error envelope.
- `flutter test` (example): 1 test passes.
- Kotlin JVM unit tests, `gradlew :vp_linphone:testDebugUnitTest` from `example/android`: 28 tests pass.
  - `LogScrubberTest`: the log sink's scrubber on lines with an Authorization header, a password and full phone numbers.
  - `CallLogFileTest`
  - `MappingTest`: call states, end reasons (answered elsewhere), registration failures, codec order, HD, routes.
  - `RulesTest`: emergency, dial strings, DTMF, instance ids.
- `flutter build apk --debug` (example): builds (277 MB debug APK: four ABIs, unstripped liblinphone).
- **Not done (not allowed in 3.1):** any live registration or call. Everything that talks to liblinphone at runtime is unproven until the live SIP tests.

### liblinphone licence as found in the release's own files

`org.linphone:linphone-sdk-android:5.5.39` from `https://download.linphone.org/maven_repository` (published 2026-10-27 02:20, server time). The AAR's SHA-256 is `d3654346f2c99995d89beb712fc15d475ca994d8500b2af482565a0fd8f8a9c0`, and it matches the repository's `.sha256`.

- **POM** `<licenses>`: `<name>GNU GENERAL PUBLIC LICENSE, Version 3.0</name>`, `<url>https://www.gnu.org/licenses/gpl-3.0.en.html</url>`.
- **AAR:** no LICENSE, COPYING or NOTICE file.
- **Sources jar** (`-sources.jar`, 222 files):
  - 55 files (the Android tools classes, for example `CoreService.java`): "Copyright (c) 2010-2022 Belledonne Communications SARL ... GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version".
  - 162 files (the generated API wrappers, for example `Account.java`): "GNU General Public License ... either version 2 of the License, or (at your option) any later version".
  - 5 files have no licence header.

So the release says GPL-3.0 in its metadata and AGPL-3.0-or-later / GPL-2.0-or-later in its source headers, not the "AGPL-3.0" the spec expected. Both combine with this AGPL-3.0 app (GPL-3.0 section 13 / AGPL-3.0 section 13). `NOTICE` records this.

### Header formats assumed (WS2 emits these on INVITEs to app contacts)

```
X-VP-Called: +61355501201;label="Sales group"
X-VP-Also-Ringing: "Mia's desk phone", "Front desk DECT"
X-VP-Repeat: 3
X-VP-Last-Answered: "Mia Chen";at=2026-10-27T03:15:00Z
```

- Quoted strings follow RFC 3261 (`\"` and `\\` escapes). An unquoted token is accepted wherever a quoted string is. Parameter names are case-insensitive.
- **X-VP-Called:** the number is E.164 (`+` then 2 to 15 digits) or absent (`;label="Sales group"` alone). A non-E.164 number is dropped and the label kept.
- **X-VP-Also-Ringing:** a comma list in one header (liblinphone exposes the first header instance only). Empty items and duplicates are dropped, and the list is capped at 5.
- **X-VP-Repeat:** an integer from 1 to 9999.
- **X-VP-Last-Answered:** a name, then `;at=` with RFC 3339 that has `Z` or an offset (a zoneless time is dropped). The time is converted to UTC.
- All display text is trimmed, stripped of control characters and cut at 64 characters. A malformed header leaves its field empty and never throws.

### Proposed decisions (numbers for mobile-lead to assign)

1. liblinphone's licence is recorded as found: the POM says GPL-3.0; the source headers say AGPL-3.0-or-later and GPL-2.0-or-later. This is compatible with the AGPL-3.0 app.
2. Engine logging: liblinphone at Warning level, no logcat, no liblinphone log files. One scrubbed sink feeds the call log, scrubbed again on export (Kotlin, then Dart).
3. The REGISTER Request-URI is the tenant domain. The outbound proxy is a loose route over TLS. RFC 8599 params go as Contact URI parameters.
4. Decline is `486 Busy Here`. To voicemail is a 302 to a configurable target, `*97` until the platform supplies one.

### Deviations

- The task said `docs/handbacks/`; the agent file says `docs/mobile/handbacks/`. I used the task's path.
- No `docs/mobile/STATUS.md` in this repo, so no row was updated.
- `car` as an audio route throws `InvalidState` until Telecom (3.2).
- The foreground service runs as `phoneCall` while idle and registered, as the task asked. Play's `phoneCall` policy expects an ongoing call. 3.2's FCM wake may let the service start only for calls.

### Open questions

Answered by mobile-lead (27 Oct): the contract gained `instanceId` (used for `+sip.instance`); the voicemail target stays `*97` as a constructor option; the extra AAR permissions are settled as listed above; NOTICE now lists AndroidX Core, kotlinx.coroutines and the AAR's native libraries; the licence finding goes into decision 135's follow-up.

1. **Call history on the device.** liblinphone keeps its own call-log database by default; it is not exported or uploaded. Should it be turned off?
2. **Release date.** 5.5.39 was published to Belledonne's repository on 27 Oct. It is pinned as specified. Belledonne's release notes for it were not reviewed.
3. **Native licences not established** (see NOTICE): the post-quantum KEM code (ML-KEM/Kyber symbols; liboqs is a linphone-sdk submodule but not confirmed in this build) and libxml2 (named in strings only). The other licences are from the upstream projects named in linphone-sdk's submodule list, read from the master branch, not from the 5.5.39 tag.
4. **The root app** needs, in 3.2, its merged manifest checked against the spec's permission list. Nothing in `lib/`, the root `pubspec.yaml` or the root `android/` was touched.