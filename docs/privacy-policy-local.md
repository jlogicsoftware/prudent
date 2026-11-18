# Prudent Local — privacy statement

Prudent Local is the form of Prudent that runs with **no server, no sign-in and no account**. This
page says what it keeps, where, who can see what, how to copy it and how to erase it. It is a
statement of its own because almost nothing in the server-connected app's policy
([`privacy-policy.md`](privacy-policy.md)) applies here: there is no operator, no database, no
identity provider and no mail relay.

> **Prudent Local is not released.** It has been built and tested on a Mac and on CI runners, never
> on a phone, a tablet or a person's own computer (plan unit 12, NOT VERIFIED). Every statement below
> is true of the code in this repository and the jZen revision it is pinned to; the ones that rest on
> something never yet run on a device are marked **not verified**, and the section
> "[What has not been verified](#what-has-not-been-verified)" lists them together. Each claim names
> its source in a footnote: an ADR in [`DECISIONS.md`](DECISIONS.md), one in jZen's archive
> (`../jZen/docs/architecture/DECISIONS.md`, "jZen ADR-…"), or a file.

## In one paragraph

Your whole financial history lives on your own devices, encrypted. Nobody runs a server that holds
it, so **nobody but you can read it and nobody can recover it for you**. If you sync, your devices
exchange encrypted records through iCloud (on iPhone, iPad and Mac) or through a folder you choose
and a sync service of your own (on Android, Windows and Linux). That service stores ciphertext: it
can see how much there is and when it changes, not what it says.[^t-model]

## What stays on the device

Everything Prudent Local knows, in the app's own data directory:[^boot]

| What | How it is kept |
|---|---|
| The ledger: accounts (with any bank account number you enter), categories, records, transfers, corrections, plans and their skipped or confirmed dates, reminder settings and read marks, budgets, carry-over resets, goals and the history of money set aside for them, settings | In jZen's store: every file but the device's random id is AES-256-GCM, with a key of this device's own[^store] |
| The store key | In the platform's secret storage, never beside the data (table below)[^key] |
| The sync key, once this device is paired (Android, Windows, Linux) | In the same secret storage[^synckey] |
| The PIN, if you set one, and its failure count | A hash, in the same secret storage; a PIN is off unless you turn it on[^pin] |
| A statement you are importing: the rows read from it, the categories and notes you give them, their fingerprints | Inside the encrypted store, in a collection that **never syncs** — not to your other devices, not to the folder, not to iCloud. Deleted when you confirm or discard the import, or 24 hours after you started it. The statement file itself is read once and never copied, cached or logged; it stays where you picked it, and Prudent says so after the import[^import] |
| Reminder notifications the app has scheduled | With the operating system. Their text has the plan's title and no amount, and a title can show on a lock screen[^notify] |
| Whether the notification permission was already refused | One flag in the app's preferences[^notify] |

**Where the store key is kept**, by platform:[^key]

| Platform | Where | What that means |
|---|---|---|
| iOS, macOS (a release build) | The Keychain, readable only while the device is unlocked, on this device only | Not in a backup, not on another device |
| Android | A key wrapped by the Android Keystore | The wrapping key cannot leave the device; it is **not** tied to the screen lock |
| Windows | A key in Credential Manager (this machine, this user) that encrypts a file under `%APPDATA%` | The file is useless on another machine |
| Linux | The login keyring (libsecret: GNOME Keyring, KWallet or the portal) | As strong as that keyring. With no secret service, or a locked one, Prudent Local refuses to open rather than keep the key in a file |

Prudent Local never makes a new key over data it cannot open. If the key is missing or unreadable —
for example after files were restored from a backup without it — the app says so and offers to
erase this device's copy so it can sync again from your other devices, and never does that on its
own.[^restore] On Android the app does not allow Auto Backup at all, and a gate fails the build if
a manifest ever allows it.[^backup]

## What the app never sends

- **No server, no account, no analytics, no crash reporting, no advertising.** The app's own code
  contains no network client: `task verify:boundaries` fails if the Local app reaches for any of
  the server-connected app's transport or identity packages, or holds an absolute URL.[^boundaries]
  On Android and macOS the release build does not even ask the operating system for network access
  (no `INTERNET` permission in the Android release manifest, no network entitlement in the macOS
  release sandbox).[^manifest]
- **Sync is the only thing that leaves the device**, and only in encrypted form, through the one
  transport described below.[^syncstart]
- **No log line carries your data.** Amounts, titles, payees, notes, account numbers, statement
  text, the sync key and pairing codes are refused in logs; a failure is logged as class names and
  codes. A test scans the app's source for it.[^logs]
- **A pairing code is never logged, put in a URL or on the clipboard.** It is shown on request,
  for five minutes, and hidden when the app goes to the background.[^pairing]
- **A bank account number is never part of an id, a file name, a log line or a notification.**[^numbers]
- **Screenshots and screen recordings are blocked on Android** while the app is open, so balances
  do not show in the recents thumbnail, a recording or a cast. iOS and the desktops have no such
  switch; there the lock's cover hides the app when it goes to the background.[^screen]

## What the sync service holds and can see

You do not have to sync. If you do, which service it is depends on the platform.[^plan]

### A folder you choose (Android, Windows, Linux)

Your devices share a 32-byte sync key, carried from one to the next by a pairing code you show on
one device and enter (or scan) on the other.[^pairing] Each device writes encrypted files into a
folder you choose, and a service of your own — Syncthing, Dropbox, OneDrive or any other — keeps
that folder in step between your devices. Prudent signs in to nothing and talks to no service; it
only reads and writes files.[^folder]

**What is in the folder:** one directory per sync key and, inside it, one per device, each holding
one file per record. Every file is AES-256-GCM under a key derived from the sync key. A record's
collection, its id and every field are inside the ciphertext, and a file's name is a keyed hash of
the record's name, so the name says nothing. The file's path is bound into the encryption, so a
file copied, renamed or replayed elsewhere fails to open instead of merging as something else.[^folder]

**What whoever stores the folder can see** — your sync service, and anyone you share the folder
with:[^folder]

- how many devices you have (directories);
- how many records each holds (files) — every device keeps a whole copy, so the folder holds each
  record once per device;
- each file's size: sizes follow the records' sizes and are not padded, so an unusually large or
  small record can be told apart from the rest;
- when files change, and on which device: roughly when, and how much, you edit;
- that you replaced the sync key or erased everything (a marker file is left; below).

**Never:** an amount, a name, a note, an account number, a category, a date inside a record, a
device's name.

So choose a folder only you can open. The app says this when you choose one: a folder shared with
someone else shows them when and how much you edit, though not what. It refuses a folder inside its
own data directory.[^folderwarn]

**Someone who can write to the folder but has no key** cannot add, change or rename a record; a
file that does not decrypt is skipped. Deleting files only delays sync.[^folder]

**A lost, sold or stolen device.** Settings → Sync and devices → "Replace the sync key" makes a new
key on this device, rewrites everything under it and leaves the old key's directory with only a
marker that tells the remaining devices to pair again. It cannot take back what the removed device
already read, and it cannot stop that device reading the folder's ciphertext while the folder is
still shared with it: stop sharing the folder with it too.[^rekey]

### iCloud (iPhone, iPad, Mac)

On Apple's platforms Prudent Local syncs through CloudKit, in the private database of your Apple
ID, in a container of its own (`iCloud.com.jlogicsoftware.prudent.local`), separate from anything
the server-connected app uses.[^cloudkit-container] **Not verified:** no CloudKit sync has run at all,
because the paid Apple Developer Program and the iCloud entitlement it needs are not in place yet
(unit 12).[^cloudkit-unverified]

**What is stored:** one CloudKit record per Prudent record, in one zone. The record's content and
its real name are fields CloudKit encrypts on your device with keys in your iCloud Keychain, so
Apple holds only ciphertext for them. The record's name that Apple can see is a keyed hash
(HMAC-SHA-256) of the real name, under a key that lives in your iCloud Keychain too.[^cloudkit]

**What Apple can see:**[^cloudkit]

- that your Apple ID uses Prudent Local's container;
- how many records there are, their sizes, and when they are created and changed;
- the zone's name and the single record type every record shares;
- after "Erase everywhere", a marker record in a zone of its own (below).

**Never:** what kind of record it is (an account, a budget, a goal), its id, or any field. An id
that Prudent derives from a month, a date or a category — a budget slot, a skipped date — is hashed
like every other name.[^cloudkit]

**A lost device** is removed from your Apple ID (Settings → Apple ID → Devices), after which it no longer receives the account's keys. CloudKit has no sync key for
Prudent to replace.[^rekey]

### If every device is lost

If every device is lost — or, on Apple, your iCloud Keychain is — **nobody can recover the data:
not us, not Apple, not your sync service.** There is no server and no key escrow. The app says so on
first launch and under Sync and devices, and offers a copy (below).[^loss]

## Your copy

**Settings → Privacy and data → Save a copy to a file** writes everything the store holds to a file
you choose, as readable JSON: accounts, categories and records (with each imported record's
statement key, a fingerprint and a number, never the statement's text), plans, budgets, resets,
goals and the money set aside for them. It is the same document the server-connected app exports,
so it can be read the same way.[^export]

- **The file is not encrypted.** It holds all of your finances in plain text; the app says so above
  the button. Keep it somewhere private and delete it when you are done with it.[^export]
- It is **never** put on the clipboard: a clipboard reaches clipboard managers and, on some
  systems, your other devices.[^export]
- It is named `prudent-export-<date>.json`, with no account number or name in it.[^numbers]

**Moving in from the server-connected app.** "Move my data in", under Privacy and data, reads a
copy saved by the server-connected app into an empty Prudent Local and refuses the whole move
unless every account balance matches to the cent. It reads the file you pick and changes nothing
on the server: your server account stays until you erase it there, and the file stays where it was
(it is not encrypted; delete it when you are done).[^movein] **Not verified:** no real export and
no device has been tried.

## Erasing it

There is nothing to erase on a server. Two buttons, under **Settings → Privacy and data**:[^erase]

- **Erase this device's copy** deletes Prudent Local's data on this device only. Your other devices
  keep theirs, and so do the folder and iCloud, from which this device gets it back when it syncs.
  The same thing is what "Forgot PIN?" does on a device with no other way to confirm it is you.
- **Erase everywhere** asks twice, then deletes your data on this device, in the folder or in
  iCloud, and on every other device the next time it syncs. It cannot be undone. Afterwards a
  device says that its data was erased, and starts again only when you ask — with an empty ledger
  and a new sync key.

**What "Erase everywhere" leaves:**[^erase-leaves]

- **Markers, not data.** In a folder, one small file per device saying the data was erased; in
  iCloud, one marker record in a zone of its own. They are what tells a device that was off. You
  may delete the folder once every device has erased.
- **A device that is off** keeps its copy until it next syncs, and its files stay in the folder
  until then, because only a device writes its own directory.
- **If this device is not syncing**, only its own copy is erased and your other devices are not
  reached; the app says so before you press the button.
- **Copies you made**: a saved copy, a server export you moved in from, a statement file.
- **Backups the operating system or the sync service made** of the folder (a sync service's own
  version history or trash, a Time Machine or File History backup of the folder). They hold
  ciphertext, which needs a sync key the erased devices have forgotten, but they are not Prudent's
  to delete.

**Not verified:** "Erase everywhere" has been driven between two stores in tests and through the
buttons of a macOS build; it has not run against iCloud or a real sync service.[^erase-unverified]

## What is not protected

Prudent Local protects data at rest on a locked device and in transit through the sync service. It
does not protect against these, and says so:

- **A device someone holds unlocked.** Without a PIN, anyone holding the unlocked device sees all
  of your finances. The PIN is off by default and offered on first launch; with one, the app locks
  when it goes to the background.[^pin]
- **A shared operating-system account.** Everyone who uses the same account on a computer sees the
  same Prudent Local. The PIN is a door, not a key: the data is not encrypted under it.[^shared]
- **A forgotten PIN.** On iOS, macOS and Android the device's own lock (passcode, Face ID, Touch ID,
  fingerprint) confirms it is you. **Windows has no biometric or device-owner check** in this
  version: "Forgot PIN?" there — and on Linux — erases this device's copy, which comes back from
  your other devices. With no other device, nothing else holds a copy; the app says so before you
  turn a PIN on, and asks you to save a copy first.[^forgot]
- **A key read from a backup on a macOS developer build.** A build made for development
  (`ZEN_ENV=dev`, not a release build) keeps the store key and the PIN hash in the macOS login
  keychain, which can be in a backup. A release build uses the device-only Keychain and the release
  task builds with `ZEN_ENV=prd`; the developer build is never meant to reach a person. A Mac that
  switches between the two cannot open its data until it is erased and synced again.[^devkeychain]
- **Android's store key and the screen lock.** The Keystore key that wraps Prudent's key is not tied
  to the screen lock, so the PIN, not the screen lock, is what stands between an unlocked phone
  and the app.[^key]
- **iOS Data Protection on the store's directory is not set.** jZen offers it
  (`ZenDataProtection.protectDirectory`) and the threat model assumed it, but Prudent Local does not
  call it yet; the store's own encryption protects the files regardless.[^dataprotection]
- **The plan's title on a lock screen**, in a reminder notification (never the amount).[^notify]
- **What the sync service infers from sizes and timing** (above), and anyone the folder is shared
  with.
- **A device clock that is wrong.** Time decides nothing in a merge, but it dates reminders,
  expires imports and pairing codes.[^t-model]
- **A plaintext copy you saved**, and a statement file you left where you picked it.

## What has not been verified

Prudent Local is not released before plan unit 12 has been done by a person on real devices
([`implemented-plans/PRUDENT-LOCAL-PLAN.md`](implemented-plans/PRUDENT-LOCAL-PLAN.md), unit 12).
What this page states but has not been seen on a device:[^unit12]

- the store key in each platform's secret storage on a real iPhone, Android phone, Windows PC and
  Linux desktop (a signed macOS release build included: an unsigned one refuses to open);
- any CloudKit sync, the hashed record names in a real container, removing a device from an Apple
  ID, the iCloud marker zone after "Erase everywhere";
- a real sync service (Syncthing, Dropbox, OneDrive) between two devices, Android's folder access,
  and what such a service's history and trash keep;
- Android's screen-capture block, its owner check, and the Keystore after a restore;
- "Forgot PIN?" on real Android, Windows and Linux;
- the save sheet on a phone, a notification firing, and scanning a pairing code with a camera.

jZen's own device check (jZenDev/jZen#231) ran its demo app on simulators, an emulator and a real Mac
and iPhone; it does not stand in for any of this, and its open follow-ups (jZenDev/jZen#266 to #271)
are gaps Prudent Local inherits.[^jzen231]

*Changes to this statement are changes to this file; its history is in Git. This statement and the
server-connected app's policy are separate on purpose (ADR-128).*

[^t-model]: ADR-100 (the threat model, rows T1–T26) and its row-by-row answer in ADR-121. T26: a wrong clock.
[^boot]: `local/prudent_local_client/lib/core/local_boot.dart` (the store's directory inside the app's support directory).
[^store]: jZen's `zen_store` (`client/zen_store/lib/src/zen_store.dart`, `zen_store_cipher.dart`); jZen ADR-065; ADR-100 T1; ADR-111.
[^key]: jZen ADR-075 and `client/zen_store_key/lib/src/zen_device_store_key.dart` (the per-platform table); ADR-100 T1, T8.
[^synckey]: `local/prudent_local_client/lib/core/local_session.dart` (`prudent_local.sync_key`, written to the secret storage).
[^pin]: ADR-100 T2; ADR-121 (first-run notice and the Lock page, `threat_model_test`, `settings_test`); jZen ADR-065 (PIN off by default), jZen ADR-087 (where its hash is kept).
[^import]: ADR-114 (the device-only collection `import_sessions`, `collection(syncs: false)`, 24-hour expiry, hourly sweep); ADR-089 (the statement read once); ADR-100 T11, T12; ADR-121 (the "file is still where you picked it" sentence).
[^notify]: ADR-056 (no amount in a notification), ADR-058 (the remembered refusal), ADR-119 (the shared scheduler reused by Local); ADR-100 T16.
[^restore]: jZen ADR-075 (no key over existing files); ADR-100 T8–T10; ADR-121 (the start-failed page offers erase-and-re-sync behind a question).
[^backup]: ADR-100 T10; ADR-124 (`task verify:local-release`, `scripts/verify_local_release.py`, which also checks the merged manifest in CI).
[^boundaries]: `scripts/verify_boundaries.py` (checks C and F; `DART_LIB_SCOPES` includes `local/prudent_local_client/lib`); ADR-109.
[^manifest]: `local/prudent_local_client/android/app/src/main/AndroidManifest.xml` (the debug and profile manifests add `INTERNET` for Flutter's tooling) and `local/prudent_local_client/macos/Runner/Release.entitlements`. iOS has no such permission to omit.
[^syncstart]: ADR-121 ("Sync is `ZenSync.start` only"); ADR-124 (`verify:local-release` fails when a transport is built or started anywhere but `sync_starter.dart`).
[^logs]: ADR-100 T21; ADR-121 (`threat_model_test` scans the source); ADR-072, ADR-094.
[^pairing]: jZen ADR-077 (a code of 77 characters with a QR code beside it, carrying the sync key; five minutes; hidden in the background; never logged); ADR-100 T17.
[^numbers]: ADR-100 T22; ADR-121 (`data_copy_test`); `packages/prudent_ui/lib/privacy/privacy_actions.dart` (the file name).
[^screen]: ADR-121 (`ZenLockGate(secureScreen: true)`); jZen ADR-085 (`FLAG_SECURE`); ADR-100 T15. Not seen on a device.
[^plan]: jZen ADR-079 and `client/zen_store_sync/lib/src/zen_sync_plan.dart` (CloudKit on iOS and macOS, the shared folder on Android, Windows and Linux; the unencrypted development transport refused in a release build, jZen ADR-085, ADR-100 T18, `task test:local-release-refusal`).
[^folder]: jZen ADR-076 (layout, encryption, "what the folder exposes", bad files skipped) as refined by jZen ADR-085 (the key-id directory); ADR-100 T6, T19.
[^folderwarn]: ADR-100 T6; ADR-121 (`threat_model_test`, `devices_and_issues_test`); `local/prudent_local_client/lib/core/local_session.dart` (`isInsideAppData`).
[^rekey]: jZen ADR-085 ("Consequences — what is not claimed"); ADR-100 T3; ADR-121 (`devices_and_issues_test`).
[^cloudkit-container]: `local/prudent_local_client/lib/core/sync_starter.dart` (`prudentCloudKitContainer`); ADR-101.
[^cloudkit-unverified]: ADR-121 ("Not verified"); plan unit 12, item 2; jZenDev/jZen#270.
[^cloudkit]: jZen ADR-065 (records in `encryptedValues`), jZen ADR-083 (HMAC record names, jZenDev/jZen#236; "Apple still sees how many records exist, their sizes and times"); `client/zen_store_cloudkit/darwin/.../ZenCloudKitBridge.swift` (one record type, the data zone and the marker zone); ADR-100 T7.
[^loss]: ADR-100 T5; ADR-121 (`threat_model_test`, `settings_test`); `local/prudent_local_client/lib/l10n/local_en.arb` (`firstRunLoss`, `syncLossWarning`).
[^export]: ADR-071 (the `DataExport` document), ADR-110 (import keys), ADR-117 (`zen_save_file`), ADR-121 (the data copy; `data_copy_test` records platform calls and finds no clipboard); ADR-100 T14.
[^movein]: ADR-103, ADR-123 (`MoveIn`, an empty store only, refused unless every balance matches); `local/prudent_local_client/lib/l10n/local_en.arb` (`moveInServerNote`).
[^erase]: jZen ADR-078 (erase this device's copy, "Forgot PIN?"), jZen ADR-085 (`eraseEverywhere`); ADR-100 T24; ADR-121 (`erase_test`); the wording is `dataEraseHint`, `dataEverywhereHint`, `dataEverywhereNoSync` in `local_en.arb`.
[^erase-leaves]: jZen ADR-085 ("Erasing leaves markers, not data"); ADR-121.
[^erase-unverified]: ADR-121 ("Checked", "Not verified"); jZen ADR-085 ("Not verified on a device").
[^shared]: ADR-100 T25; `securityPeopleNote` in `local_en.arb`; jZen ADR-065.
[^forgot]: ADR-100 T4; jZen ADR-078, ADR-081 and ADR-086 (`zen_ui_lock` resolves no Windows owner check); ADR-127; `securityForgetAlone` in `local_en.arb`.
[^devkeychain]: jZen ADR-087 (`zenIsDevBuild`; "can be in a backup"); ADR-127 (`task build:local:runners:release` passes `ZEN_ENV=prd`).
[^dataprotection]: ADR-100 T1 ("iOS adds Data Protection `complete`"); `client/zen_store_cloudkit/lib/src/zen_data_protection.dart`; no call to it in `local/prudent_local_client/lib` (checked 2026-11-18); ADR-128. The follow-up is jlogicsoftware/prudent#285.
[^unit12]: Plan unit 12 (items 1–3, 6, 7) and ADR-121 ("Not verified").
[^jzen231]: ADR-127; `docs/jzen/README.md`.
