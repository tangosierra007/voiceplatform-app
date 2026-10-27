# Handback: mobile-release (WS5)

## 5.1 `ci/app-pipelines`: Android CI

### What is built

`.github/workflows/android.yml`, on every push, pull request, `v*` tag and manual dispatch:

| Job | What it does |
| --- | --- |
| Analyze and test | Flutter 3.47.8 (pinned, checked), `flutter analyze` over the whole tree, `flutter test` for the app, then every `packages/*/` with a `test/` folder: `flutter test` if its pubspec depends on the Flutter SDK, `dart test` otherwise. New packages are picked up without editing the workflow. |
| Build | Temurin JDK 17, Android platform 36, build-tools 36.0.0, NDK 28.2.13676358; debug APK and release App Bundle. The release bundle is **unsigned** here (this job gets no key) and the job says so in a notice and the run summary. Both files are kept as a run artifact for 14 days. |
| Play track guard | `.github/scripts/play-track-guard.sh` over every tracked text file except Markdown (`*.md`); `docs/` is scanned too, and so is the script itself. Fails on: any track setting (plain or quoted key, `track:`, `tracks:`, `track =`, `track_promote_to:`, `--track`, `--track=`) whose value isn't the literal `internal`; `promote`, `rollout`, `userFraction`, `promote_track` or `track_promote` anywhere; `production` in CI, fastlane, Gradle or script files; fastlane files outside `android/fastlane/`; a Play upload tool anywhere but `android.yml` and `android/fastlane/`; the Gradle Play Publisher plugin or a `play { }` block; a workflow or script running a `.md` file or naming a fixtures folder; any `uses:` other than the exact actions already in use (owner/repo@sha, plus `actions/checkout@v4` from `secret-scan.yml`) or a `./` path. The self-test (`play-track-guard-test.sh`) writes its fixtures from heredocs into `$RUNNER_TEMP`, outside the tree: 20 bad cases, each expecting its refusal message, and a good set expecting a pass. This guard is defence in depth; the real control is the `play-internal` environment. |
| Upload to Play internal testing | Only on manual dispatch from `main` or a `v*` tag; needs the three jobs above. Skips with a notice when no upload secret is set, fails if only some are set. Builds a bundle signed with the upload key, refuses it if unsigned or debug-signed, and uploads to the **internal** track with `r0adkll/upload-google-play` v1.1.5 (pinned by commit). |

Caching: the Flutter SDK and pub cache (flutter-action), Gradle (setup-java). Every action is pinned to a full commit SHA with its tag in a comment. Permissions are empty at the top and `contents: read` per job. `secret-scan.yml` is unchanged.

Note: `subosito/flutter-action` uses `actions/cache@v5` internally by tag; we can't pin inside a composite action.

### Signing (`android/app/build.gradle.kts`)

The upload key comes from environment variables `VP_UPLOAD_STORE_FILE`, `VP_UPLOAD_STORE_PASSWORD`, `VP_UPLOAD_KEY_ALIAS`, `VP_UPLOAD_KEY_PASSWORD`, or from `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`; a relative `storeFile` is resolved against `android/`). Both are kept out of git (`.gitignore` and the secret scan's key-file check).

- Key configured: release signed with it.
- No key, `CI=true`: release unsigned, with a warning.
- No key, local: release signed with the machine's own debug key, so `flutter run --release` still works (never uploadable).
- Some values set but not all, or a keystore path that doesn't exist: the build fails.
- `VP_REQUIRE_UPLOAD_KEY=true` (set by the upload job): no key means the build fails.

Tested locally: CI unsigned bundle, a partial configuration (fails), and a throwaway test keystore (signed, signer checked, keystore deleted).

### Versions

- `versionName`: the name part of `version:` in `pubspec.yaml`.
- `versionCode`: `github.run_number` of `android.yml` (`--build-number`). One counter for all runs of this workflow, so it only goes up. It restarts if the workflow file is renamed; if that ever happens, add a fixed offset above the last code uploaded.
- A `v*` tag must equal `v<pubspec version name>` or the upload job fails.

### Repository settings for TJ to apply (not done by this task)

The upload job (and no other job) declares `environment: play-internal`. As of 27 October the environment exists with deployment policies `main` and `v*` and the five secrets set in it only; no required reviewer and no tag ruleset yet. TJ decides on those; the settings below are the proposal.

1. **Settings → Environments →** `play-internal` (exists; check each item):
   - **Required reviewers**: TJ (and mobile-lead's account if wanted). Tick **Prevent self-review** if more than one reviewer is listed.
   - **Deployment branches and tags → Selected branches and tags**: add branch rule `main` and tag rule `v*`.
   - **Allow administrators to bypass**: off.
   - **Environment secrets**: the five secrets below (not repository secrets).
2. **Settings → Rules → Rulesets → New tag ruleset** `release tags`:
   - Enforcement **Active**; target tags matching `v*`.
   - Rules: **Restrict creations**, **Restrict updates**, **Restrict deletions**; bypass list: TJ only.
3. Leave no Play or keystore secret at repository level.

### Secrets the upload job expects (`play-internal` environment secrets)

| Secret | What goes in it |
| --- | --- |
| `PLAY_UPLOAD_JSON` | The full JSON key of the `play-upload` service account (the text of the file, as is). |
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | The upload keystore (`.jks`), base64-encoded on one line (`base64 -w0 upload.jks`). |
| `ANDROID_UPLOAD_STORE_PASSWORD` | The keystore password. |
| `ANDROID_UPLOAD_KEY_ALIAS` | The key's alias in the keystore. |
| `ANDROID_UPLOAD_KEY_PASSWORD` | The key's password (the same as the store password if one was set for both). |

Set all five or none. Set by mobile-lead in the `play-internal` environment (not by this task); this task generated no keystore. The key alias is `voiceplatform-upload`; the keystore is PKCS12, so the key password equals the store password.

### Upload key certificate (for App Links, WS1 1.4)

SHA-256: `E0:C6:75:63:BE:C0:2A:6F:42:7A:18:7E:15:DE:25:98:66:30:47:48:94:14:A2:A4:22:CD:6C:D9:D1:DD:97:09`

`assetlinks.json` also needs Play App Signing's SHA-256, from Play Console after the first upload. The upload job prints the signer's SHA-256 on every run; check it against this one.

### Proposed (for mobile-lead to decide)

1. versionCode from the run number as above; no offset for now.
2. Manual dispatch defaults to release status `draft`; tags use `completed`. Play only accepts `draft` releases until the app's first release is set up in Play Console.
3. `production` is refused only in CI, fastlane, Gradle and script files (any other track name is refused everywhere through the track check), so app code can still say for example a Sentry environment of `production` in 5.3.

### Open questions for TJ (through mobile-lead)

- Play may refuse API uploads until a first bundle has been uploaded by hand in Play Console. If so, TJ uploads the signed bundle kept by that run (artifact `android-signed-<run>`, 7 days) by hand once; after that CI uploads.
- Play App Signing's SHA-256 (after the first upload) is needed for `assetlinks.json` (WS1 1.4) alongside the upload key's above.

### Accepted residual risks (track guard)

The guard is defence in depth; the `play-internal` environment is the real control. Accepted by mobile-review (WS6):

- A `.md` file fed to a shell on stdin (`bash < x.md`) or through a pipe (`cat x.md | sh`) is not detected.
- Names built from pieces at run time (split strings, variables, encoded text) are not detected.

### Deviations

- None from the brief. `docs/handbacks/` is created by this task.
