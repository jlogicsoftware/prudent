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
can see how much there is and when it changes, not what it says. A file you save, and the copies
[the file dialogs leave](#plaintext-copies-the-file-dialogs-leave), are not encrypted.[^t-model]

## What stays on the device

Everything Prudent Local knows, in the app's own data directory:[^boot]

| What | How it is kept |
|---|---|
| The ledger: accounts (with any bank account number you enter), categories, records, transfers, corrections, plans and their skipped or confirmed dates, reminder settings and read marks, budgets, carry-over resets, goals and the history of money set aside for them, settings | In jZen's store: every file but the device's random id is AES-256-GCM, with a key of this device's own[^store] |
| The store key | Kept by the platform's secret storage, or wrapped or encrypted by a key the platform keeps: never in the clear beside the data (table below)[^key] |
| The sync key, once this device is paired (Android, Windows, Linux) | In the same secret storage[^synckey] |
| The PIN, if you set one, and its failure count | A hash, in the same secret storage; a PIN is off unless you turn it on[^pin] |
| A statement you are importing: the rows read from it, the categories and notes you give them, their fingerprints | Inside the encrypted store, in a collection that **never syncs** — not to your other devices, not to the folder, not to iCloud. Deleted when you confirm or discard the import, or 24 hours after you started it. Prudent reads the statement file once, makes no copy of it in its own code and never logs it; the file stays where you picked it, and Prudent says so after the import. On iPhone, iPad and Android [the file dialog leaves a copy](#plaintext-copies-the-file-dialogs-leave) all the same, which the app's "did not keep the statement file" message does not mention[^import] |
| Reminder notifications the app has scheduled | With the operating system. Their text has the plan's title and no amount, and a title can show on a lock screen[^notify] |
| Whether the notification permission was already refused | One flag in the app's preferences[^notify] |
| This device's name: the computer's or phone's host name (for example "my-laptop"), or the operating system's name if it has none | Inside the encrypted store, written into **every record** this device saves, and so **synced to and shown on your other devices** when two devices disagree about a record. It travels encrypted like the rest: the sync service cannot read it[^devicename] |

**Where the store key is kept**, by platform:[^key]

| Platform | Where | What that means |
|---|---|---|
| iOS, macOS (a release build) | The Keychain, readable only while the device is unlocked, on this device only | Not in a backup, not on another device |
| Android | Prudent's key, encrypted (AES-GCM) by a key the Android Keystore holds, stored in the app's private storage | The Keystore key cannot leave the device; it is **not** tied to the screen lock |
| Windows | Prudent's key in a file under `%APPDATA%`, encrypted by a key in Credential Manager (this machine, this user) | The file is useless on another machine; a program running as you can read Credential Manager |
| Linux | The login keyring (libsecret: GNOME Keyring, KWallet or the portal) | As strong as that keyring; a program running as you can read it while it is unlocked. With no secret service, or a locked one, Prudent Local refuses to open rather than keep the key in a file |

**On iPhone and iPad the store's files also get iOS Data Protection `complete`:** a second layer,
beside Prudent's own encryption, that makes them unreadable while the device is locked (a device with
no passcode has no Data Protection to apply, so it adds nothing there). Prudent Local asks iOS for it before it opens the
store, at every launch and again after this device's copy is erased, and if iOS does not set it, the
store is not opened (at launch the app says so). It covers the store's own directory and nothing else.
No other platform has this class. **Not verified on a device.**[^dataprotection]

Prudent Local never makes a new key over data it cannot open. If the key is missing or unreadable —
for example after files were restored from a backup without it — the app says so and offers to
erase this device's copy so it can sync again from your other devices, and never does that on its
own.[^restore] On Android the app does not allow Auto Backup at all, and a gate fails the build if
a manifest ever allows it.[^backup]

### Plaintext copies the file dialogs leave

Outside the encrypted store, the system's file dialogs leave **unencrypted copies in the app's own
storage**, and Prudent Local does not delete them yet. This is read from the plugins' code and has
**not been observed on a device or a simulator**.[^pickercopies]

- **Picking a file** (a statement to import, or a server export to move in) on iPhone, iPad and
  Android gives the app a copy of it: in the app's temporary folder on iOS, in its cache on Android.
- **Save a copy to a file** on iPhone and iPad also leaves what it wrote, the whole copy in plain
  text, in the app's temporary folder, whether you finished saving or cancelled.

Neither erase button removes these copies, and the Data Protection set on the store's directory does
not cover them. The operating system may clear temporary and cache files, at a time Prudent Local
does not control.

## What the app never sends

- **No server, no account, no analytics, no crash reporting, no advertising.** Prudent's own code
  for the Local app contains no code that calls a server. What a gate checks is narrower than that
  sentence: `task verify:boundaries` fails if the Local app depends on the server-connected app's
  transport or identity packages, imports `package:http` or holds an absolute `http(s)://` URL. It
  does not scan for `dart:io`'s `HttpClient`, raw sockets or what a third-party plugin does.[^boundaries]
  Today the Android release manifest asks for no `INTERNET` permission and the macOS release sandbox
  has no network entitlement; the iCloud entitlement CloudKit needs (unit 12) will change the
  macOS side.[^manifest] **Not verified:** nobody has watched a device's traffic to confirm that
  nothing else goes out.
- **Sync is the only thing that leaves the device**, and only in encrypted form, through the one
  transport described below.[^syncstart]
- **No log line carries your data.** Amounts, titles, payees, notes, account numbers, statement
  text, the sync key and pairing codes are refused in logs; a failure is logged as class names and
  codes. A test scans the app's source for it.[^logs]
- **A pairing code is never logged, put in a URL or on the clipboard.** It is shown on request,
  for five minutes, and hidden when the app goes to the background.[^pairing]
- **A bank account number never appears in the clear in an id, a file name, a log line or a notification.** An imported record's id is derived from a SHA-256 digest of the statement row (which covers its account, amount and text), so it carries the digest, never the values.[^numbers]
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

This is true of every release build. A **development** build started with `ZEN_SYNC=folder` syncs
through jZen's development stand-in instead, which stores records **unencrypted**; a release build
with that setting refuses to sync, and a gate and a test prove it.[^plan]

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

**Settings → Privacy and data → Save a copy to a file** writes a file you choose, as readable JSON,
in the same document format the server-connected app exports.[^export] **It is not everything the
store holds.**

It holds:

- your main-currency setting;
- accounts, categories and records, as the screens show them (a transfer as its two legs; a record
  that confirmed a planned payment carries its plan and an occurrence id, a one-way digest; the
  occurrence itself, and so its date, is not in the copy, jlogicsoftware/prudent#288);
- each imported record's statement key: a fingerprint and a number, never the statement's text;
- plans (with their reminder settings), budgets, carry-over resets, goals, and the history of money
  set aside for goals.

It leaves out:

- **the dates you skipped** in a plan and **which reminders you marked as read** (they are kept in
  the store, but the copy does not carry them yet, so a ledger rebuilt from the copy would show
  skipped payments as due again and read reminders as unread; jlogicsoftware/prudent#288);
- occurrences themselves, which are worked out from each plan's schedule (what the store keeps
  about a particular date, such as a skip, is the item above);
- an import you have not finished (its rows never leave the device);
- the device names written into records (above), and any disagreement between devices that has not
  been settled: a disputed record is copied as this device shows it;
- balances, budget summaries, goal progress and analytics, which are calculated from the rest.

- **The file is not encrypted.** It holds all of your finances in plain text; the app says so above
  the button. Keep it somewhere private and delete it when you are done with it. On iPhone and iPad
  [a second copy stays in the app](#plaintext-copies-the-file-dialogs-leave).[^export]
- It is **never** put on the clipboard: a clipboard reaches clipboard managers and, on some
  systems, your other devices.[^export]
- It is named `prudent-export-<date>.json`, with no account number or name in it.[^numbers]

**Moving in from the server-connected app.** "Move my data in", under Privacy and data, reads a
copy saved by the server-connected app into an empty Prudent Local and refuses the whole move
unless every account balance matches to the cent. It reads the file you pick and changes nothing
on the server: your server account stays until you erase it there, and the file stays where it was
(it is not encrypted; delete it when you are done). On iPhone, iPad and Android
[a copy of it also stays in the app](#plaintext-copies-the-file-dialogs-leave).[^movein] **Not verified:** no real export and
no device has been tried.

## Erasing it

There is nothing to erase on a server. Two buttons, under **Settings → Privacy and data**:[^erase]

- **Erase this device's copy** deletes Prudent Local's data on this device only, though not
  [the copies the file dialogs left](#plaintext-copies-the-file-dialogs-leave). Your other devices
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
- **[The copies the file dialogs left](#plaintext-copies-the-file-dialogs-leave)** in the app's
  storage.
- **Backups the operating system or the sync service made** of the folder (a sync service's own
  version history or trash, a Time Machine or File History backup of the folder). They hold
  ciphertext, which needs a sync key the erased devices have forgotten, but they are not Prudent's
  to delete.

**Not verified:** "Erase everywhere" has been driven between two stores in tests and through the
buttons of a macOS build; it has not run against iCloud or a real sync service.[^erase-unverified]

## What is not protected

Prudent Local is designed to protect data at rest on a locked device and in transit through the
sync service. It does not protect against these, and says so:

- **A device someone holds unlocked.** Without a PIN, anyone holding the unlocked device sees all
  of your finances. The PIN is off by default and offered on first launch; with one, the app locks
  when it goes to the background.[^pin]
- **A shared operating-system account.** Everyone who uses the same account on a computer sees the
  same Prudent Local. The PIN is a door, not a key: the data is not encrypted under it.[^shared]
- **A forgotten PIN.** On iOS, macOS and Android the device's own lock (passcode, Face ID, Touch ID,
  fingerprint) confirms it is you — if the device has a passcode or a biometric set; without one,
  "Forgot PIN?" erases this device's copy as below. **Windows has no biometric or device-owner check** in this
  version: "Forgot PIN?" there — and on Linux — erases this device's copy, which comes back from
  your other devices. With no other device, nothing else holds a copy; the app says so before you
  turn a PIN on, and asks you to save a copy first.[^forgot]
- **A key read from a backup on a macOS developer build.** Under jZen's ADR-087, which is still
  *proposed* upstream, a build made for development (`ZEN_ENV=dev`, not a release build) keeps the store key and the PIN hash in the macOS login
  keychain, which can be in a backup. A release build uses the device-only Keychain and the release
  task builds with `ZEN_ENV=prd`; the developer build is never meant to reach a person. A Mac that
  switches between the two cannot open its data until it is erased and synced again.[^devkeychain]
- **Android's store key and the screen lock.** The Keystore key that wraps Prudent's key is not tied
  to the screen lock, so the PIN, not the screen lock, is what stands between an unlocked phone
  and the app.[^key]
- **Anything outside the store's directory, on iOS.** Data Protection `complete` is set on that
  directory alone: not on the app's preferences, a copy you saved or
  [the copies the file dialogs leave](#plaintext-copies-the-file-dialogs-leave).[^dataprotection]
- **A photograph of a pairing code.** A pairing code is on screen for five minutes at most, but a
  photograph of it, or a copy someone wrote down, stays the sync key after that, because the code
  carries the key itself: with it and access to
  the folder, they can read and write your records. Show it only where nobody else can see it; if it
  was seen, replace the sync key.[^pairing-risk]
- **Other programs running as you.** On Windows and Linux a program running under your account can
  read Credential Manager or the unlocked keyring, and so the store key; on any platform such a
  program can read a plaintext copy you saved.[^key]
- **The plan's title on a lock screen**, in a reminder notification (never the amount).[^notify]
- **What the sync service infers from sizes and timing** (above), and anyone the folder is shared
  with.
- **A device clock that is wrong.** Time decides nothing in a merge, but it dates reminders,
  expires imports and pairing codes.[^t-model]
- **A plaintext copy you saved**, a statement file you left where you picked it, and
  [the copies the file dialogs leave](#plaintext-copies-the-file-dialogs-leave).

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
- on a real iPhone, that the store's files carry Data Protection `complete` and cannot be read while
  it is locked;
- the copies the file dialogs leave, on any device or simulator;
- the save sheet on a phone, a notification firing, and scanning a pairing code with a camera;
- that no traffic leaves a device other than through the sync transport (no device's network
  traffic has been observed).

jZen's own device check (jZenDev/jZen#231) ran its demo app on simulators, an emulator and a real Mac
and iPhone; it does not stand in for any of this, and its open follow-ups (jZenDev/jZen#266 to #271)
are gaps Prudent Local inherits.[^jzen231]

*Changes to this statement are changes to this file; its history is in Git. This statement and the
server-connected app's policy are separate on purpose (ADR-128).*

[^t-model]: ADR-100 (the threat model, rows T1–T26) and its row-by-row answer in ADR-121. T26: a wrong clock.
[^boot]: `local/prudent_local_client/lib/core/local_boot.dart` (the store's directory inside the app's support directory).
[^store]: jZen's `zen_store` (`client/zen_store/lib/src/zen_store.dart`, `zen_store_cipher.dart`); jZen ADR-065; ADR-100 T1; ADR-111.
[^key]: jZen ADR-075 and `client/zen_store_key/lib/src/zen_device_store_key.dart` (the per-platform table); ADR-100 T1, T8. That another program running as the same user can read Credential Manager or the unlocked keyring is inferred from ADR-075's "this machine, this user" and "as strong as the unlocked login keyring"; it has not been tried.
[^synckey]: `local/prudent_local_client/lib/core/local_session.dart` (`prudent_local.sync_key`, written to the secret storage).
[^pin]: ADR-100 T2; ADR-121 (first-run notice and the Lock page, `threat_model_test`, `settings_test`); jZen ADR-065 (PIN off by default), jZen ADR-087 (where its hash is kept).
[^import]: ADR-114 (the device-only collection `import_sessions`, `collection(syncs: false)`, 24-hour expiry, hourly sweep); ADR-089 (the statement read once); ADR-100 T11, T12; ADR-121 (the "file is still where you picked it" sentence).
[^notify]: ADR-056 (no amount in a notification), ADR-058 (the remembered refusal), ADR-119 (the shared scheduler reused by Local); ADR-100 T16.
[^restore]: jZen ADR-075 (no key over existing files); ADR-100 T8–T10; ADR-121 (the start-failed page offers erase-and-re-sync behind a question).
[^backup]: ADR-100 T10; ADR-124 (`task verify:local-release`, `scripts/verify_local_release.py`, which also checks the merged manifest in CI).
[^boundaries]: `scripts/verify_boundaries.py` (checks C, D and F; `DART_LIB_SCOPES` includes `local/prudent_local_client/lib`); ADR-109. Check D bans `package:http` outside a composition root, check C absolute URL literals, check F the server packages in Local's pubspec.
[^manifest]: `local/prudent_local_client/android/app/src/main/AndroidManifest.xml` (the debug and profile manifests add `INTERNET` for Flutter's tooling) and `local/prudent_local_client/macos/Runner/Release.entitlements`. iOS has no such permission to omit.
[^syncstart]: ADR-121 ("Sync is `ZenSync.start` only"); ADR-124 (`verify:local-release` fails when a transport is built or started anywhere but `sync_starter.dart`).
[^logs]: ADR-100 T21; ADR-121 (`threat_model_test` scans the source); ADR-072, ADR-094.
[^pairing]: jZen ADR-077 (a code of 77 characters with a QR code beside it, carrying the sync key; five minutes; hidden in the background; never logged); ADR-100 T17.
[^numbers]: ADR-100 T7, T22; ADR-121 (`data_copy_test`); `packages/prudent_ui/lib/privacy/privacy_actions.dart` (the file name); `DerivedIds.imported` (`local/prudent_local_store`) over `RowFingerprints` (ADR-091, ADR-112, ADR-114).
[^screen]: ADR-121 (`ZenLockGate(secureScreen: true)`); jZen ADR-085 (`FLAG_SECURE`); ADR-100 T15. Not seen on a device.
[^plan]: jZen ADR-079 and `client/zen_store_sync/lib/src/zen_sync_plan.dart` (CloudKit on iOS and macOS, the shared folder on Android, Windows and Linux; the unencrypted development transport refused in a release build, jZen ADR-085, ADR-100 T18, `task test:local-release-refusal`).
[^folder]: jZen ADR-076 (layout, encryption, "what the folder exposes", bad files skipped) as refined by jZen ADR-085 (the key-id directory); ADR-100 T6, T19.
[^folderwarn]: ADR-100 T6; ADR-121 (`threat_model_test`, `devices_and_issues_test`); `local/prudent_local_client/lib/core/local_session.dart` (`isInsideAppData`).
[^rekey]: jZen ADR-085 ("Consequences — what is not claimed"); ADR-100 T3; ADR-121 (`devices_and_issues_test`).
[^cloudkit-container]: `local/prudent_local_client/lib/core/sync_starter.dart` (`prudentCloudKitContainer`); ADR-101.
[^cloudkit-unverified]: ADR-121 ("Not verified"); plan unit 12, item 2; jZenDev/jZen#270.
[^cloudkit]: jZen ADR-065 (records in `encryptedValues`), jZen ADR-083 (HMAC record names, jZenDev/jZen#236; "Apple still sees how many records exist, their sizes and times"); `client/zen_store_cloudkit/darwin/.../ZenCloudKitBridge.swift` (one record type, the data zone and the marker zone); ADR-100 T7.
[^loss]: ADR-100 T5; ADR-121 (`threat_model_test`, `settings_test`); `local/prudent_local_client/lib/l10n/local_en.arb` (`firstRunLoss`, `syncLossWarning`).
[^export]: ADR-071 (the `DataExport` document), ADR-110 (import keys), ADR-117 (`zen_save_file`), ADR-121 (the data copy; `data_copy_test` records platform calls and finds no clipboard); ADR-100 T14. What it holds and leaves out: `LocalDataExport.build` in `local/prudent_local_client/lib/repository/local_data_export.dart` (no occurrence states, no occurrences, no import sessions, no profile).
[^movein]: ADR-103, ADR-123 (`MoveIn`, an empty store only, refused unless every balance matches); `local/prudent_local_client/lib/l10n/local_en.arb` (`moveInServerNote`).
[^erase]: jZen ADR-078 (erase this device's copy, "Forgot PIN?"), jZen ADR-085 (`eraseEverywhere`); ADR-100 T24; ADR-121 (`erase_test`); the wording is `dataEraseHint`, `dataEverywhereHint`, `dataEverywhereNoSync` in `local_en.arb`.
[^erase-leaves]: jZen ADR-085 ("Erasing leaves markers, not data"); ADR-121.
[^erase-unverified]: ADR-121 ("Checked", "Not verified"); jZen ADR-085 ("Not verified on a device").
[^devicename]: `local/prudent_local_client/lib/core/local_boot.dart` (`Platform.localHostname`, the operating system's name as a fallback); jZen's `ZenStore.outgoing` writes the device-name map into every record's payload (`client/zen_store/lib/src/zen_store.dart`), and `zen_ui_store` names the device in a conflict; the payload is encrypted by the transport (jZen ADR-076, ADR-083).
[^pairing-risk]: ADR-100 T17 (accepted); jZen ADR-077 (the code carries the sync key); jZen ADR-085 (replacing the key, folder transport only).
[^shared]: ADR-100 T25; `securityPeopleNote` in `local_en.arb`; jZen ADR-065.
[^forgot]: ADR-100 T4; jZen ADR-078 (the owner check needs a passcode or biometric set), ADR-081 and ADR-086 (`zen_ui_lock` resolves no Windows owner check); ADR-127; `securityForgetAlone` in `local_en.arb`.
[^devkeychain]: jZen ADR-087 (status: proposed; `zenIsDevBuild`; "can be in a backup"); ADR-127 (`task build:local:runners:release` passes `ZEN_ENV=prd`).
[^pickercopies]: `file_selector_ios` 0.5.3+7 (`FileSelectorPlugin.openFile`, a document picker with `asCopy: true`); `file_selector_android` 0.5.2+11 (`FileUtils.getPathFromCopyOfFileFromUri`, into the cache directory); under `zen_save_file`, `file_picker_darwin` 2.5.1 (`IOSFilePickerHandler.saveFile` writes under `tmp/flutter_file_picker` and does not remove it; 2.5.2 says it does, jZenDev/jZen#287). Prudent's pickers (`packages/prudent_ui/lib/imports/statement_picker.dart`, `local/prudent_local_client/lib/move_in/export_file_picker.dart`) delete nothing. ADR-100 T11's "refuse" to copy a statement is therefore not met on iOS and Android.
[^dataprotection]: ADR-100 T1 ("iOS adds Data Protection `complete`"); ADR-137 (before every open, nothing opened on iOS without it, `data_protection_test`); `local/prudent_local_client/lib/core/protect_store_directory.dart`; jZen's `ZenDataProtection.protectDirectory` (`client/zen_store_cloudkit/lib/src/zen_data_protection.dart`, and its Swift half for what is set). What the class does when the device locks is Apple's, and no test here shows it.
[^unit12]: Plan unit 12 (items 1–3, 6, 7) and ADR-121 ("Not verified").
[^jzen231]: ADR-127; `docs/jzen/README.md`.
