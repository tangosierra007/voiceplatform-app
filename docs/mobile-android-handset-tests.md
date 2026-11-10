# Android handset tests (Stage A3)

The handset script for the VoicePlatform Android app, run from a Play internal-testing install. It covers every item in spec 22's "Handset tests" (platform repo, `docs/spec/22-voiceplatform-app.md`), numbered as there. It adds three sections spec 22 doesn't have:
- **F:** the Fold and landscape layouts.
- **M:** a mobile call during an app call.
- **R:** re-tests of earlier findings.

"A3" here is Stage A3, the handset tests. It is not the design-scope item A3 (the per-device Rings switch, done in #106), which is item 16 below.

## Rules for every run

- **Emergency numbers:** 000, 112 and 106 are never really called. Item 7 is a dry run: tap, see the system dialler open with the number, and stop there. Never press call. The platform side of item 7 is proven by SIPp on the isolated stack (`app-emergency-routes.xml`), never the live one.
- **Phone numbers:** live calls go to the tester's own numbers only. No real number is ever written in this file, a commit, a PR or a test log. TJ gives the live test number at run time when a test needs it. Examples here use ACMA fictional numbers only (for example `0491 570 156`).
- **Secrets:** sign-in codes, passwords and keys are never printed. For the lab test account on the dev stack only, a sign-in code may be read from Mailpit and passed straight to the phone, noted in the log.
- **dev-1 changes:** only two kinds may be made during a run.
  - The app minimum version (item 11) and an extension's tier (item 3), on the lab tenants only.
  - Each change is audited, restored at the end of the test it serves, and noted in the log with its restore.
  - Never during a window, or while anything else runs on dev-1.
  - Anything else (an OpenSIPS restart for item 4) needs TJ's OK and its own window.
- **Heavy jobs:** SIPp runs, including `scripts/dev1/ring201.sh`, take the dev-1 heavy lock (`flock ~/.vp-heavy.lock`).
- **Full-screen access** is denied on a Play install until Google approves the declaration. Locked-phone tests record what happens with access denied, and don't change the setting.
- **Recording each result:** time (`HH:MM:SS`), pass or fail, and the evidence: call record (CDR), audit row, GlitchTip event or screenshot name. A fault becomes a follow-up. Nothing is fixed inside A3.

**Who runs what:**
- **L:** the lead, on the A53 (SM-A536E) over adb, signed in as lab extension 201.
- **T:** TJ, at the desk phone or on TJ's own phone.
- **F:** the Galaxy Z Fold7 (SM-F966B), held by TJ, with the lead reading the records.

**Before a run, note:** the app version and build (Play), the phone and Android version, dev-1's main commit and API image, and the time.

## Spec 22 items

### 1. Every phone artboard, light and dark (L)
- **Do:** open each screen in light, then dark (Me, Dark mode), and screenshot it: Keypad, Recents, Contacts, contact detail, Messages, thread, Voicemail, Me, in-call, incoming, AppOffline, AppMicrophone, AppSignedOut, AppBasic, AppUpdate.
- **Pass:** each matches its artboard in layout, text and colours. Note any difference with the screenshot names.

### 2. Sign in by link and by code (L, T)
- **Do:**
  1. Sign out, then sign in by code.
  2. Sign out, then sign in by tapping the link on the phone.
  3. Forward a fresh link to another phone and open it there.
  4. Open a link on a PC.
- **Pass:**
  - Steps 1 and 2 sign in.
  - Step 3 fails (wrong device).
  - Step 4 shows "open on your phone" and completes nothing.
  - Audit: `app.sign_in_requested`, `app.sign_in_completed`.

### 3. Basic refused; "Ask my admin to upgrade" (L)
- **Do:**
  1. On a lab tenant, set 201's extension tier to Basic, and log it as a change.
  2. Sign in.
  3. Tap "Ask my admin to upgrade".
  4. Put the tier back to Advanced and log the restore.
- **Pass:**
  - AppBasic shows.
  - The admin gets a notification and an email (Mailpit).
  - Audit: the refusal and the request.
  - After the restore, sign-in works.

### 4. Incoming call on a locked phone, app killed; after an OpenSIPS restart (L, then T's window)
- **Do:**
  1. Kill the app (swipe it from Recents) and lock the phone.
  2. Ring 201 (`ring201.sh` or the desk).
  3. The OpenSIPS restart half runs only in a window TJ has approved.
- **Pass:**
  - The phone rings within 8 s of the INVITE.
  - With full-screen access denied, the call shows as a notification and answers from it.
  - Audio both ways.
  - After the restart, the same holds.

### 5. A call answered on the desk phone clears the app (L, T)
- **Do:** ring 201 so the app and the desk phone both ring, then TJ answers on the desk phone.
- **Pass:** the app's ringing screen clears within 2 s and shows nothing missed. CDR: answered by the desk phone.

### 6. Transfer, hold, merge; caller ID picker (F, T)
- **Do:**
  1. Blind transfer.
  2. Attended transfer.
  3. Hold and resume.
  4. Add a call and merge the two into a three-way.
  5. Make one call with each caller ID in the picker, then with "Withheld".
- **Pass:**
  - Each completes, with audio on every leg.
  - The far end sees the chosen caller ID, or "withheld".
  - Each call has its CDR.

### 7. 000 opens the dialler, nothing reaches the platform (L, dry run)
- **Do:** type 000 and tap call. Then repeat with 112 and 106, and with a leading 0. **Stop when the dialler opens. Never press call there.**
- **Pass:**
  - The system dialler opens with the number, before any permission or registration check.
  - No INVITE reaches dev-1 (Homer, and no CDR).

### 8. Voicemail (L, T)
- **Do:**
  1. Leave a message for 201, then play it.
  2. Mark it heard, and check the MWI on the desk phone.
  3. Delete it.
  4. Record a greeting and play it back.
  5. Change the PIN, then change it back.
- **Pass:** each step works, and the MWI clears when the message is heard.

### 9. Office hours override, with and without the grant (L)
- **Do:** with the grant, override office hours and put them back. Then repeat without the grant.
- **Pass:** with the grant it works and is audited. Without it, it's refused or hidden.

### 10. Remote sign-out from the portal (L, T)
- **Do:** revoke the A53 in the portal: once with the app open, and once with the app closed (#56's last check).
- **Pass:** AppSignedOut shows who signed it out and when, at once if the app is open, and on next open if it's closed. Audit: `app.device_revoked`.

### 11. Forced update below the minimum version (L)
- **Do:**
  1. Raise the Android minimum version on dev-1 above the installed build, and log the change.
  2. Open the app.
  3. Put the minimum back and log the restore.
- **Pass:**
  - AppUpdate shows and links to Play.
  - Authenticated calls get 426.
  - After the restore, the app works.

### 12. A crash and send-logs, in GlitchTip, no secrets (F)
- **Do:** trigger the test crash (diagnostics), then Me, "Send call logs to support".
- **Pass:**
  - Both show in GlitchTip and the support view.
  - No password, code, token, SIP credential or phone contact appears in either.

### 13. Repeat caller (L, T)
- **Do:** call 201 twice from the same number, the first answered by the desk phone.
- **Pass:** the second call shows the repeat-caller tag, and who answered last.

### 14. SMS both ways on the lab mobile line (F, T)
- **Do:** from the Messages tab, send an SMS to TJ's phone, then reply.
- **Pass:** both arrive, in order, in one thread.

### 15. "Call from my desk phone instead" (L, T)
- **Do:** from a contact, choose "Call from my desk phone instead".
- **Pass:** the desk phone rings first, then calls the number. CDR: from the desk extension.

### 16. Rings switch off stops the app ringing (L)
- **Do:** turn this device's Rings switch off, ring 201, then turn it back on.
- **Pass:** the app doesn't ring while the switch is off, and the desk phone still rings. It rings again once the switch is back on.

### 17. Phone contacts (F)
- **Do:** run this on a fresh install with a proxy capture running.
  1. Open Contacts, and refuse the permission.
  2. Then allow it.
  3. Call from a saved contact.
- **Pass:**
  - Permission is asked on first open only.
  - Refusing leaves the rest working.
  - The contact's name shows on the incoming call and in Recents.
  - Nothing from the address book appears in API traffic (the proxy capture), GlitchTip or the log export.

### 18. FreeSWITCH CPU: 20 Opus calls against 20 G.711 (lead, isolated SIPp stack)
This is a separate `tests/sipp` PR in the platform repo, never run against the live stack.
- **Do:**
  1. Capture one real Opus call's RTP from an app call on dev-1 (a test tenant, nothing identifying).
  2. Replay that capture as the media of 20 concurrent calls from app identities to the loopback carrier (transcoded to G.711).
  3. Run the same 20 calls on G.711.
  4. Sample FreeSWITCH CPU every second.
- **Pass:** the numbers are recorded. If they change sizing, `docs/architecture.md` is updated.

### 19. Presence (L, T)
- **Do:** with the app open on Contacts, change a colleague's status at the desk. Then put the app in the background.
- **Pass:**
  - The status changes within 2 s.
  - With the app in the background, no presence stream is open (API side).

### 20. Echo test (L)
- **Do:** dial `*43`, speak, then wait. Then sign in as the review tenant's user (window open) and dial `*43` again.
- **Pass:**
  - Your own voice comes back after the prompt.
  - The call ends by itself at 60 s.
  - The reviewer's call works the same.
  - CDR: flow path `echo`, in the caller's tenant.

**Status:** the reviewer half passed on 10 Nov (1.0.2, A53).

## F. The Fold and landscape (F)

The source is the design scope's large-screen rules (`APP_DESIGN_SCOPE.md`). The widths were never measured on a device, so record them.

- **F1. Widths:** folded and unfolded, portrait and landscape.
  - Record the window width in dp for each.
  - Below 600 dp: bottom tabs.
  - From 600 dp: the rail.
  - From about 680 dp: the list and detail split (Recents, Contacts, Messages, Voicemail).
- **F2. Keypad and in-call:** both stay phone width on the wide screen.
- **F3. Fold and unfold mid-task:** a half-typed number on the keypad and an open thread both survive folding and unfolding.
- **F4. No orientation lock:** every screen turns with the phone on the wide screen.
- **F5. A call across a fold:** answer folded, unfold mid-call. Audio and controls carry on.
- **F6. Text at 200% and the screen reader:** the main screens stay usable, and every control has a label.

## M. A mobile call during an app call (F, T)

Since #59, Android Telecom alone holds our call. This has never been tested.

- **M1.** In an app call, a GSM call comes in. Pass: it rings or waits as Android decides. The app call holds, or ends, with no crash and no stuck audio.
- **M2.** Answer the GSM call, end it, then go back to the app call. Pass: the app call's audio returns both ways.
- **M3.** The reverse: an app call comes in during a GSM call. Pass: it shows as waiting and doesn't take the audio until answered.

## R. Re-tests

| # | What | Expected on 1.0.2 |
|---|---|---|
| R1 | Follow-up 43: first locked answer on a fresh install, microphone | Known failure (no outgoing audio). Record it; the fix is in v1.0.3 |
| R2 | Follow-up 44: "INCOMING CALL" label after answer | Known failure. Record it; the fix is in v1.0.3 |
| R3 | A6: licence request from the app reaches the admin (with item 3) | Pass |
| R4 | A4: timed DND ends by itself at its time | Pass |
| R5 | A licence refusal clears the local logs | Pass |
| R6 | Icon checks (`docs/store/release-checklist.md`) | Pass |

## Results

Each run is written up as its own table: item, time, pass or fail, evidence. The results then go into the platform repo's `docs/mobile/STATUS.md` through a docs PR. Faults become follow-ups numbered from 47 on.

The planned order (TJ, 10 Nov):
1. The A53 items (L).
2. Item 18, the load PR.
3. The Fold hour (F, M and the F-marked items), at a time TJ gives.
