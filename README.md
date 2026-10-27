# VoicePlatform app

The VoicePlatform phone and desktop app: calls, voicemail, contacts with presence and messages for people whose business phones run on VoicePlatform. Built with Flutter on [liblinphone](https://www.linphone.org/). Android first, then iOS, Windows and macOS.

The app needs a VoicePlatform account with an Advanced licence. It talks only to the VoicePlatform platform; it holds no servers of its own.

## Licence

GNU Affero General Public License v3.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE) for this app's own licence and the third-party components it uses.

## Repository rules

- No secrets, signing keys, service account files, server lists or customer data are ever committed. A secret scan runs on every push and pull request.
- `contracts/` holds the app API contract (`app-api.openapi.yaml`, published from the platform) and the `CallEngine` interface between the UI and the SIP engine. They change only through the project lead.
- Test data uses fictional names and ACMA's fictional numbers only.

## Status

Early development. Nothing to install yet.