# First internal testing release: checklist

For TJ and mobile-lead together. Internal testing only; nothing else in Play Console changes.

1. **Before the run**
   - [ ] `main` is green; `pubspec.yaml` `version:` is the versionName wanted (for example `1.0.0`). The versionCode is the run number of `android.yml` (it only goes up).
   - [x] The `play-internal` environment has its five secrets (set 27 Oct), a required reviewer (TJ) with admin bypass off, and deploys only from `main` and `v*` tags.
   - [x] A tag ruleset protects `v*` tags.
   - [ ] Optional: the `SENTRY_DSN` repository secret, if this build should report crashes to GlitchTip.
2. **Build and sign**
   - [ ] Run `android` by hand from `main` (Actions, Run workflow, release status `draft`), or push the tag `v<versionName>` (it must match `pubspec.yaml`).
   - [ ] TJ approves the `play-internal` deployment.
   - [ ] Check the job log: "Signed with the upload key" and the SHA-256 `E0:C6:75:63:BE:C0:2A:6F:42:7A:18:7E:15:DE:25:98:66:30:47:48:94:14:A2:A4:22:CD:6C:D9:D1:DD:97:09`.
3. **First upload (by hand, if Play refuses the API)**
   - [ ] Play may refuse API uploads until a first bundle has been uploaded by hand. If the upload step fails that way, download the artifact `android-signed-<run>` (kept 7 days).
   - [ ] Play Console, VoicePlatform, Testing, Internal testing, Create new release: upload `app-release.aab`, release name as the version, save as draft.
4. **Declarations and listing** (texts in this folder)
   - [ ] Foreground service types: phone call and microphone, with the video (`declarations.md`).
   - [ ] Full-screen intent: calling app (`declarations.md`).
   - [ ] Data safety (`data-safety.md`), privacy policy URL (`privacy-policy.md` published first), ads (none), content rating, target audience, app access (`reviewer-notes.md`).
   - [ ] Store listing text and graphics (`listing.md`). The app icon is `graphics/ic_launcher-playstore-512.png`.
5. **Release to testers**
   - [ ] Internal testing, testers: the `Milavo Staff` list. Start the release.
   - [ ] Later releases come from CI: run `android` again; the upload job sends to the internal track.
6. **After the first upload**
   - [ ] Play Console, Setup, App integrity, App signing: copy the **app signing key** SHA-256 (and SHA-1).
   - [ ] `assetlinks.json` on each portal host (WS1 1.4): `au.com.voiceplatform.app` with both the Play App Signing SHA-256 and the upload key SHA-256 above.
   - [ ] **F1:** in Google Cloud for the Firebase project, restrict the `google-services.json` API key to Android apps. Add package `au.com.voiceplatform.app` with the SHA-1 of the Play App Signing key and of the upload key. Then check push still arrives on the test phone.
   - [ ] Install from the internal testing link on TJ's phone and start the handset tests.
   - [ ] Icon checks (A3):
     - The home screen icon is the VoicePlatform mark, not the Flutter default, under the launcher's own mask.
     - With Material You themed icons on (Android 13+), the icon follows the wallpaper colours.
     - The status bar shows the white mark for the "ready" and in-call notifications and for an incoming call.
     - The internal testing listing shows the 512 icon.
