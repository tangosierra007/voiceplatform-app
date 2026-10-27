# Handback: mobile-release (WS5)

## 5.1 `ci/app-pipelines`: Android CI

### What is built

`.github/workflows/android.yml`, on every push, pull request, `v*` tag and manual dispatch:

| Job | What it does |
| --- | --- |
| Analyze and test | Flutter 3.47.8 (pinned, checked), `flutter analyze` over the whole tree, `flutter test` for the app, then every `packages/*/` with a `test/` folder: `flutter test` if its pubspec depends on the Flutter SDK, `dart test` otherwise. New packages are picked up without editing the workflow. |
| Build | Temurin JDK 17, Android platform 36, build-tools 36.0.0, NDK 28.2.13676358; debug APK and release App Bundle. The release bundle is **unsigned** here (this job gets no key) and the job says so in a notice and the run summary. Both files are kept as a run artifact for 14 days. |
| Play track guard | `.github/scripts/play-track-guard.sh`: fails if any file under `.github/` or `android/fastlane/` names a track other than the literal `internal`, or mentions production, promotion or rollout. |
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

### Secrets the upload job expects (repository secrets)

| Secret | What goes in it |
| --- | --- |
| `PLAY_UPLOAD_JSON` | The full JSON key of the `play-upload` service account (the text of the file, as is). |
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | The upload keystore (`.jks`), base64-encoded on one line (`base64 -w0 upload.jks`). |
| `ANDROID_UPLOAD_STORE_PASSWORD` | The keystore password. |
| `ANDROID_UPLOAD_KEY_ALIAS` | The key's alias in the keystore. |
| `ANDROID_UPLOAD_KEY_PASSWORD` | The key's password (the same as the store password if one was set for both). |

Set all five or none. None were set by this task, and no keystore was generated.

### Proposed (for mobile-lead to decide)

1. versionCode from the run number as above; no offset for now.
2. Manual dispatch defaults to release status `draft`; tags use `completed`. Play only accepts `draft` releases until the app's first release is set up in Play Console.
3. Optionally put the five secrets in a GitHub environment (for example `play-internal`) limited to `main` and `v*` tags, and add `environment:` to the upload job. Not done here, because it changes repository settings.

### Open questions for TJ (through mobile-lead)

- Play may refuse API uploads until a first bundle has been uploaded by hand in Play Console. If so, TJ uploads the signed bundle kept by that run (artifact `android-signed-<run>`, 7 days) by hand once; after that CI uploads.
- The upload key's SHA-256 (printed by the upload job) is needed for `assetlinks.json` (WS1 1.4) alongside Play App Signing's.

### Deviations

- None from the brief. `docs/handbacks/` is created by this task.
