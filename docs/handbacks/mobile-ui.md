# Handback: mobile-ui (WS4)

## 4.1 `feat/app-shell`

PR: https://github.com/tangosierra007/voiceplatform-app/pull/10 (against `main`, not merged).

### What is built

- **Theme from tokens.** `design/tokens.json` is the design system's `tokens.json`, unchanged. `dart run tool/gen_theme.dart` writes `lib/theme/tokens.g.dart`: the fixed palette, every colour token resolved for light and dark (as a `ThemeExtension`), shadows, spacing, radii, sizes and the type scale. `test/theme/tokens_up_to_date_test.dart` fails when the generated file is stale. `lib/theme/app_theme.dart` builds light and dark `ThemeData` from it: orange is a fill with ink text (never white), orange as text is `brand-text`, and `VpCallColours` holds the call-control rules (ink ground in both themes, answer #2e7d32, hang up #c62828, white icons). Tests check these rules and 4.5:1 contrast.
- **Artboard colours.** Three colours the artboards set directly are not in `tokens.json`, so they live in `tool/theme/artboard_colours.json` (each with its source) and are generated beside the tokens: the badge red #b42318 with white, and the dark tab bar #1a1613.
- **Fonts.** Unbounded and Manrope variable fonts with their `OFL.txt`, from github.com/google/fonts at commit `e7db6ca`, in `assets/fonts/`. The theme sets the `wght` axis as well as the weight. The OFL texts are registered with `LicenseRegistry`. No network fonts.
- **Dark mode.** Follows the device. A stored override (System, Light, Dark) in `shared_preferences` is ready for the Me switch (`themePreferenceProvider`).
- **Navigation.** go_router with a `StatefulShellRoute`: Keypad, Recents, Contacts, Messages, Me, each with a placeholder. `VpTabBar` matches the artboards' `nav.tabs`, using the artboard SVG icons unchanged, the pill, badges, colours, padding and the 22 px label line. Messages is hidden, and its route redirects, when `Me.permissions.messages` is false. Full-screen routes `/sign-in`, `/incoming/:callId` and `/in-call/:callId` sit outside the shell. `CallFlow` moves between them as the engine's calls change.
- **API client.** `dart run tool/gen_api.dart` regenerates `lib/api/` (swagger_parser, then build_runner) from `contracts/app-api.openapi.yaml`. `lib/net/api.dart` adds `X-VP-App: android/<version>` (version from package info) and the bearer token to every request. `lib/net/events.dart` is a hand-written SSE client for `/events`.
- **Mock server.** Start it with `dart run tool/mock_server/main.dart`, which serves `http://localhost:3000/app/v1`. It covers every route in the contract, using canvas sample data only. It needs `X-VP-App` on every request and a bearer on authenticated routes, and answers 426 below the minimum version. `/events` sends `presence.snapshot`, then `badges`, then a presence change every 5 s, with a heartbeat. The mock-only sign-in values are in `SignInFixtures`. To run the app against the mock server: `flutter run --dart-define=VP_DEV_TOKEN=mock`.
- **FakeCallEngine.** Implements every `CallEngine` method with the same state rules a real engine keeps. Tests can script incoming calls with `IncomingInfo`, outgoing outcomes, answered elsewhere, remote hold, registration failures, network loss and audio devices. The input level runs at 20 Hz and reads 0 while muted. The password is never readable and the log masks numbers. 23 tests cover it.
- **Goldens.** At 390 x 844, 2x, light and dark, drawn with the bundled fonts: `test/goldens/`. `test/goldens/compare/tab_bar_side_by_side.png` puts them beside `AppKeypad.dc.html` and `AppKeypadDark.dc.html`, rendered with Edge headless. To regenerate: `flutter test --update-goldens test/goldens`.
- **Accessibility.** Each tab is a selected or unselected button with its own label: "Recents, 2 new" and "Messages, 1 unread" carry the badge count. Tap targets meet the Android and labelled guidelines. Labels grow with the text size and shrink to fit their tab, and a test checks 100, 130, 150 and 200 % with no overflow.

Checks: `flutter analyze` clean, `flutter test` 72 passing, and `flutter build apk --debug` builds.

### Dependencies added (also in NOTICE)

The app uses: dio 5.11 (MIT), flutter_riverpod 3.4 (MIT), go_router 18.1 (BSD-3-Clause), retrofit 4.10 (MIT), json_annotation 4.12 (BSD-3-Clause), shared_preferences 2.5 (BSD-3-Clause), flutter_svg 2.3 (MIT), package_info_plus 10.2 (BSD-3-Clause), and `call_engine` (this repo, path dependency).

Dev only: swagger_parser 1.45 (MIT), build_runner 2.17 (BSD-3-Clause), json_serializable 6.15 (BSD-3-Clause), retrofit_generator 10.3 (MIT), fake_async 1.3 (Apache-2.0), yaml 3.1 (MIT).

The template's `cupertino_icons` is removed. Golden tooling is plain `flutter_test`, with no package.

### Proposed for mobile-lead

- **Record the dependency set** above under decision 135's app dependencies.
- **Fold three artboard colours into `tokens.json`:** badge #b42318 with white, and dark tab bar #1a1613. The generator would then drop `artboard_colours.json`.
- **Contract: give inline enum parameters names.** swagger_parser named the `status` query parameter of `GET /voicemail/messages` `Status`, which overwrote the `Status` schema. `gen_api.dart` works round this by moving each inline enum parameter into a named component before generating: `VoicemailMessagesStatus`, `HistoryFilter` and `VoicemailGreetingsKind`. The wire format is unchanged. Named components in the contract itself would make that step unnecessary.
- **Contract: `CallSettingsPatch` nulls.** The generated client leaves unset fields out of the request, so it cannot send `followMeTo: null` or `forwardAlwaysTo: null` to clear them. Either the contract gets a clear marker, or 4.4 sends that PATCH by hand.
- **Contract notes, no change needed.** `GET /events` and `GET /media/{token}` are not useful as generated, so the SSE client is hand-written and playback goes through the player in 4.4. `extension` fields are `extensionValue` in Dart because `extension` is a keyword.

### Artboard mismatches and sample data

- **AppRecents** shows "03 9555 0142", which is not an ACMA fictional number. The fixture uses 03 7010 0142 instead.
- **AppContacts** lists "Jess Rowe, Reception Â· 201". In the sample data, 201 is the Reception extension with no person named. Kept as the artboard shows it.
- **AppContacts** says "22 colleagues Â· 4 free now", but only 3 of the 7 people shown are free. The fixture keeps the totals and the 7 people.
- **AppMessages** filter chip says "Service" while the line is "Service mobile". The fixture line label is "Service mobile".
- **Tab bar labels** are 11 px with the 22 px line height inherited from `.vp-root`. Neither is in the type scale, so the tab bar uses those values directly, as the artboard does.
- **AppMe** shows "Version 1.0.3", which is sample data. The app is 1.0.0.

### Outside my directories

- `dart_test.yaml` at the root declares the `golden` tag.
- `android/` is untouched.

### Open points

- Goldens are drawn on Windows, and font rasterising differs on Linux. CI has no `flutter test` job yet. When one is added, run it with `--exclude-tags golden` or regenerate the goldens on the runner.
- The sign-in redirect (no session goes to `/sign-in`) is left for 4.2. For now the app starts on Keypad.
- pub.dev gave intermittent socket errors on this PC. Use `flutter test --no-pub` once dependencies are fetched.
