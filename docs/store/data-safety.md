# Play data safety form (draft answers)

Draft for task 5.4, following spec 22 (Play data safety) and `privacy-policy.md`. Rows marked **decide** need mobile-lead or TJ before the form is submitted.

## Overview questions

| Question | Answer |
| --- | --- |
| Does the app collect or share any of the required user data types? | Yes |
| Is all user data collected by the app encrypted in transit? | **Decide.** Yes only if every app call's audio uses SRTP. The API, SIP signalling (TLS) and GlitchTip (HTTPS) are always encrypted, but spec 22 turns SRTP on only when the edge carries it. If call audio can travel as plain RTP, the answer is No. |
| Do you provide a way for users to request that their data is deleted? | **Decide.** Accounts are created by the workplace's administrator, not in the app. Proposed: yes, through the workplace administrator or the support contact in the privacy policy, with a web page that says so. |

## Data types

"Collected" means it leaves the phone. Nothing is "shared" in Play's sense: GlitchTip is self-hosted and FCM is a service provider delivering push for us.

| Category | Data type | Collected | Shared | Optional | Purposes | Processed ephemerally |
| --- | --- | --- | --- | --- | --- | --- |
| Personal info | Email address | Yes | No | No (needed to sign in) | App functionality, Account management | No |
| Personal info | Name, address, phone number, other | No | | | | |
| Device or other IDs | Device or other IDs (FCM push token, device id) | Yes | No | No | App functionality (incoming calls) | No |
| App info and performance | Crash logs | Yes | No | No (users can't turn it off; scrubbed on the device) | App functionality (fixing faults) | No |
| App info and performance | Diagnostics (device model, app version; call logs only when the user taps Send) | Yes | No | Device model and version: No. Call logs: Yes | App functionality, Account management (device list) | No |
| App info and performance | Other app performance data | No | | | | |
| Messages | Other in-app messages (SMS the user sends and reads on the workplace's lines) | Yes | No | Yes (only with an SMS line) | App functionality | No |
| Messages | Emails, SMS or MMS from the phone | No | | | | |
| Audio | Voice or sound recordings (voicemail greetings the user records) | Yes | No | Yes | App functionality | No |
| Audio | Voice or sound recordings (call audio during a call) | Yes | No | No (needed for a call) | App functionality | Yes: it passes through our servers in transit to the other party, isn't end-to-end encrypted, and isn't stored by the app |
| Contacts | Contacts (phone address book) | No (read on the device only, APP12) | | | | |
| Location | Approximate or precise | No | | | | |
| Photos and videos | Photos | No (QR scan stays on the device) | | | | |
| Financial info, Health and fitness, Calendar, Web browsing, Files and docs | All | No | | | | |
| App activity | App interactions, search history, installed apps, other actions | No | | | | |

## Security practices section

- Data is encrypted in transit: as decided above.
- Independent security review: No.
- Committed to the Play Families policy: Not applicable (not for children).
