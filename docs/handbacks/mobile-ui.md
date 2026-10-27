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
  - The mock-only sign-in values are in `SignInFixtures`. To run the app against the mock server: `flutter run --dart-define=VP_DEV_TOKEN=mock`.
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
- pub.dev gave intermittent socket errors on this PC. Use `flutter test --no-pub` once dependencies are fetched.
