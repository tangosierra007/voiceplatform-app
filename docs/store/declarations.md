# Play Console declarations (draft texts)

Draft for task 5.4, from spec 22 (Android specifics, decision 141). Paste into Play Console at the first upload (see `release-checklist.md`).

## Foreground service types

The engine runs one foreground service (`android:foregroundServiceType="phoneCall|microphone"`) only while a call is ringing or in progress. It stops when the call ends. The app runs nothing in the background otherwise.

### `FOREGROUND_SERVICE_PHONE_CALL` (type `phoneCall`)

> VoicePlatform is a business calling app. It places and receives calls over the internet on the user's work number through Android's Telecom framework as a self-managed ConnectionService. The foreground service runs only while a call is ringing or in progress, so the call keeps going when the user leaves the app or locks the phone, and so Telecom can route audio to the earpiece, speaker, Bluetooth headsets and Android Auto. It stops when the call ends. The ongoing call notification is shown the whole time.

- User-visible: yes, the ongoing call notification and the in-call screen.
- Can't be deferred or interrupted: the call would drop.
- Video: **to record** (TJ). Show an incoming call on a locked phone, answer, lock the screen and keep talking, hang up, then show the notification has gone.

### `FOREGROUND_SERVICE_MICROPHONE` (type `microphone`)

> During a call the app captures the user's voice from the microphone and sends it to the other party. The microphone is used only while a call is in progress, inside the same foreground service, and the user is asked for microphone permission when their first call starts. The app doesn't record calls.

- User-visible: yes, the ongoing call notification and Android's microphone indicator.
- Video: the same video as above covers it.

## Full-screen intent (`USE_FULL_SCREEN_INTENT`)

Declaration: **calling app** (the app's core function is making and receiving calls).

> VoicePlatform rings for incoming calls on the user's work number. On a locked phone it shows the incoming call screen with Answer and Decline through a full-screen intent, as the phone's own dialler does. When the phone is unlocked it shows a heads-up notification instead. Full-screen intents are used for incoming calls only.

## Permissions not requested

For the reviewer: the app does not request `CALL_PHONE` (emergency calls open the phone's own dialler with `ACTION_DIAL`), `READ_PHONE_STATE`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, location, SMS or call log permissions.

## Other declarations at the first release

- Ads: no ads.
- Data safety: `data-safety.md`.
- Privacy policy URL: where `privacy-policy.md` is published.
- App access: sign-in needed; reviewer account at review time (`reviewer-notes.md`).
- Government app, financial features, health: no.
