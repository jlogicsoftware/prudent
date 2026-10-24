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
| The email address you sign in with, and — if ever set — a display name and a nickname | To identify you, to send the account emails (confirmation and password recovery, sent by the identity provider) and, if your account goes unused, the two warnings described under "How long it is kept" |
| Your language | To show the app, and write account emails and those warnings, in it |
| When you last signed in, and when each warning was sent | To run the schedule under "How long it is kept" |
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

The operator's deployment: a server and a Postgres database, Supabase for sign-in (and so for the
account emails), and a mail relay that sends the two unused-account warnings. The relay sees your
sign-in address and the text of those warnings (below) and nothing else; it keeps whatever record of
sent mail its own terms say. Those are the only processors.

## How long it is kept

**Until you delete it — or until you have not signed in for about a year and have been warned twice.**

The schedule is counted from your last sign-in. The windows are the framework's own, which Prudent
does not change:

| When | What happens |
|---|---|
| **330 days** after your last sign-in | A first warning email to the address you sign in with: your data will be deleted in 30 days unless you sign in |
| **23 days** after the first warning | A final warning: 7 days left |
| **7 days** after the final warning | The account is anonymised and **everything Prudent holds for it is deleted** — the same thing "Delete my data" does (below) |

**Signing in at any point before the last step cancels all of it** and starts the count again. The
check runs once a day, so each step can come up to a day after its date.

Two things about the warnings, so that nobody is surprised by either:

- **They are sent in your language** (English, Ukrainian or Polish) and carry your sign-in address,
  the number of days left and a link to the app. Nothing from your accounts, records, budgets or
  goals is in them, and the operator's logs name you by an internal id and never by address.
- **A warning counts only when the operator's mail relay accepted it.** If it could not be sent —
  the relay is down, your address is refused — the account does not move to the next step and its
  data is kept until a warning can be sent. So an account whose address no longer receives mail is
  not deleted by this route. The relay accepting a message is the most Prudent can know: it does not
  see a message later bounce, be filtered as spam or go unread. "Warned" here means "sent", not
  "read".

This route does not remove your sign-in with the identity provider either; see "What deletion does
not remove".

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

The in-app route needs a session, so a person who cannot sign in asks the operator instead. On a
request the operator erases that person's Prudent data by their user id, without their session: the
same deletion, in one transaction, as the in-app route, and the profile is anonymised the same way.
Only an administrator of the service can do it — anyone else, signed in or not, is refused. Deleting
the sign-in record at Supabase on its own stops anyone using the account but does **not** delete the
Prudent data behind it, so the operator does both. The operator finds your user id from the address you
give, in the sign-in record. If you do not ask, the data is deleted on the schedule under "How long it is kept" — if the warnings can reach the address
on the account.

## For the operator

- Dormancy erasure runs only if **both** halves are in place: the Cloud Scheduler entry that drives
  the daily job, and a working mail relay (`SMTP_HOST`, `SMTP_FROM`, `SMTP_USERNAME`,
  `SMTP_PASSWORD`). Without the relay nothing is ever warned, so nothing ever expires, and nothing
  else says so. `task verify:deploy` fails when either is missing from the running service. It does
  **not** prove that the relay authenticates or that a message reaches an inbox: the first real
  warning is the first proof. Verify the sender domain with the relay (SPF and DKIM), or the warnings
  are accepted and then filtered.
- The relay is a processor of the addresses it sends to; keep it in the list you give people who ask.
- An account the identity table marks as premium is never touched by the cycle. Prudent never sets
  that flag.
- On an erasure request, also delete the person's Supabase user. Prudent's side is complete when the
  app has said so; the identity record is the half only you can remove.
- For a person who cannot sign in, erase their Prudent data yourself:
  `POST /api/v1/admin/privacy/users/{userId}/erase` as a signed-in user whose `users.role` is
  `admin` (`docs/persistent-environment.md` shows the call). It refuses everyone else (401 without a
  session, 403 for any other role), answers 404 for an id Prudent holds nothing under, and refuses
  your own id. It logs the opaque id and the row counts, nothing else. Repeating it is harmless.
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
- `OperatorErasureTest` — the operator route: only an admin may call it (anonymous 401, an ordinary
  user 403, nothing deleted), every table with a `user_id` is empty for the person afterwards and the
  operator's and everyone else's rows are untouched, the profile is one the framework recognises as
  anonymised, the operator cannot erase themselves, an unknown id is 404, and the log line names the
  ids and counts and no address or name.
- `PrudentRetentionCleanupTest` — Prudent's cascade when the framework anonymises an account, driven
  through the framework's own anonymisation.
- `PrivacyDormancyErasureTest` — the schedule above, end to end: a dormant account is sent the first
  warning, then the final one, then anonymised, and afterwards no table with a `user_id` holds a row
  for it while another user's rows are untouched; signing in cancels it; the warning is in the
  account's language and carries nothing from the ledger; and the windows this page states are the
  ones the framework is configured with.
- `PrivacyDormancyUnreachableMailerTest` — with a relay that always fails, no warning is stamped,
  no account advances however often the job runs, nothing is erased, and the failure is logged
  against the account's id and never its address.

`client/test/privacy_actions_test.dart` and `privacy_screen_test.dart` cover the app's side.

*Changes to this policy are changes to this file; its history is in Git.*
