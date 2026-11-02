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

Emergency and short codes such as 000, 112 and 106 are fine.

Never use a real person's, business's or public service's number, your own included. That holds even when the test only checks the number is rejected, and even when the number is built from parts. A crisis line or a company's 13 number counts too.

13 numbers (TJ's rule, 2 November 2026). ACMA lists no fictional 13 number, so tests that need one use `arbitrary13Number` from `test/support/test_numbers.dart`:

- It's an arbitrary shape, never a real business's or public service's number.
- It's defined in one place. The call_engine package can't import the app's `test/` folder, so it keeps a copy in `packages/call_engine/test/support/test_numbers.dart`, and `test/tool/test_numbers_test.dart` checks the two match.
- It's data only, for formatting, normalisation and matching. It is never dialled, never sent anywhere (the mock server included), and never in screenshots, goldens or store material. The same test fails if it appears in `lib/`, `tool/mock_server/`, `assets/`, `docs/store/` or `test/goldens/`.
- The phone number check allows it in those two files only. Any other 13 number, anywhere, fails CI.

1300 and 1800 tests use ACMA's fictional numbers.

Building a number from parts at run time is only for the check's own tests in `test/tool/phone_numbers_test.dart`, which need non-ACMA numbers to prove they are caught. They use made-up digits only. The same rule as the 13 constant applies to them: data only, never dialled or sent anywhere, never in screenshots, goldens or store material, and only in the scanner's own tests.

CI enforces this: `tool/check_phone_numbers.dart` (the `phone-numbers` job in `.github/workflows/secret-scan.yml`) fails on any Australian mobile, geographic, 13, 1300 or 1800 number outside ACMA's numbers. It catches these forms:

- national: `04xx xxx xxx`, `(0x) xxxx xxxx`, `13 xx xx`, `13x xxx`;
- international: `+61 4…`, `61 4…`, `0061 4…`, `0011 61 4…`, URL-encoded `%2B614…`;
- separators: spaces (up to three), dots, dashes, or a dot or dash with spaces around it (` - `).

It checks every tracked text file, the commit messages and added lines of the pushed or pull request commits, and the pull request title and description. It prints each hit as file and line with the number masked.

It does not catch a number split across lines, or one glued to letters, digits or `_` (`id_0412…`, `abc0412…`), since those look like identifiers. Review for them by eye.

Run it before you push:

```
dart tool/check_phone_numbers.dart                            # tracked files
dart tool/check_phone_numbers.dart --commits origin/main..HEAD # your commits
```

A digit string that looks like a number but is not one (a version, a long ID) goes in `tool/phone_numbers/allow_list.txt` with a reason; the file explains how. CI runs the check and reads the allow-list from `main`, never from your branch. A pull request that changes `tool/check_phone_numbers.dart`, `tool/phone_numbers/` or `.github/workflows/secret-scan.yml` fails until the project lead adds the `phone-check-approved` label.

## Status

Early development. Nothing to install yet.