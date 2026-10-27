# Notes for the Play reviewer (draft)

Draft for task 5.4. Paste the quoted text into Play Console, under App access and the release notes for review. The reviewer account itself is added at review time (spec 22, APP10).

## App access

> VoicePlatform is a business phone app for workplaces that use the VoicePlatform phone system. Accounts are created by the workplace's administrator, so there is no sign-up in the app.
>
> Reviewer account: [given at review time]. Sign in with the email address below; the app sends a 6-digit code, and the review account accepts the code given here. The review account belongs to a demo workplace. It can make internal calls and call the echo test on extension [given at review time], but cannot call outside numbers.

## How calls work in the background

> The app does not run in the background. Incoming calls wake it with a high-priority Firebase Cloud Messaging data message, which carries no personal data. The app then starts its calling foreground service, registers with the phone system and hands the call to Android Telecom as a self-managed call. On a locked phone the incoming call screen appears through a full-screen intent; on an unlocked phone it's a heads-up notification.
>
> The foreground service runs only while a call is ringing or in progress, and stops when it ends. Live presence updates are used only while the app is open. The app doesn't ask to be excluded from battery optimisation. If a phone's battery saving delays calls, the app shows a card that opens Android's own battery settings and leaves the choice to the user.

## Things the reviewer may notice

> - Emergency numbers (000, 112, 106) always open the phone's own dialler with the number filled in; the app never places an emergency call itself.
> - The microphone is requested when the first call starts, the camera only when the user taps to scan a sign-in code, and contacts only when the phone contacts tab is first opened. Refusing any of them leaves the rest of the app working.
> - The Messages tab appears only for accounts with a workplace mobile line; the review account may not have one.
> - Source code: github.com/tangosierra007/voiceplatform-app (AGPL-3.0).
