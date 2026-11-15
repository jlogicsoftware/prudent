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

Everything in this section was **reported by the user from the bank's web UI on 2026-11-15**, from
four screenshots of the Polish interface. It was not read from a bank document and it was not
re-checked against a download made for this repository; UI labels are quoted as the bank shows them.

1. In the bank's web banking, open the top menu **"Historia"**, then the sub-tab **"Historia"** (the
   other sub-tab is "Przegląd wydatków").
2. Set the filter panel above the list. It offers a search box ("Wpisz odbiorcę, nadawcę, tytuł lub
   nr konta, min. 3 znaki"), "Okres" (the period; the default shown is "Bieżący rok (2026)"), "Kwota
   transakcji" (from and to), "Wydatki i wpływy" (expenses and inflows), "Status" ("Wszystkie") and a
   radio "Widoczne w tabeli" with the options "Data transakcji" and "Data księgowania i saldo". Period,
   amount, type, status and what is visible in the table are chosen here; the download dialog offers
   none of them. That the filter also decides what the download holds is assumed, not seen.
3. Under **"Pobierz listę transakcji"** press **"CSV"** (the other button is "PDF").
4. In the small dialog, leave the dropdown **"Separator"** on **"przecinek - ,"** (comma, the default
   shown). It is the only option the dialog has; the others it lists are "średnik - ;", "pipe - |" and
   "tabulator - tab". Press **"POBIERZ"**.
5. The bank downloads `history_YYYYMMDD.csv`, where `YYYYMMDD` is the export date without hyphens
   (the user's example: `history_20261115.csv`). Import the file as it is: do not open and save it in
   a spreadsheet or edit it.

**The importer requires the comma separator.** A file in another separator is refused whole, before
any write, and nothing is repaired. What the importer actually emits is decided by the file's shape,
not by a delimiter guess: a first line that has no comma and no double quote but contains a
semicolon or a tab is `layout.delimiter`; a first line with a double quote inside an unquoted field is
`csv.malformed`, whatever the separator; a first line that holds both a comma (a decimal comma is
enough) and the other separator, and a file separated by a pipe, are not recognised as separator
mistakes and surface as `row.field_count`. All of these refuse the file. A real semicolon download
most likely keeps decimal commas, so it would not give `layout.delimiter`. What a real semicolon, pipe
or tab download looks like was not seen.

The file name carries no contract and is never parsed: the importer reads the bytes only; the export
date is the one inside the summary row. The pattern above is what the user saw, not something the
importer relies on.

### Still unconfirmed

- How the account is chosen: whether the "Historia" page is per account or lists several, and so
  which account a given file holds.
- Whether the "Widoczne w tabeli" radio changes the columns of the CSV. The sample this contract was
  derived from held both a transaction date and a booking date and a balance column while "Data
  transakcji" appeared selected in the screenshots, which does not settle it.
- Whether the filter applies to the download at all (assumed, not seen), and whether its limits (for
  example "Okres") change anything in the file beyond which rows it holds, such as the summary row's
  period start.
- The maximum period or number of rows one export holds.
- The exact content of a download made with a non-default separator.

## File-level format

| Property | Observed | Parser expectation |
|---|---|---|
| Encoding | UTF-8, no byte-order mark, Polish letters stored directly | Decode strictly as UTF-8; a BOM, invalid bytes or another encoding is rejected, not repaired |
| Line ending | LF, with a final LF after the last row | Accept LF; CRLF is not observed (open question). A missing final LF is rejected (`layout.no_final_newline`): the file may be cut short |
| Delimiter | comma | Comma only |
| Quoting | RFC 4180 double quotes, used exactly where a field contains a comma (every amount and balance) | Standard CSV quoting; no escaped quote observed |
| Header row | **none** | The first row is data. A file whose first row looks like a header is a different variant and is rejected |
| Fields per row | 9, on every row | Exactly 9, else the file is rejected |
| Trailing comma | every row ends with `,`, so field 9 is always empty | Require field 9 to be empty |
| Decimal separator | comma, always two decimals, e.g. `"-12,50"` | Parse comma in the amount; reject a dot or a different scale there. Balance and summary fields 6 to 8 are not read |
| Thousands separator | none observed (no amount or balance reached 1000 in the sample) | An amount is digits only: `-?` then 1 to 11 whole digits (no leading zero except a single `0`), a comma and two decimals, so `1000,00` is read and `1.000,00` or `1 000,00` is `amount.invalid`. How a real amount of 1000 or more is written is an open question. The balance column is never read, so a separator there changes nothing |
| Negative amounts | leading `-` (a debit); credits carry no `+` | Sign is the direction; zero is not observed |
| Currency | only in the summary row (field 5); the transaction rows carry none | One currency per file, taken from the summary row |
| Row order | **newest transaction date first** (dates never rise down the file), and the bank sequence number grows as the date falls: it is smallest on the newest row | Do not rely on order for correctness, and do not reject a file for its order: one sample cannot say that another order is a different variant, and nothing downstream needs order. The sequence number looks like a rank counted from the newest row, so it may shift when a later export adds newer rows; see the open question and #75 |

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

## Upload bounds (the import workflow's, before any parser runs)

A refusal before the importer is also a rule code with no text, so the client can say what to do: an empty upload (`statement.empty_upload`), a file over 5 MiB (`statement.too_large`), more than 5000 transaction rows (`statement.too_many_rows`) and a destination account that is not the caller's or does not exist (`account.not_found`). They are the workflow's, not the importer's, so the rule list below does not contain them.

## Validation expectations for the parser (#73)

Reject the whole file, before any write, when (the rule code is in brackets; error messages carry the code and row numbers only):

1. the bytes are not valid UTF-8 (`encoding.not_utf8`), contain a NUL byte (`encoding.nul_byte`) or begin with a byte-order mark (`encoding.bom`);
2. a CR is present (`layout.line_ending`) or the last line has no LF (`layout.no_final_newline`);
3. a line is not well-formed CSV: an unterminated quote, a quote inside an unquoted field, text after a closing quote (`csv.malformed`);
4. the first row is a single field containing `;` or a tab (`layout.delimiter`), looks like a header (`layout.header_row`), or is a transaction instead of a summary (`layout.summary_missing`);
5. any row, the summary row included, does not have exactly 9 fields (`row.field_count`) or field 9 is not empty (`row.trailing_field`);
6. the summary's field 1 is not an ISO date (`summary.export_date_invalid`), field 2 is not a real `DD-MM-YYYY` day (`summary.period_start_invalid`), field 3 does not start with `'` and hold an account-number shape (`summary.account_invalid`), or field 5 is not a supported currency, today `PLN` only (`currency.unsupported`). Summary fields 4 and 6 to 8 are not read;
7. the statement's account does not equal the destination account the user chose, compared in the one normal form (whitespace of any kind and the apostrophe removed, upper-cased, a leading `PL` dropped from a 26-digit number); an account without a stored number is refused, not guessed (`account.number_missing`, `account.identity_mismatch`; `account.identity_unverifiable` is the defensive refusal when a session carries no identity token);
8. a transaction row has a date that is not a real `DD-MM-YYYY` calendar day (`date.invalid`), a date before 2000-01-01 or later than one year after today (`date.out_of_range`), or a booking date earlier than its transaction date (`date.booking_before_transaction`);
9. an amount is not `-?` plus digits (1 to 11, no separator, no leading zero except a single `0`), a comma and exactly two decimals (`amount.invalid`), or is zero (`amount.zero`). The balance is not checked;
10. a bank sequence number is not digits without a leading zero (`sequence.invalid`) or repeats within the file (`sequence.duplicate`);
11. a card payment names a currency other than the file's (`card.foreign_currency`). This rejects the whole file, not the row: whether the amount column then holds the card currency or the account currency is not observed, so no row of such a file can be trusted to carry the right amount;
12. a file has no transaction row (`statement.empty`);
13. the amount column no longer holds the amount (`layout.amount_column`), told without the balance column (never read) from two witnesses. Every real card payment and BLIK purchase is outgoing, so **any** card or BLIK row with a positive amount refuses the file. A card payment also writes its own amount in its description, so when field 6 disagrees with that text on **half or more of at least two** card rows the file is refused too; one disagreeing row among consistent ones is not enough (that stays a flagged row, below). The case this is for is a bank that swaps the amount and balance columns: without it an incoming own-account transfer would be accepted with the balance as its amount.

Per row, flag (do not drop silently; the row is returned rejected with a code and no text) a description that fits none of the three shapes, including a card payment that has a counterparty (`description.unknown_shape`); a card payment whose embedded amount differs from field 6 (`card.amount_mismatch`); a counterparty account that is not two digits then six groups of four (`counterparty_account.invalid`); an own-account transfer with a negative amount (`amount.sign_unexpected`: no such row was observed; a card or BLIK entry with a positive amount is not flagged, it refuses the file, item 13); and an own-account transfer whose other account is the statement's own (`transfer.same_account`: it cannot be a transfer between two accounts). Never assert the running balance. Error messages name the row number and the rule, never the row's content, because the content is personal data.

## Unsupported and unknown variants

None of these is in the sample. A parser must reject, not adapt, until each is observed and
written here: a header row; any encoding other than UTF-8 and any BOM; CRLF line endings;
semicolon, tab or other delimiters; a dot decimal separator or thousands separators in an amount;
a currency other than `PLN` and a file mixing currencies; a card payment in a foreign
currency (the whole file is rejected, see rule 11 above); outgoing own-account transfers; standing
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
- Whether the bank's date range selects rows by transaction date or by booking date. If by booking date, two exports can be adjacent
  by booking date and still both hold rows of one transaction date, and a genuinely new row can look identical to an imported one
  (same transaction date, amount and text, another booking day), which duplicate detection (ADR-091) marks as a duplicate. A second
  export taken for an adjacent or overlapping range, compared by both dates, would settle it. Until then the review screen (#74) must
  let the user include a row marked as a duplicate.
- What the balance column is. It does not chain in either order tried (file and reversed), so it may be a balance at
  booking time over a wider set of entries than the file lists.
- Why the sequence has gaps: other accounts, entries omitted from this export, or pending items.
- Booking dates later than the export date: whether such rows can still change.
- How an amount of 1000 or more is written. The importer reads digits only (`1000,00`) and treats any separator as `amount.invalid`; **a private export that contains such an amount must be checked to confirm the format** (the fixtures cannot settle it).
- Thousands separators in the balance column (never read), CRLF, foreign-currency card payments, refunds, outgoing own transfers and
  every operation type not listed above.
- The parts of the export procedure listed as unconfirmed under [How the export is produced](#how-the-export-is-produced).

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

Malformed, drifted, duplicate and mixed-currency statements are not fixtures: a file that is meant to be
refused is derived in memory from a synthetic base statement by the failure matrix (ADR-094,
`ImportFailureCatalogue`), so no refused-file variant needs a place in this tree or a pass through the gate.
`ErsteFormatDriftTest` pins these three fixtures to their exact parsed rows and holds the rule codes named
in the validation list above to the ones the importer can emit.

**Issue #42** is complete with this document: the inspection, the fixtures and the export steps
(ADR-095) are all recorded. What stays unconfirmed is listed in the section on the export.
