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
  - SRTP SDES offered and never mandatory. *(Superseded: SRTP is mandatory, APP13; see "SRTP mandatory" below.)*
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
- **Emergency (decision 139 as amended, 27 Oct):** emergency numbers always go to the phone's dialler; the app never places one. `VpLinphoneEngine.call()` checks the contract's `isEmergencyNumber()` first, before registration, microphone or engine state, throws `EmergencyNumberUseDialler` and sends nothing to the platform side, so no INVITE. Kotlin keeps a mirror of the rule as a backstop, the first line of `LinphoneEngine.call()` (code `emergency_use_dialler`, mapped to the same error). `Rules.callGate` refuses it ahead of every other check. Both rules are tested against one table, `test/fixtures/emergency_numbers.txt`, so they can't drift apart. `transferBlind` to an emergency number is refused the same way (Dart first, the Kotlin backstop in the address builder), since a REFER would make the platform set the call up.
- **Snapshots:**
  - `encrypted` is true only when the account's transport is TLS and the call's current media encryption is SRTP.
  - `hdAudio` is true for opus or G722 as the used payload type.
  - `answeredElsewhere` comes from a CANCEL with `Reason: SIP;cause=200` (liblinphone's call-log status `AcceptedElsewhere`, or error info SIP 200).
- **Logs:**
  - `Factory.enableLogcatLogs(false)`, log collection disabled, liblinphone log level **Warning**. At Message level belle-sip dumps whole SIP messages, Authorization headers included.
  - Every liblinphone line goes through `LogScrubber` before it reaches memory or disk.
  - The scrubber removes: Authorization and Proxy-Authorization values; digest params (response, rspauth, nonce, nextnonce, cnonce, opaque, nc); password, passwd, pass, pwd, ha1 and secret pairs and `pn-prid` and other tokens, with `=` or `:` and also as JSON keys (`"password":"x"`); Bearer tokens; the exact current password and push token; email addresses (SIP URIs are kept); and runs of 6 or more digits, allowing up to two of space, dash, dot, slash or brackets between digits (a dotted IPv4 address is kept).
- **`exportLastCallLog()`:** `noBackupFilesDir/vp_linphone/lastcall.log`, which rotates once at 512 KB. Each file starts with a 200-line in-memory lead-in, runs from the first call starting until 3 s after the last call ends, and is scrubbed again on export (Kotlin, then Dart). Timestamps are written as `2026 Oct 27 03:15:00.123Z` so the digit rule never eats them.
- **Manifest (merged from the plugin):**
  - Declared: INTERNET, ACCESS_NETWORK_STATE, RECORD_AUDIO, MANAGE_OWN_CALLS, POST_NOTIFICATIONS, FOREGROUND_SERVICE, FOREGROUND_SERVICE_PHONE_CALL, FOREGROUND_SERVICE_MICROPHONE, BLUETOOTH_CONNECT, WAKE_LOCK, VIBRATE, and the service.
  - MANAGE_OWN_CALLS is needed for a `phoneCall` foreground service on Android 14 and later.
  - Removed from liblinphone's AAR: FOREGROUND_SERVICE_CAMERA, FOREGROUND_SERVICE_DATA_SYNC, ACCESS_NOTIFICATION_POLICY, CHANGE_WIFI_MULTICAST_STATE and CAMERA (the app declares CAMERA itself for QR; checked: an app-level CAMERA survives the plugin's remove marker). BLUETOOTH is limited to `maxSdkVersion=30`.
  - Final merged permissions of the example APK (`aapt2 dump permissions`): INTERNET, ACCESS_NETWORK_STATE, RECORD_AUDIO, MANAGE_OWN_CALLS, POST_NOTIFICATIONS, FOREGROUND_SERVICE, FOREGROUND_SERVICE_PHONE_CALL, FOREGROUND_SERVICE_MICROPHONE, BLUETOOTH_CONNECT, WAKE_LOCK, VIBRATE, BLUETOOTH (maxSdkVersion 30), MODIFY_AUDIO_SETTINGS, ACCESS_WIFI_STATE, and AndroidX's own `<package>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.
- **Example:** `packages/vp_linphone/example` is a bench app (Start, Stop, Export log, event list) with minSdk 29 and target 36. It never registers.

### Tests

- `flutter analyze` (package and example): no issues.
- `flutter test` (package): 61 tests pass, including `licenses_test.dart`: every licence file is listed and declared as an asset, NOTICE names each one, and `addVpLinphoneLicenses()` yields one LicenseRegistry entry per component.
  - `incoming_headers_test.dart`: the parser.
  - `log_scrubber_test.dart`: the same sample lines as Kotlin, including an Authorization header, the password and full numbers.
  - `engine_test.dart`: the Dart side against a fake host API, including the emergency table (every emergency number throws `EmergencyNumberUseDialler` with nothing sent, also before `start()` and `register()`; the table agrees with `isEmergencyNumber()`).
  - `channel_test.dart`: real Pigeon messages on a mock platform channel, including the error envelope.
- `flutter test` (example): 1 test passes.
- Kotlin JVM unit tests, `gradlew :vp_linphone:testDebugUnitTest` from `example/android`: 38 tests pass (`dialString` keeps ASCII digits 0-9 only, like the emergency rule).
  - `LogScrubberTest`: the log sink's scrubber on lines with an Authorization header, a password and full phone numbers.
  - `CallLogFileTest`
  - `MappingTest`: call states, end reasons (answered elsewhere), registration failures, codec order, HD, routes.
  - `RulesTest`: the Kotlin mirror against the shared emergency table, `callGate` (emergency refused first whatever the account, registration or microphone; normal numbers need all three), dial strings, DTMF, instance ids.
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

So the release says GPL-3.0 in its metadata and AGPL-3.0-or-later / GPL-2.0-or-later in its source headers, which differs from the plain AGPL-3.0 that was expected. Both combine with this AGPL-3.0 app (GPL-3.0 section 13 / AGPL-3.0 section 13).

**NOTICE is generated** (TJ, 27 Oct). The liblinphone section is written by `packages/vp_linphone/tool/liblinphone_notice.dart`. Re-run it on an upgrade from `packages/vp_linphone`: `dart run tool/liblinphone_notice.dart --version <v> --write ../../NOTICE`. It reads only the SDK's own files and checks each download against the repository's `.sha256`: the POM `<licenses>`, any LICENSE, COPYING or NOTICE file in the AAR or sources jar (there are none), each Java source's header, the root CA bundle's header, and licence-like strings inside the native libraries. Each statement names its source file. The only licence the SDK states is for the SDK as a whole (POM) and for the Java sources (their headers). **For every native component the licence is not stated in the SDK**, ML-KEM and libxml2 included, and NOTICE says so plainly. The only text found in a native library is a copyright line in libjpeg-turbo's `libjpeg.so` and `libturbojpeg.so` ("Copyright (C) 1991-2024 The libjpeg-turbo Project and many others"), with no licence. The root CA bundle states no licence either. The upstream licences I listed in the previous round came from Belledonne's source repositories, not from the SDK, so they were removed from NOTICE.

**Licence texts for the native code (hand-kept, WS6 round 4).** The generated section only records what the SDK's own files say, and they state none of the native licences. So NOTICE has a second, hand-kept section with each bundled component's upstream project, version and licence, and its licence text in `packages/vp_linphone/licenses/LICENSE.<component>` (40 files; named so the Play track guard's licence-text exemption applies):

- **Belledonne components:** texts are exact, from linphone-sdk tag 5.5.39 on GitHub. liblinphone, mediastreamer2 and oRTP ship AGPL-3.0 texts; bctoolbox, belle-sip, belr, bzrtp, lime, postquantumcryptoengine, msaaudio and msandroidcamera2 ship GPL-3.0 texts; mswebrtc ships a GPL-2.0 COPYING, but its own source headers say GPL-2.0-or-later (`mswebrtc.c`, `vad.cc`) and AGPL-3.0-or-later (`aec3.cc`, `mswebrtc_aec3.cc`), so it combines with AGPL-3.0.
- **CodeSynthesis XSD runtime** (libxsd, linked into `liblinphone.so`): exact texts from `liblinphone/libxsd` at 5.5.39. It stays GPL-2.0; the FLOSS Exception permits distributing it and XSD-generated code together with this AGPL-3.0 app. NOTICE gives the reasoning.
- **libyuv:** confirmed bundled. `libmediastreamer2.so` exports `I420Scale`, `ARGBToI420`, `NV12ToI420` and `ScalePlane`, and 5.5.39 pins `external/libyuv`. BSD-3-Clause plus PATENTS, from the lemenkov/libyuv mirror (version not established).
- **Third-party code:** it is built from Belledonne's forks on gitlab.linphone.org, pinned in `external/` at 5.5.39. That server could not be reached from this PC or dev-1, so the texts come from the upstream GitHub projects:
  - at the version the binary reports: opus 1.3.1, libvpx 1.9.0 base, libsrtp 2.7.0, zlib 1.2.8, SQLite 3.46.0, libjpeg-turbo 3.0.3;
  - at a stated nearby version or the default branch where the binary names none: speex, Mbed TLS 3.6.2, dav1d, jsoncpp, ZXing-C++, xerces-c, SOCI, libxml2, OpenLDAP, liboqs.
- **libc++:** the text is from the local NDK r28c NOTICE.
- **Upstream licence not established:** aom, GSM 06.10, BroadVoice16, decaf (Ed448), WebRTC audio processing inside mswebrtc, and liboqs's third-party subfolder licences (the ML-KEM code may sit there). NOTICE says so, and the in-app list shows "could not be obtained" for each.
- **In the APK:** the texts ship as plugin assets (35 files, checked in the example APK). `addVpLinphoneLicenses()` adds them to Flutter's `LicenseRegistry`. **WS4 must call `addVpLinphoneLicenses()` once at app start** (the example does, in `main`). Flutter's licence page then lists them.
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

Answered by mobile-lead (27 Oct): the contract gained `instanceId` (used for `+sip.instance`); the voicemail target stays `*97` as a constructor option; the extra AAR permissions are settled as listed above; NOTICE lists AndroidX Core and kotlinx.coroutines, and its liblinphone section is generated from the SDK's own files (above); the licence finding goes into decision 135's follow-up; emergency numbers always go to the dialler (decision 139 as amended).

1. **Call history on the device.** liblinphone keeps its own call-log database by default; it is not exported or uploaded. Should it be turned off?
2. **Release date.** 5.5.39 was published to Belledonne's repository on 27 Oct. It is pinned as specified. Belledonne's release notes for it were not reviewed.
3. **Licences still open:** aom, GSM 06.10, BroadVoice16, decaf, WebRTC and liboqs's third-party parts have no established upstream licence, and versions are not confirmed for most third-party components (texts and versions from Belledonne's forks need gitlab.linphone.org access). mswebrtc is settled: GPL-2.0-or-later by its source headers. Previously: native licences are not stated in the SDK (see NOTICE): about 28 components, ML-KEM and libxml2 among them. For distribution, their licence texts have to come from somewhere: the linphone-sdk 5.5.39 source tag, or Belledonne directly. That is a call for you and TJ; nothing in this branch infers them.
4. **The root app** needs, in 3.2, its merged manifest checked against the spec's permission list. Nothing in `lib/`, the root `pubspec.yaml` or the root `android/` was touched.

## SRTP mandatory (APP13, TJ decision) `feat/srtp-mandatory`

Branch `feat/srtp-mandatory` from `main` at `cbce9a0`. One PR, not merged. Required before the first Play upload.

### What's built

- **Policy** (`MediaSecurity.kt`, pure, JVM-tested): SDES-SRTP (`MediaEncryption.SRTP`, RFC 4568 `a=crypto`), as spec 22 says ("SRTP SDES") and as the edge carries it. Not DTLS-SRTP.
  - **Core** (`configure`): `setMediaEncryption(SRTP)`, `setMediaEncryptionMandatory(true)`, capability negotiation off (with it on, liblinphone can put RTP/AVP on the m-line and offer SRTP only as a potential configuration). The m-line is therefore RTP/SAVP only, never RTP/AVP. If the build has no SRTP, the Core is not started (`MediaSecurity.Unavailable`, reported as a start failure): never plain RTP.
  - **Call params:** `call()` and `answer()` set `mediaEncryption = SRTP` and capability negotiation off on the INVITE's and the 200 OK's params. Both first refuse (`InvalidState`) if the Core is not mandatory SRTP.
  - **Account params:** liblinphone 5.5.39's `AccountParams` has no media-encryption setting (only `instantMessagingEncryptionMandatory`, for chat, which is off). Media encryption is per Core and per call.
- **Falling back to plain RTP is refused or ends the call:**
  - An incoming offer without crypto: liblinphone (mandatory) answers **488 Not Acceptable Here**; the call never rings.
  - Our offer refused by the far end with 488 (the edge would not do SRTP): the call ends.
  - An outgoing call answered without crypto, an incoming late-offer call, or a re-INVITE/UPDATE that drops crypto: every negotiation that leads to audio ends in `StreamsRunning`. There the engine checks `currentParams.mediaEncryption`; anything but SRTP (unknown included) and the call is terminated at once. With encryption mandatory, mediastreamer2 also sends and accepts no unencrypted RTP meanwhile.
  - **End reason:** the contract's `EndReason.failed` in every case (a 488 either way, or the engine's own end). No contract change.
- **Diagnostics:** `CallDiagnostics` does not report encryption, so nothing was added there. The call log it exports now has `media encryption SRTP, mandatory true` at Core start, `call <id> media encryption SRTP` at each `StreamsRunning`, and `call <id> ending: media encryption <x>, not SRTP (APP13)` when the engine ends one. `CallSnapshot.encrypted` is unchanged (TLS and SRTP).

### Tests

- Kotlin JVM (`gradlew :vp_linphone:testDebugUnitTest` from `example/android`): 79 pass, including `MediaSecurityTest`:
  - the Core is SRTP, mandatory, without capability negotiation; no SRTP in the build means no engine; every call's params are SRTP;
  - a Core that is not mandatory SRTP refuses calls;
  - running media that is not SRTP (None, unknown, DTLS) ends the call; no other state is checked;
  - an RTP-only offer refused with 488 (incoming, or our offer refused) and a call the engine ended are `failed`;
  - source checks: the engine applies the policy to the Core and to both `call()` and `answer()`, and nothing in the plugin sets mandatory to false, `MediaEncryption.None`, or capability negotiation on.
- `flutter analyze` and `flutter test` (root and packages): see the PR.
- **Not done:** a two-Core loopback test. This PC has no emulator (no `emulator` package or system image in the SDK, and installing one was out of scope), and the A53 was off limits. So liblinphone's own 488 to a plain offer, and that `currentParams.mediaEncryption` reads SRTP at `StreamsRunning` on a real SDES call, are unproven until the live SIP tests. If the second were wrong every call would end as `failed` at once, so it is the first thing to check on the handset.

### Handset test for TJ

1. A normal call each way through the edge: two-way audio, the Encrypted tag shows, the exported log has `media encryption SRTP`.
2. With an edge or test UA that offers RTP/AVP only: the INVITE gets 488 and the phone doesn't ring.
3. A test UA that answers our offer without `a=crypto`: the call ends at once as `failed`.
4. A re-INVITE without crypto mid-call: refused with 488 (the call goes on, encrypted) or ended as `failed`.

### Open

1. **Edge:** the app now needs the edge to offer and answer RTP/SAVP with SDES on every app branch and app-originated call. PR #117 (WS2 2.2) as read today has no SRTP change (its SIPp scenarios still use RTP/AVP). Until the edge's SRTP-only change lands, every app call fails with 488.
2. **UI copy:** `docs/store/listing.md` still says calls are encrypted "where your workplace's connection supports it". With APP13 they always are. Owner: WS5.
3. **Proposed guardrail row** for `docs/guardrails.md` (main repo): APP13, "Every app call's audio is SRTP (SDES), mandatory: the SDP never offers RTP/AVP, and a call that would carry plain RTP is refused (488) or ended (`failed`)". Test: app `MediaSecurityTest`; edge SIPp from WS2. Status: partial until the handset test.

## 3.2 (Android) `feat/telecom-fcm`

Branch `feat/telecom-fcm` from `main` at `89752d3`. One PR, not merged.

### What's built

- **Self-managed Telecom** (`VpConnectionService`, `VpConnection`, `TelecomBridge`):
  - Every call is a Telecom connection: outgoing through `placeCall`, incoming through `addNewIncomingCall`. The PhoneAccount is `CAPABILITY_SELF_MANAGED` with the `sip` and `tel` schemes.
  - Answer, reject, hold, unhold, disconnect and DTMF from the system, headsets and cars become engine commands through `ConnectionMachine` (pure, JVM-tested). Hanging up a ringing call from a headset is a decline (486) for this device.
  - Engine snapshots drive the connection: ringing, dialing, active, holding, then disconnected with a cause. The causes are LOCAL, REMOTE, REJECTED, BUSY, MISSED, ERROR and **ANSWERED_ELSEWHERE**, the last from a CANCEL with `cause=200`, which also clears the notification.
  - **Audio routes** come from Telecom while a connection exists: `CallEndpoint` on Android 14+, `CallAudioState` below.
    - They feed `CallEngine.audio`, and `setAudioRoute` goes through Telecom; liblinphone's devices follow.
    - `car` is a Bluetooth endpoint whose device class is car audio (needs `BLUETOOTH_CONNECT`); otherwise it shows as `bluetooth`.
- **Emergency:** `placeCall`, the outgoing connection request, `call()` and the address builder all refuse 000, 112 and 106 first. There is never a self-managed emergency call, whoever asks Telecom for one.
- **Incoming notification** (`IncomingCallNotifier`):
  - CallStyle with Answer and Decline, on a ringtone channel (insistent). liblinphone's own ringing is off.
  - It carries a full-screen intent to the app's activity. On Android 14+ without the permission it falls back to a plain heads-up notification with the two actions, because Android refuses a CallStyle notification without a full-screen intent. The fallback is reported to Dart.
  - Answer opens the app and answers, so the microphone is used while the app is in front. Decline is a broadcast.
  - The plugin (`ActivityAware`) shows the activity over the lock screen and turns the screen on while a call rings.
- **Route hook for WS4:**
  - `VpLinphoneEngine.uiRequests` (`showIncoming` and `showCall` with the call id) and `takeUiRequest()` for a cold start.
  - `fullScreenIntentDenied`, `canUseFullScreenIntent()` and `openFullScreenIntentSettings()`.
  - No Flutter screens.
- **FCM:**
  - `firebase_core` 5.1.0 and `firebase_messaging` 17.0.1 (pinned) give the token: `VpPushTokens.start()`.
  - On a refresh, `VpPushTokens` calls `CallEngine.updatePush` and emits on `tokens`; that stream is the hook for `PUT /devices/me/push-token`.
  - Data messages are received **natively** by `PushReceiver`, which sits beside firebase_messaging's receiver on the same c2dm broadcast. An incoming call therefore never waits for Flutter to start.
- **`PushHandler`** (pure; JVM-tested with a fake clock):
  - `incoming_call` starts the service (`phoneCall`) and the Core, and registers again with the stored account and the same pn-prid. If a registration is already up, it refreshes it.
  - The 8 s budget runs from `sentAt` (from receipt when `sentAt` is missing). A later registration goes into `WakeLog`.
  - `call_cancelled` ends the wake at once unless a call is up.
  - With no INVITE within 30 s, the engine goes back to sleep.
  - Duplicate `pushId`s are dropped.
  - `voicemail`, `message`, `signed_out` and `config` go to `VpLinphoneEngine.pushMessages`. If no Flutter engine is attached, they are kept (types only, at most 20) for `takePendingPushes()`.
- **Account for push wakes:** `CredentialStore` keeps the account register() was given, AES-256-GCM under an Android Keystore key, in `noBackupFilesDir`. It is cleared by unregister(), and nothing reads it back through the Flutter API (APP4).
  - The account is registered with `unregisterAtStop` off, so stopping the engine after a wake keeps the push contact.
- **Microphone:** the foreground service is `phoneCall` while ringing or dialling. It adds `microphone` once a call is connected.
- **Battery** (no `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`): `batteryStatus()` gives whether the app is ignoring optimisations, the late wakes in the last 7 days and `Build.MANUFACTURER`. `openBatteryOptimizationSettings()` opens `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`.
- **Root app:** the google-services Gradle plugin is in `android/settings.gradle.kts` and `android/app/build.gradle.kts` (outside the signing block). The root app still doesn't depend on vp_linphone (4.2).
- **NOTICE:** firebase_core, firebase_messaging, the Firebase Android SDK and the google-services plugin.

### Tests

- `flutter analyze` (package, example, root app): clean.
- `flutter test` (package): 70 pass. The new `android_extras_test.dart` covers the push, UI-request and full-screen-intent streams, pending pushes, battery, and `VpPushTokens` with a fake token source.
- Kotlin JVM tests: 63 pass (after the review fixes below), including:
  - `ConnectionMachineTest`: the state machine, system events and disconnect causes.
  - `PushHandlerTest`: dedupe, wake, late registration counted from receipt and from `sentAt`, cancel, the idle timeout and delivery, with a fake clock and scheduler.
  - `AccountRecordTest`.
- Example and root debug APKs build.

### On TJ's A53 (Android 15), with a fake engine behind TelecomBridge (no SIP, no FCM send)

- An incoming call rings in Telecom, with the CallStyle heads-up showing Answer and Decline.
- Answer from the notification opens the app, makes the call ACTIVE and sends `showCall`.
- Decline gives DisconnectCause REJECTED.
- The headset key answers a ringing call and hangs up an active one.
- "Answered elsewhere" gives ANSWERED_ELSEWHERE, and the notification is cleared.
- An outgoing call goes DIALING, then ACTIVE.
- Endpoints reported: earpiece and speaker.
- On a locked screen the full-screen intent shows the activity over the keyguard and sends `showIncoming`.
- With the full-screen intent denied (appops), the call falls back to a plain heads-up and Dart gets `fullScreenIntentDenied`. This test found a crash, now fixed: Android refuses a CallStyle notification without a full-screen intent.
- A simulated `incoming_call` push starts the service (type `phoneCall`, 0x4). `call_cancelled` stopped it within 1.5 s; with no call, the 30 s idle timeout stopped it.
- A `voicemail` push reached the Dart stream.
- `call('000')` threw `EmergencyNumberUseDialler`.
- Battery status read `ignoring=false late=0 samsung`.

Not verified: a real SIP INVITE or FCM message, Bluetooth or car routes (none paired), and microphone capture on an answer from the lock screen.

### Deviations

- **Credentials at rest.** For push wakes, the account (password included) is kept Keystore-encrypted on the device. In 3.1 it was in memory only; spec 22 allows "memory and the platform keystore".
- **Pushes for the app** are received natively and forwarded to Dart. firebase_messaging is used for the token only (no `onMessage` or background isolate).
- **Example app:** it has bench-only Kotlin, a fake engine and a simulated push, that is not in the plugin's API. It has no google-services config, so `VpPushTokens.start()` returns null there.
- **SDK package:** the FlutterFire Gradle build installed Android SDK Platform 34 (`platforms;android-34`, 95 MB) automatically.

### Open questions

1. firebase_messaging 17 deprecates `getToken`/`onTokenRefresh` for `register()`/`onRegistered`, which give a Firebase Installation ID as the send target. We keep the FCM token as pn-prid. Moving needs WS2's push gateway to send to the new target.
2. Microphone from the lock screen. Answering from Telecom or a headset while the app is in the background adds the `microphone` foreground-service type when the call connects; Android may refuse that from the background, and the code then falls back to `phoneCall` only. This needs a live call test. If capture is silent, the fix is to open the activity on answer, as the notification's Answer button does.
3. The root app must depend on vp_linphone and call `VpLinphoneEngine`, `VpPushTokens.start()` and `addVpLinphoneLicenses()` (4.2). The Firebase Android SDK's Apache-2.0 texts are not in Flutter's LicenseRegistry; they would need an oss-licenses step.
4. `POST_NOTIFICATIONS` and `BLUETOOTH_CONNECT` are runtime permissions WS4 must ask for. Without the first, Telecom still has the call but no notification shows.

### Review fixes (WS6 on PR #15)

1. **Answering from another app.** The notification's full-screen intent, tap and Answer now go to `CallActionActivity`, which is not exported. Each notification carries a random token per call (`CallActionGate`): Answer and Decline need it and use it once, and failed guesses don't burn it.
   - The launcher activity's intent extras are no longer read at all. The UI request reaches the plugin in process memory (`PendingUiRequest`), and the lock-screen flag is set only while that call is ringing.
   - The Decline receiver checks the token too. Call ids are random (`call-` and 16 hex characters).
   - Verified on the A53 while a call rang. None of these changed the call: an external intent to the launcher with `answer` and a valid-looking id; a shell start of the trampoline (a SecurityException, since it isn't exported); a shell Decline broadcast without a token. The notification's own Answer still worked, and so did the full-screen intent over the lock screen.
   - JVM tests: `CallActionGateTest`.
2. **`call_cancelled` during start-up.** `EngineLifecycle` (pure) holds a stop that arrives while the service is starting. The service is stopped as soon as it is in the foreground, and the start callbacks get `StartCancelled`. `wakeForPush` also re-checks that a wake is still wanted before registering. A start from the app meanwhile wins over the pending stop.
   - JVM tests with a fake clock: `CancelDuringStartTest`.
3. **`signed_out`** clears `CredentialStore`, forgets the account and stops the engine natively (no Flutter needed), then delivers the push to Dart. Tested in `PushHandlerTest`.
4. **Route fallback:** asking for Bluetooth when the only Bluetooth endpoint is a car kit uses the car endpoint.

## 3.4 `feat/engine-diagnostics`

Branch `feat/engine-diagnostics` from `main` at `dedc9f8`. One PR, not merged.

### What's built

- **Rotating per-call logs** (`CallLogFile`):
  - Each call's log is in segments of at most 1 MB, `calls/<start>-<n>.log` in `noBackupFilesDir/vp_linphone/` (app-private, excluded from backup).
  - Kept: the last 5 calls or 10 MB in all, whichever comes first. The oldest segments go first, so a very long call loses its start, and its export begins with a "rotated out" marker.
  - A 200-line in-memory lead-in (the REGISTER before the call) starts each call's log.
  - The scrubbing sink is still the only writer. liblinphone's logcat output stays off in every build. A JVM test fails on any `Log.*`, `println` or `printStackTrace` in the plugin's Kotlin.
  - 3.1's single-file log is deleted on first use.
- **Export:** `exportLastCallLog()` returns the last call's log **gzipped**, at most 2 MB.
  - It is scrubbed as written, again in Kotlin on export, and again in Dart (`LogScrubber`).
  - If it doesn't fit, the oldest lines are cut at a line boundary and `callLogTruncatedMarker` goes first. It is empty when no call has been logged.
- **Shared scrub table:** `packages/vp_linphone/test/shared_scrub_cases.dart` is a copy of WS5's `test/diagnostics/shared_scrub_cases.dart`. A test checks the two tables are equal and runs every case through vp_linphone's scrubber; all pass.
- **`CallDiagnostics`** (for the Me screen, 4.4):
  - `lastCallLog()` returns the gzipped bytes.
  - `sendCallLogs()` uploads them through a `CallLogUploader` and returns the reference (`LOG-...`). It throws `NoCallLog` when there is nothing to send.
  - The uploader is injected: the app passes its generated API client's `POST /app/v1/diagnostics/call-logs` call (`application/gzip`), which adds the bearer token and `X-VP-App`.
- **MOS hooks (v1.x):** `VpLinphoneEngine.callQuality` gives a sample every 2 s per connected call, from liblinphone's RTCP statistics:
  - liblinphone's 0..5 quality estimate;
  - jitter (ms, as the far end reported it);
  - local and remote loss (%);
  - round trip (ms).
  - It is optional, and nothing sends it.

### Tests

- `flutter analyze` (whole tree): clean.
- Root `flutter test`: 217 pass.
- vp_linphone `flutter test`: 105 pass, including `diagnostics_test.dart`: the shared table, gzip export, the 2 MB truncation with marker, `CallDiagnostics` and the quality stream.
- Kotlin JVM tests: 67 pass, including `CallLogFileTest`: last 5 calls, the total-size limit oldest-first, a long call's rotated start, export, legacy cleanup, and no logcat.
- Example and root debug APKs build.
- Not run on the A53: no fake engine path writes call logs (they need a real Core call). Rotation and export are covered by the JVM tests.

### Deviations and open questions

1. `CallEngine.exportLastCallLog()` now returns **gzip** (the contract's doc says "the rotating log"; the API takes `application/gzip`). If WS4 reads it as text anywhere, it must gunzip it. Should the contract doc say gzip?
2. The upload is a hook, not an HTTP call in the plugin: vp_linphone has no API client, and the app's generated one adds the auth and version headers.
3. Quality units follow liblinphone: jitter is the far end's RTCP report, and the 0..5 estimate is not a calibrated MOS.
