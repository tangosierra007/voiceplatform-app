# Notes for the Play reviewer (draft)

Draft for task 5.4. Paste the quoted text into Play Console, under App access and the release notes for review. The reviewer account itself is added at review time (spec 22, APP10).

## App access

> VoicePlatform is a business phone app for workplaces that use the VoicePlatform phone system. Accounts are created by the workplace's administrator, so there is no sign-up in the app.
>
> Reviewer account: [given at review time]. Sign in with the email address below and tap "Email me a sign-in link"; on the next screen type the 6-digit code given here (no email needs to be opened). The review account belongs to a demo workplace. To try a call, dial *43 from the keypad: the echo test answers, and you hear your own voice back for up to 60 seconds. The account can make internal calls, but calls to outside numbers are blocked.

## How calls work in the background

> The app does not run in the background. Incoming calls wake it with a high-priority Firebase Cloud Messaging data message, which carries no personal data. The app then starts its calling foreground service, registers with the phone system and hands the call to Android Telecom as a self-managed call. On a locked phone the incoming call screen appears through a full-screen intent; on an unlocked phone it's a heads-up notification.
>
> The foreground service runs only while a call is ringing or in progress, and stops when it ends. Live presence updates are used only while the app is open. The app doesn't ask to be excluded from battery optimisation. If a phone's battery saving delays calls, the app shows a card that opens Android's own battery settings and leaves the choice to the user.

## Things the reviewer may notice

> - Emergency numbers (000, 112, 106) always open the phone's own dialler with the number filled in; the app never places an emergency call itself.
> - The microphone is requested when the first call starts, the camera only when the user taps to scan a sign-in code, and contacts only when the phone contacts tab is first opened. Refusing any of them leaves the rest of the app working.
> - The Messages tab appears only for accounts with a workplace mobile line; the review account may not have one.
> - Source code: github.com/tangosierra007/voiceplatform-app (AGPL-3.0).
