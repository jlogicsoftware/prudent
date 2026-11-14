# Erste Polska CSV statement: the parser contract

Status: **observed from one export, not published by the bank.** This document is the contract the
Erste importer (jlogicsoftware/prudent#73 and the tasks after it) validates against. It was
derived from a single real export that is kept outside this repository and never committed
(jlogicsoftware/prudent#41, #42). Every example below, and every file under
`server/src/test/resources/import/erste/`, is synthetic. Where one sample cannot settle a fact, the
fact is listed under [Open questions](#open-questions), not stated.

"Observed" means seen in that one file. A parser must reject what it has not seen
([Unsupported and unknown variants](#unsupported-and-unknown-variants)) rather than guess.

## How the export is produced

Not documented here. The bank's screens and menu names were not captured, and inventing them would
be worse than leaving them out.

**To be confirmed by the user in the bank UI** and then written down in this section: where the CSV
is requested, which account and date range are chosen, which format, delimiter, encoding and
"header" options (if any) are offered, and what the downloaded file is called. What is known is
only the file the bank produced: the bank names it `history*.csv`, and the observed sample was
renamed locally afterwards, so the file name carries no contract and must not be parsed.

## File-level format

| Property | Observed | Parser expectation |
|---|---|---|
| Encoding | UTF-8, no byte-order mark, Polish letters stored directly | Decode strictly as UTF-8; a BOM, invalid bytes or another encoding is rejected, not repaired |
| Line ending | LF, with a final LF after the last row | Accept LF; CRLF is not observed (open question) |
| Delimiter | comma | Comma only |
| Quoting | RFC 4180 double quotes, used exactly where a field contains a comma (every amount and balance) | Standard CSV quoting; no escaped quote observed |
| Header row | **none** | The first row is data. A file whose first row looks like a header is a different variant and is rejected |
| Fields per row | 9, on every row | Exactly 9, else the file is rejected |
| Trailing comma | every row ends with `,`, so field 9 is always empty | Require field 9 to be empty |
| Decimal separator | comma, always two decimals, e.g. `"-12,50"` | Parse comma; reject a dot or a different scale |
| Thousands separator | none observed (no amount or balance reached 1000) | Open question; reject any value with a separator until it is seen |
| Negative amounts | leading `-` (a debit); credits carry no `+` | Sign is the direction; zero is not observed |
| Currency | only in the summary row (field 5); the transaction rows carry none | One currency per file, taken from the summary row |
| Row order | **newest transaction date first** (dates never rise down the file), and the bank sequence number grows as the date falls: it is smallest on the newest row | Do not rely on order for correctness. The sequence number looks like a rank counted from the newest row, so it may shift when a later export adds newer rows; see the open question and #75 |

## Row 1: the summary row

The first row is not a transaction. It has the same nine fields, in a different order and meaning.

| # | Field | Format | Meaning |
|---|---|---|---|
| 1 | Export date | `YYYY-MM-DD` (ISO, unlike every other date) | Day the file was produced (the sample's local file name repeated it) |
| 2 | Period start | `DD-MM-YYYY` | Start of the exported range (inferred; the sample's value was the first day of the year). No period end is present. The oldest transaction in the real file starts months after this date, so a parser must not validate rows against it |
| 3 | Account number | `'` then an IBAN-style number, e.g. `'00 0000 0000 0000 0000 0000 0001` | The statement's own account. The apostrophe is a spreadsheet text-guard; strip it before comparing |
| 4 | Holder | name and address in capitals, one field | Account holder identity; personal data, never logged or kept past parsing |
| 5 | Currency | ISO 4217, `PLN` | Currency of every row |
| 6 | Unknown amount | quoted decimal | Not understood (open question). Do not use it |
| 7 | Balance before the newest row (unconfirmed) | quoted decimal | In the sample it equals the balance of the first transaction row in the file (the NEWEST one) minus that row's amount. It is not an opening balance of the range, and it is not the balance before the oldest row. Its meaning is unconfirmed (open question); do not use it |
| 8 | Unknown integer | digits | Not understood (open question); larger than any row's sequence number in the sample, so it is not a row count |
| 9 | (empty) | | Trailing-comma artefact |

## Rows 2 to N: transactions

| # | Field | Format | Meaning |
|---|---|---|---|
| 1 | Booking date | `DD-MM-YYYY` | Date the bank booked the entry. Equal to or after the transaction date, by 0 to 3 days in the sample. Not monotonic in file order. It can be later than the export date |
| 2 | Transaction date | `DD-MM-YYYY` | Date of the operation itself. The file is ordered by it, newest first |
| 3 | Description | free text, see shapes below | The bank's description of the operation |
| 4 | Counterparty | free text, or empty | Name (and address) of the other party; empty on card payments. On own-account transfers it begins with a two-word business name, then the holder's name and address (see shape 3) |
| 5 | Counterparty account | IBAN-style number in groups, e.g. `00 0000 0000 0000 0000 0000 0010`, or empty | No apostrophe here; empty on card payments |
| 6 | Amount | quoted signed decimal, comma | Negative is money out. Always in the summary row's currency |
| 7 | Balance | quoted decimal, comma | Balance the bank printed for the row. **Does not chain from one row to the next in the sample**: both file order (newest first) and the reversed, chronological order were tried, and in each only a minority of adjacent pairs satisfy balance = previous balance plus amount. No running-balance check may be built on it (open question). The fixtures do not chain either, so a parser that asserts it fails on them |
| 8 | Bank sequence number | digits, no leading zeros | Ascends down the file, i.e. as the transaction date falls, and has gaps, so the file is not the whole sequence. Unique within the sample. It behaves like a rank from the newest row, so whether it is stable across exports is not known and must not be assumed (open question) |
| 9 | (empty) | | Trailing-comma artefact |

Dates are `DD-MM-YYYY` with a hyphen; the summary row's export date is the only ISO date. Amounts and
balances are always quoted because they contain the decimal comma.

### Description shapes

All three observed, none exhaustive. Fields 4 and 5 differ per shape.

1. **Card payment.** `DOP. <MC|VISA> <masked card> PŁATNOŚĆ KARTĄ <amount> <CCY> <merchant text>`.
   The mask is `NNNNNN******NNNN` (first six and last four digits), the embedded amount uses a dot
   (`12.50`) and equals the absolute value of field 6, and the embedded currency was `PLN` in
   every case. Fields 4 and 5 are empty. The card is identifiable only by its mask.
2. **BLIK purchase.** `Zakup BLIK <merchant text>` followed by the label `ref`, a colon and 11 digits. Field 4 repeats the merchant
   text, field 5 is the merchant's account. That reference number is a per-payment value seen only
   in this shape.
3. **Own-account transfer.** `Przelew na rachunek własny`. Field 4 begins with a two-word business name, then the holder's name and
   address plus a voivodeship in capitals (the fixtures model this shape with invented words); field 5 is the other account. Only incoming transfers
   (positive amount) were observed; the wording of an outgoing own-account transfer is unknown.

A description in any other shape is not an error for the file, but the row has no known meaning and
the parser must say so per row rather than guess a merchant.

## Validation expectations for the parser (#73)

Reject the whole file, before any write, when:

1. the bytes are not valid UTF-8, or begin with a byte-order mark;
2. any row does not have exactly 9 fields, or field 9 is not empty;
3. the first row's field 1 is not an ISO date, field 2 is not `DD-MM-YYYY`, field 3 does not start
   with `'`, or field 5 is not a currency the importer supports (today: `PLN` only);
4. the summary account does not equal the destination account the user chose (account identity,
   compared after removing the apostrophe and spaces);
5. a transaction row has a date that is not a real `DD-MM-YYYY` calendar day, or a booking date
   earlier than its transaction date;
6. an amount or balance is not a quoted comma decimal with exactly two decimals, or an amount is
   zero;
7. a bank sequence number is not digits, or repeats within the file;
8. a file has no transaction row (a summary row alone is not observed, so it is not accepted
   until confirmed).

Per row, flag (do not drop silently) a description that fits none of the three shapes, a card
payment whose embedded amount differs from field 6 or whose embedded currency is not the file's, and
a counterparty account that is not IBAN-shaped. Never assert the running balance. Error messages
name the row number and the rule, never the row's content, because the content is personal data.

## Unsupported and unknown variants

None of these is in the sample. A parser must reject, not adapt, until each is observed and
written here: a header row; any encoding other than UTF-8 and any BOM; CRLF line endings;
semicolon, tab or other delimiters; a dot decimal separator or thousands separators; amounts of 1000
or more; a currency other than `PLN` and a file mixing currencies; a card payment in a foreign
currency (its embedded amount and currency versus field 6); outgoing own-account transfers; standing
orders, direct debits, fees, interest, cash withdrawals, card refunds, incoming transfers from
other people and any other operation type; multi-account files; a different number of fields;
a summary row that is absent or repeated; an empty statement.

## Open questions

These need a second export or the bank's own documentation, and are deliberately not guessed:

- The meaning of summary fields 6 and 8, and whether field 2 is the start of the range the user
  chose.
- Whether the bank sequence number (field 8) is stable for the same operation across two exports
  with different ranges. This decides whether #75 can use it as the duplicate key. Until then the
  safe assumption is that it is not, and a documented fingerprint is needed. Because it grows as the
  date falls, a newer export that adds rows above would renumber the older ones if it is a rank from
  the newest row. **#75 must not use it as a duplicate key unless a second export covering an
  overlapping range shows the same operation keeping the same number.**
- What the balance column is. It does not chain in either order tried (file and reversed), so it may be a balance at
  booking time over a wider set of entries than the file lists.
- Why the sequence has gaps: other accounts, entries omitted from this export, or pending items.
- Booking dates later than the export date: whether such rows can still change.
- Thousands separators, CRLF, foreign-currency card payments, refunds, outgoing own transfers and
  every operation type not listed above.
- The export steps in the bank UI (see the first section).

## Synthetic fixtures

All under `server/src/test/resources/import/erste/`. The names, addresses, merchants, accounts and
amounts are invented: every free-text field carries one of the whole words TEST, TESTOWY, TESTOWA, TESTOWE, TESTOWO, EXAMPLE, PRÓB, PRÓBNA or PRÓBNY, accounts have the check
digits `00` that no real IBAN has, and card masks are `000000******0000`.
`task verify:import-fixtures` fails if a fixture or this document drifts from that
([`scripts/verify_import_fixtures.py`](../scripts/verify_import_fixtures.py)). Every file in the
fixtures tree must be named `statement-*.csv`, and no other `*.csv` may sit anywhere under
`server/src/test/resources/`. It narrows the room for a leak and is not proof of
anonymity: a real name beside a marker word, a digit run shorter than 9, and the content of any
amount, date or balance (only their shape is checked) pass. Fixture rows are
newest first, with sequence numbers ascending down the file and balances that deliberately do not
chain.

| File | Covers |
|---|---|
| `statement-representative.csv` | The summary row; a card payment with MC and one with VISA; BLIK purchases; incoming own-account transfers; a sub-1 amount; an amount close to three digits; booking date later than transaction date, equal to it, and out of order against the next row; Polish diacritics; quoted comma decimals; trailing comma; `DD-MM-YYYY` dates, one ISO date; gaps in the sequence |
| `statement-minimal.csv` | The smallest valid file: the summary row and one card payment |
| `statement-diacritics.csv` | Every Polish letter (upper and lower case) in the holder, address and description; UTF-8 without a BOM |

Malformed, drifted, duplicate and mixed-currency fixtures are not here: they belong to
jlogicsoftware/prudent#77.

**Issue #42 stays open.** This document and the fixtures are its inspection and fixtures halves; the
export steps in the bank UI are user-supplied and still missing. Do not close #42 from a PR
that merges this work.
