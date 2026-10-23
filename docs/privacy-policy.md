# Prudent — privacy policy

Prudent is a minimalist personal-finance application. This page says what it keeps about you,
where, for how long, and how to get a copy of it or have it deleted. It is written to be true of the
code in this repository; the tests named at the end are what keep it true.

**Who "the operator" is.** Prudent is software, and each deployment of it is run by someone — the
person or organisation whose server your app talks to. That is the party responsible for your data
and the one to contact about it. This repository does not name one, because it describes the
software and not any deployment of it (ADR-021).

## What Prudent keeps

On the server, for each person:

| What | Why |
|---|---|
| The email address you sign in with, and — if ever set — a display name and a nickname | To identify you and to send the account emails (confirmation and password recovery, sent by the identity provider) |
| Your language | To show the app, and write account emails, in it |
| Your accounts and their currencies, categories, records (title, payee, note, amount, date), transfers and balance corrections | The application: this is what it is for |
| Your plans and their occurrences, reminder settings and whether you have read a reminder | Planned and recurring transactions |
| Your budgets, carry-over resets and goals, and the history of money set aside for goals | Budgets and goals |
| Your settings (main currency) | Display |

On your device: your sign-in session, the reminder notifications the app has scheduled (their text
carries no amount), and one flag recording that the notification permission was already asked for.

**What Prudent does not do.** It has no analytics, no advertising and no tracking. Your data is not
sold, shared, or sent to anyone other than the infrastructure that runs it (below). The app talks to
one server and nothing else.

## Where it is processed

The operator's deployment: a server and a Postgres database, and Supabase for sign-in (and so for
the account emails). Those are the only processors.

## How long it is kept

**Until you delete it.** Nothing expires on its own today.

The framework Prudent is built on has a dormancy cycle — a warning email after 330 days without a
sign-in, a final one 23 days later, and, 7 days after that, anonymisation of the account — and
Prudent's side of it (deleting all of the account's data when it is anonymised) is built and tested.
But the framework anonymises an account only after a warning was **confirmed delivered**, and Prudent
has no mail sender to deliver one, so no account ever gets that far. A test
(`PrivacyRetentionStatementTest`) pins that, so this paragraph cannot go stale quietly. Giving the
cycle a way to warn people is open work; until it exists, dormant accounts are kept, and the only
way your data is removed is you deleting it (below) or the operator doing so.

## Your copy

**Settings → Privacy and data → Copy my data** puts everything above on your clipboard as readable
JSON — paste it into any text editor. It is complete, not what the screens happen to show: archived
categories and goals, skipped occurrences and revoked carry-over resets are in it. Money is in
minor units (`1234` is 12.34), exactly as the API spells it. Balances, budget summaries, goal progress
and analytics are not in it because they are calculated from the rest on every read.

The same document is `GET /api/v1/privacy/export` for anyone who would rather call the API; it is
never cached.

## Deleting it

**Settings → Privacy and data → Delete my data.** You are asked to type your email address, then:

- every account, category, record, plan, budget, goal and the history around them is deleted, in
  one step that either completes or changes nothing;
- your profile row is kept but anonymised — the address becomes an unroutable placeholder and the
  name is cleared — the same state the dormancy erasure leaves;
- the reminder notifications on that device are cancelled and you are signed out.

It cannot be undone. Copy your data first if you want to keep it.

### What deletion does not remove — read this

- **Your sign-in with the identity provider.** Supabase holds your email address and password hash
  in its own table, which Prudent's server cannot reach: it deliberately does not hold the key that
  would allow it. Deleting your data leaves that record, and **signing in again with it starts an
  empty account**. To remove it, ask the operator to delete the user in Supabase (Authentication →
  Users). The operator should do this when you ask for erasure.
- **Backups.** A deployment that takes database backups keeps your data in the ones taken before you
  deleted it, until they expire. The persistent proof-of-concept environment has none today
  (ADR-068); the operator defines retention when it does (#47), and that period is how long an
  erased person's data can still exist in one.
- **A copy you made.** What you copied to your clipboard or saved is yours to handle.

### If you cannot sign in

The in-app route needs a session. Deleting the sign-in record at Supabase stops anyone using the
account, but it does **not** delete the Prudent data behind it, and no dormancy cycle will (see
"How long it is kept"). An operator-initiated erasure of a person's Prudent data is **not built**;
it would be a new route, and is a follow-up rather than something this policy can promise. Until it
exists, a person who can no longer sign in has to be helped to sign in again — password recovery —
and delete from inside the app.

## For the operator

- Dormancy erasure does not run, whatever the scheduler does: see "How long it is kept". Do not tell
  anyone their data expires.
- On an erasure request, also delete the person's Supabase user. Prudent's side is complete when the
  app has said so; the identity record is the half only you can remove.
- This policy and the code move together: a table added with a `user_id` fails the privacy test
  suite until it is both exported and erased (see below).

## What proves this

`server/src/test/java/prudent/privacy/`:

- `PrivacyCoverageTest` finds every table with a `user_id` column **from the database's own schema**
  and requires each to be seeded, to appear in the export, and to be empty after an erasure — and
  requires another user's rows in those tables to be untouched. A table added tomorrow fails it until
  the exporter and the eraser know about it.
- `PrivacyExportTest` — readable JSON in both transports, rows in every lifecycle state, nothing of
  another user's, no caching.
- `PrivacyErasureTest` — the typed-address confirmation, that a refusal deletes nothing, that other
  users are untouched, and that the anonymised profile is one the framework itself recognises.
- `PrudentRetentionCleanupTest` — Prudent's cascade when the framework anonymises an account, driven
  through the framework's own anonymisation, and `PrivacyRetentionStatementTest` — that no account
  is in fact anonymised today, which is what "Nothing expires on its own" rests on.

`client/test/privacy_actions_test.dart` and `privacy_screen_test.dart` cover the app's side.

*Changes to this policy are changes to this file; its history is in Git.*
