# VoicePlatform app

The VoicePlatform phone and desktop app: calls, voicemail, contacts with presence and messages for people whose business phones run on VoicePlatform. Built with Flutter on [liblinphone](https://www.linphone.org/). Android first, then iOS, Windows and macOS.

The app needs a VoicePlatform account with an Advanced licence. It talks only to the VoicePlatform platform; it holds no servers of its own.

## Licence

GNU Affero General Public License v3.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE) for this app's own licence and the third-party components it uses.

## Repository rules

- No secrets, signing keys, service account files, server lists or customer data are ever committed. A secret scan runs on every push and pull request.
- `contracts/` holds the app API contract (`app-api.openapi.yaml`, published from the platform) and the `CallEngine` interface between the UI and the SIP engine. They change only through the project lead.
- Test data uses fictional names and ACMA's fictional numbers only (see Test data below).

## Test data

Phone numbers in code, tests, fixtures, goldens' text, docs, design files, commit messages and pull request text are ACMA's numbers for fiction only ([ACMA: Phone numbers for use in TV shows, films and creative works](https://www.acma.gov.au/phone-numbers-use-tv-shows-films-and-creative-works)):

- geographic: `(02) 5550 xxxx`, `(02) 7010 xxxx`, and the same 5550 and 7010 blocks in 03, 07 and 08;
- mobile: only the 30 numbers ACMA lists, such as `0491 570 006`, `0491 570 110` and `0491 579 455` (not every 0491 57x number);
- freephone and local rate: `1800 160 401`, `1800 975 707` to `1800 975 711`, `1300 975 707` to `1300 975 711`.

ACMA lists no fictional 13 xx xx number. Emergency and short codes such as 000, 112 and 106 are fine. Never use a real person's or business's number, your own included, not even in a test that checks a number is rejected: build such inputs from parts at run time (see `test/tool/phone_numbers_test.dart`).

CI enforces this: `tool/check_phone_numbers.dart` (the `phone-numbers` job in `.github/workflows/secret-scan.yml`) fails on any Australian mobile, geographic, 13, 1300 or 1800 number outside ACMA's numbers, in any form (`04xx xxx xxx`, `(0x) xxxx xxxx`, `+61 4…`, `61 4…`, with spaces, dots or dashes). It checks every tracked text file, the commit messages and added lines of the pushed or pull request commits, and the pull request title and description. It prints each hit as file and line with the number masked. Run it before you push:

```
dart tool/check_phone_numbers.dart                            # tracked files
dart tool/check_phone_numbers.dart --commits origin/main..HEAD # your commits
```

A digit string that looks like a number but is not one (a version, a long ID) goes in `tool/phone_numbers/allow_list.txt` with a reason; the file explains how. CI reads that list from `main`, so a branch cannot allow-list its own hit.

## Status

Early development. Nothing to install yet.