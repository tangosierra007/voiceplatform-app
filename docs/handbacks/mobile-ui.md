# Handback: mobile-ui (WS4)

## 4.1 `feat/app-shell`

PR: https://github.com/tangosierra007/voiceplatform-app/pull/10 (against `main`, not merged). Rebased on `main` at `f80fe3b`, with WS6's review and TJ's 27 Oct decisions applied.

### What is built

- **Theme from tokens.** `design/tokens.json` is the design system's `tokens.json`, unchanged. `dart run tool/gen_theme.dart` writes `lib/theme/tokens.g.dart`: the fixed palette, every colour token resolved for light and dark (as a `ThemeExtension`), shadows, spacing, radii, sizes and the type scale. `test/theme/tokens_up_to_date_test.dart` fails when the generated file is stale. `lib/theme/app_theme.dart` builds light and dark `ThemeData` from it:
  - Orange is a fill with ink text, never white; orange as text uses `brand-text`.
  - `VpCallColours` holds the call-control rules: ink ground in both themes, answer #2e7d32, hang up #c62828, white icons.
  - `VpTabBarColours` gives the tab bar's colours by role, from tokens only.

  Tests check these rules and 4.5:1 contrast.
- **Fonts.** Unbounded and Manrope variable fonts with their `OFL.txt`, from github.com/google/fonts at commit `e7db6ca`, in `assets/fonts/`. The theme sets the `wght` axis as well as the weight. The OFL texts are registered with `LicenseRegistry`. No network fonts.
- **Dark mode.** Follows the device. A stored override (System, Light, Dark) in `shared_preferences` is ready for the Me switch (`themePreferenceProvider`).
- **Navigation.** go_router with a `StatefulShellRoute`: Keypad, Recents, Contacts, Messages, Me, each with a placeholder.
  - `VpTabBar` matches the artboards' `nav.tabs`: their SVG icons unchanged, the pill, badges, padding and the 22 px label line. Colours are from tokens (see Artboard corrections).
  - Messages is hidden, and its route redirects, when `Me.permissions.messages` is false.
  - Full-screen routes `/sign-in`, `/incoming/:callId` and `/in-call/:callId` sit outside the shell. `CallFlow` moves between them as the engine's calls change.
- **API client.** `dart run tool/gen_api.dart` regenerates `lib/api/` (swagger_parser, then build_runner) from `contracts/app-api.openapi.yaml`. It is regenerated for the reformatted contract and `SipCredentials.instanceId`. `lib/net/api.dart` adds `X-VP-App: android/<version>` (version from package info) and the bearer token to every request.
- **Live events.** `lib/net/events.dart` parses the SSE stream. `lib/net/live_events.dart` (`LiveEvents`) keeps it going:
  - `LiveEventsLifecycle` (`AppLifecycleListener`) opens it in the foreground and closes it in the background, where nothing runs.
  - A `reauth` event runs the token refresh, then reopens the stream at once.
  - A failed or closed stream reopens after 1 s, then 2 s.
  - After three failures in a row, it polls `GET /presence` with its ETag every 30 s while Contacts (or, from 4.3, Transfer) is open, and retries the stream every 2 minutes. The first event on a reopened stream ends the fallback.
  - Polled presence comes out as a `presence.snapshot`.

  fake_async tests cover each step, and one runs against the mock server. The refresh itself is a hook: 4.2 supplies it.
- **Mock server.** Start it with `dart run tool/mock_server/main.dart`, which serves `http://localhost:3000/app/v1`. It covers every route in the contract, using canvas sample data only.
  - It needs `X-VP-App` on every request and a bearer on authenticated routes, and answers 426 below the minimum version.
  - `sip-credentials` includes `instanceId` (`urn:uuid:<device id>`).
  - The colleagues' free count is counted from presence.
  - `/events` sends `presence.snapshot`, then `badges`, then a presence change every 5 s, with a heartbeat.
  - The mock-only sign-in values are in `SignInFixtures`. Since 4.2 the app signs in for real against it: `ava@democo.example`, code `123456`.
- **FakeCallEngine.** Implements every `CallEngine` method with the same state rules a real engine keeps.
  - `call()` throws `EmergencyNumberUseDialler` for any number `isEmergencyNumber()` matches, before the started, registered and microphone checks: the app never places one. Tests cover 000, 112, 106, 0000, 0112, 0106, punctuated and spaced forms, an engine not started, started but not registered, and microphone refused. Near misses are tested as ordinary numbers.
  - Tests can script incoming calls with `IncomingInfo`, outgoing outcomes, answered elsewhere, remote hold, registration failures, network loss and audio devices.
  - The input level runs at 20 Hz and reads 0 while muted.
  - The password is never readable and the log masks numbers.
- **Goldens.** At 390 x 844, 2x, light and dark, drawn with the bundled fonts: `test/goldens/`. `test/goldens/compare/tab_bar_side_by_side.png` puts them beside `AppKeypad.dc.html` and `AppKeypadDark.dc.html`, rendered with Edge headless. To regenerate: `flutter test --update-goldens test/goldens`.
- **Accessibility.** Each tab is a selected or unselected button with its own label: "Recents, 2 new" and "Messages, 1 unread" carry the badge count. Tap targets meet the Android and labelled guidelines. Labels grow with the text size and shrink to fit their tab, and a test checks 100, 130, 150 and 200 % with no overflow.

Checks: `flutter analyze` clean, `flutter test` 86 passing, and `flutter build apk --debug` builds.

### Dependencies added (also in NOTICE)

The app uses: dio 5.11 (MIT), flutter_riverpod 3.4 (MIT), go_router 18.1 (BSD-3-Clause), retrofit 4.10 (MIT), json_annotation 4.12 (BSD-3-Clause), shared_preferences 2.5 (BSD-3-Clause), flutter_svg 2.3 (MIT), package_info_plus 10.2 (BSD-3-Clause), and `call_engine` (this repo, path dependency).

Dev only: swagger_parser 1.45 (MIT), build_runner 2.17 (BSD-3-Clause), json_serializable 6.15 (BSD-3-Clause), retrofit_generator 10.3 (MIT), fake_async 1.3 (Apache-2.0), yaml 3.1 (MIT).

The template's `cupertino_icons` is removed. Golden tooling is plain `flutter_test`, with no package.

### Proposed for mobile-lead

- **Record the dependency set** above under decision 135's app dependencies.
- **Contract (the lead will change it).** Three contract points, kept as workarounds until then:
  - Inline enum parameters: `gen_api.dart` keeps naming them (`VoicemailMessagesStatus`, `HistoryFilter`, `VoicemailGreetingsKind`) until the contract does.
  - `CallSettingsPatch`: the generated client cannot yet clear `followMeTo` or `forwardAlwaysTo`.
  - `GET /events` and `GET /media/{token}` are not useful as generated, so the SSE client is hand-written and playback goes through the player in 4.4. `extension` fields are `extensionValue` in Dart because `extension` is a keyword.

### Artboard corrections

TJ, 27 Oct: `tokens.json` and the sample data win over the artboard. The build follows these; the artboards need updating to match.

- **Badge colour, AppKeypad and AppKeypadDark.** The artboards draw #b42318 with white. The app uses the nearest token, `danger-600` (#c62828), with `white`: 5.6:1. No new token.
- **Dark tab bar, AppKeypadDark.** The artboard draws #1a1613. The app uses the nearest token, `charcoal-850` (#1f1b18), also the dark theme's navigation colour. The light tab bar stays `surface`. No new token.
- **AppRecents.** "03 9555 0142" is not an ACMA fictional number. It is now 03 5550 1142, which is unused in the sample data.
- **AppContacts.** The header shows the real free count, counted from presence, never a fixed "4". With the fixture's presence that is 3 (Mia, Priya, Tom on mobile).
- **AppContacts.** Extension 201 shows "Reception", as in the sample data, not "Jess Rowe".
- **AppMessages.** The filter chip says "Service mobile", not "Service".
- **AppUpdate.** "dialer" becomes "dialler".
- **AppMe.** Signed-in devices shows the phone's model ("Pixel 8"), not "This iPhone".
- **AppTransfer.** "Mobile only" becomes "Available on mobile".

The last three are for the screens in 4.2 to 4.4. Also noted, with no change: the tab labels' 11 px size and 22 px line come from the artboard's CSS, not the type scale, and AppMe's "Version 1.0.3" is sample data.

### Outside my directories

- `dart_test.yaml` at the root declares the `golden` tag; approved by mobile-lead.
- `android/` is untouched.

### Open points

- The goldens are drawn on Windows, and the Linux CI `flutter test` will fail on them until WS5 excludes the `golden` tag there (with mobile-lead).
- The sign-in redirect (no session goes to `/sign-in`) and the token refresh behind `reauth` come in 4.2. For now the app starts on Keypad.
- Done in 4.2: `main()` calls `addVpLinphoneLicenses()` now that app PR #5 is on `main`.
- pub.dev gave intermittent socket errors on this PC. Use `flutter test --no-pub` once dependencies are fetched.

## 4.2 `feat/app-signin`

PR: https://github.com/tangosierra007/voiceplatform-app/pull/13 (against `main`, not merged).

### What is built

- **AppSignIn.** Work email and "Email me a sign-in link". The app makes a 32-byte request secret (base64url) and keeps it in memory only: it is never stored or logged, and `toString` hides it. The 202 answer is the same for any email. "Scan the QR code instead" is also here. A link that failed shows its message as a notice on this screen.
- **AppCode.**
  - Six boxes drawn over one numeric field, so paste and one-time-code autofill work. Six digits submit by themselves.
  - Server messages show for a wrong code, a locked request, an expired code and the device limit.
  - "Send again in m:ss" counts down from `resendAfterSeconds`, then becomes "Send again".
- **App Link.** `https://portal.voiceplatform.com.au/app/signin/<requestId>/<linkToken>` has an `autoVerify` intent filter and is read with app_links (Flutter's own deep linking is turned off). It completes only with the in-memory request. Any other link shows "This link only signs in the phone that asked for it."
- **QR.** `vpapp://signin/<token>` is read only by the in-app scanner: flutter_zxing (zxing-cpp; no ML Kit, no network). Camera permission is asked when the scanner opens on the tap. It calls `/auth/qr/complete`. There is no `vpapp` intent filter, so no other app can sign the phone in.
- **Device binding.**
  - `android/.../keys/DeviceKeyStore.kt` holds a P-256 key in Android Keystore, in StrongBox when the phone has one, with a fallback. Its typed channel is generated by Pigeon (`tool/pigeons/device_keys.dart`).
  - The SPKI public key goes up at complete. Every refresh signs `deviceId.refreshToken.timestamp` (ECDSA SHA-256).
  - The device id and refresh token are kept in flutter_secure_storage (Keystore-backed). The access token is in memory only. Nothing is logged.
  - A 401 from any authenticated route refreshes once and retries, and refreshes are single-flight. On `device_revoked` or `refresh_invalid`, everything local is cleared, including the key, and the app goes to sign-in (AppSignedOut is 4.4). A `licence_basic` at refresh shows AppBasic.
- **AppBasic.** Shows the extension and its name. "Ask my admin to upgrade" posts the refusal token to `/auth/licence-requests`, then shows a confirmation. "Use a different email" clears the request.
- **AppUpdate.** Opened by `GET /config` at start or by any 426. It is blocking: every route redirects to it and back does nothing. "Update now" opens the store URL. Between the minimum and recommended versions, a banner on the tabs shows once a day.
- **AppEmergency.**
  - `dialNumber()` is the one way any screen places a call. Any `isEmergencyNumber` match opens the sheet and never reaches the engine; the engine's own `EmergencyNumberUseDialler` also opens the sheet.
  - "Call 000 now" opens the phone's dialler with the number (`ACTION_DIAL`, no CALL_PHONE). A trunk 0 is dropped, so 0000 dials 000.
  - With no dialler, the sheet says the device can't make emergency calls.
- **Biometric unlock.** `biometricUnlockProvider`, off by default, is ready for the Me switch in 4.4. Turning it on asks for the check once. It covers the app when it opens or comes back from the background, never the call screens. `MainActivity` is now a `FlutterFragmentActivity`, because local_auth needs one.
- **Router gate.** Order: update required, then starting, then Basic, then signed out, then signed in. The rules are in a pure `gateRedirect()` with its own tests.
- **Live events.** Run only while signed in. `reauth` uses the real refresh.
- **Mock server.** Covers each sign-in path and error:
  - unknown email: the same 202, then no code works
  - locked after 5 wrong codes; code expired after 10 minutes (on the mock's clock)
  - Send again before the wait: 429
  - Basic: by email, QR and refresh
  - `device_limit`
  - QR used or expired
  - refresh: rotation, reuse revoking the device, `refresh_invalid`, and timestamp skew
  - licence request: refusal token expiry
  - 426, and expired access tokens
- **Goldens.** All five screens, light and dark. `test/goldens/compare/signin_side_by_side.png` puts them beside the artboards. Each screen is checked at 200% text, with screen reader labels and tap targets.

Changed outside `lib/` (approved for 4.2): `android/app/src/main/AndroidManifest.xml` (INTERNET, CAMERA, USE_BIOMETRIC, the App Link filter, `flutter_deeplinking_enabled=false`, dial and https queries, backups off, and the two storage permissions removed), `res/xml/data_extraction_rules.xml`, `MainActivity.kt`, and `keys/` (`DeviceKeyStore.kt` plus the Pigeon output). The manifest had no INTERNET permission before, which release builds need.

### New dependencies (in NOTICE)

flutter_secure_storage 11.2 (BSD-3-Clause), local_auth 3.0 (BSD-3-Clause), app_links 7.2 (Apache-2.0), android_intent_plus 6.1 (BSD-3-Clause), device_info_plus 13.3 (BSD-3-Clause), and flutter_zxing 3.1 (MIT). flutter_zxing brings camera (BSD-3-Clause), image (MIT), image_picker (BSD-3-Clause, gallery off), zxing-cpp (Apache-2.0) and zint (BSD-3-Clause).

Dev only: pigeon 29.0 (BSD-3-Clause).

### Deviations and copy not on an artboard (proposed; please confirm)

- **QR scanner.** I chose flutter_zxing over mobile_scanner because mobile_scanner uses Google ML Kit, which is not open source. The cost is a native CMake build.
- **Signature encoding.** The refresh signature is ECDSA P-256 SHA-256, **DER-encoded, base64url without padding**. mobile-lead is adding this to the contract.
- **AppBasic check colour.** The artboard draws #2e6b2e; I used `status-ok` (success-600 in light), the nearest token.
- **AppEmergency icon colour.** The artboard draws #b42318 on `danger-100`; I used `status-bad` (danger-600 in light).
- **New copy:**
  - Invalid email: "Enter your work email address."
  - Offline: "Can't reach VoicePlatform. Check your connection and try again."
  - Basic confirmation: "We've asked your admin. They'll get a notification and an email."
  - No dialler: "This device can't make emergency calls. Use a mobile phone or a desk phone to call 000."
  - Banner: "A new version of the app is ready." with "Update" and "Not now".
  - QR screen title "Scan the QR code", its hint, and "That isn't a VoicePlatform sign-in code."
  - The unlock screen.
- **Emergency label.** "Call 000 now" names the number dialled, so 112 shows "Call 112 now".
- **The VoicePlatform wordmark** does not grow with text size. It has a screen reader label.
- **App Links on other hosts.** They need the reseller portal hosts added to the intent filter and `assetlinks.json` on each host (WS1 1.4).
- **API address.** The base URL still defaults to the mock on the emulator (`VP_API_BASE`). The production address per build flavour is for WS5.
- **`tel:` links.** No `tel:` intent filter is registered, so the app is not a phone handler. In-app links and Recents go through `dialNumber()` in 4.3 and 4.4.

### Artboard corrections (4.2)

- **AppUpdate:** "dialer" becomes "dialler" (built).
- **AppSignIn and AppCode:** the sample address is `ava@democo.example`. The mock fixtures now use it for Ava; they were `ava.nguyen@demo-co.example`.

### WS6 review fixes (PR #13)

- **Nulls in request bodies (blocker).** `build.yaml` sets json_serializable `include_if_null: false` (and `explicit_to_json`), and the client is regenerated. An absent optional field is now left out, never sent as null. The mock refuses a null anywhere in a JSON body with 400, as zod `.optional()` does; `CallSettingsPatch` is the exception, because its fields are nullable in the contract. Tests: `test/net/mock_server_test.dart`, "optional fields".
- **Login CSRF through `vpapp://` (high).** The `vpapp` intent filter is gone, and so is the link handler path in `lib/auth/links.dart`. QR sign-in is only through the in-app scanner. Tests: a `vpapp` link does nothing (widget test), and the manifest has no `vpapp` scheme.
- **Cold-start notice (medium).** `_restore` keeps a notice a link set while starting. A widget test cold-starts the real controller from a forwarded link.
- **Merged permissions (medium).** READ_EXTERNAL_STORAGE and WRITE_EXTERNAL_STORAGE are removed with `tools:node="remove"`. The final merged permissions for the debug build, with vp_linphone:

  | Permission | Notes |
  | --- | --- |
  | INTERNET | |
  | ACCESS_NETWORK_STATE | |
  | ACCESS_WIFI_STATE | |
  | CAMERA | |
  | USE_BIOMETRIC | |
  | USE_FINGERPRINT | local_auth; deprecated alias of USE_BIOMETRIC, accepted |
  | RECORD_AUDIO | |
  | MODIFY_AUDIO_SETTINGS | |
  | MANAGE_OWN_CALLS | |
  | POST_NOTIFICATIONS | |
  | FOREGROUND_SERVICE | |
  | FOREGROUND_SERVICE_PHONE_CALL | |
  | FOREGROUND_SERVICE_MICROPHONE | |
  | BLUETOOTH_CONNECT | |
  | BLUETOOTH | maxSdkVersion 30 |
  | WAKE_LOCK | |
  | VIBRATE | |
  | `au.com.voiceplatform.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | AndroidX, signature-level |

- **Backups (low).** `android:allowBackup="false"`, and `data_extraction_rules.xml` excludes every domain from both cloud backup and device transfer. The comment in `session_store.dart` is corrected.
- **APP7's test (low).** Now at the spec's path: `test/update_required_test.dart`.
- **vp_linphone.** It is a path dependency now that app PR #5 is on `main`, and `main()` calls `addVpLinphoneLicenses()` at start-up.
- **Pigeon's Dart output** is now `lib/platform/device_keys.pigeon.dart`. build_runner had deleted the earlier `.g.dart` name as a conflicting output.
- **Root config.** `build.yaml` is a new root file.
