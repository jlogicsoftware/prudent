#!/usr/bin/env python3
"""Fail if an import fixture or the Erste contract document looks like it holds real banking data.
Run by `task verify:import-fixtures`.

No real statement may enter this repository (jlogicsoftware/prudent#41, #42). A reviewer cannot
tell a plausible fake from a real IBAN by eye, so the fixtures are held to a narrow synthetic
vocabulary and this gate refuses anything outside it.

Scope. Every file under `server/src/test/resources/import/` must be a lowercase
`statement-<letters, digits, hyphens>.csv` that sits in `import/erste/`; any `*.csv` (any case)
anywhere else under `server/src/test/resources/` fails too, so a stray export cannot sit beside
the fixtures. Only the gitignored `.DS_Store` is skipped, by name. `docs/erste-csv-contract.md` is
scanned for long and 9-to-12-digit numbers the same way the fixtures are.

Numbers. One separator class (space, hyphen, dot, no-break space; up to two between characters) and
one rule judge every long sequence: 13 or more characters that are digits or the mask characters
`*`, bullet and middle dot may appear only as the fictional IBAN (22 zeros then any four digits) or
the fictional card mask `000000******0000`. So a card or IBAN written with hyphens, dots, no-break
spaces, spaces, or masked with asterisks or bullets is refused. In a CSV field any other run of 9 to
12 digits (same separators) is refused as a PESEL, phone number or short reference. Also refused: a
card mask shorter than that other than the fictional one, and a `ref:` number not starting `000`.

Row shape (fixtures only). Every row has exactly 9 fields with field 9 empty and no line break inside
a field. The first row is the summary row and the others are transactions; each field has its own
pattern (dates, quoted comma-decimals with two places, sequence digits, a fictional grouped IBAN,
a three-letter currency). Free-text fields (description, counterparty; the holder on the summary row)
must carry the WHOLE WORD TEST, TESTOWY, TESTOWA, TESTOWE, TESTOWO, EXAMPLE, PRÓB, PRÓBNA or PRÓBNY
(case-insensitive); the one exemption is a description that is exactly the bank's fixed phrase
`Przelew na rachunek własny`, which holds no free text to mark. A non-UTF-8 fixture, and a scope
that matches no fixture at all (a gate over nothing is a failure), fail too.

What still passes, so nobody trusts it further than it goes: a real name or merchant next to a marker
word in the same field; a digit run shorter than 9; amounts, dates and balances, which are checked
for shape and never for content; a `ref:000` followed by arbitrary digits; a sequence number of any
digits; a run split by three or more separator characters or by letters; a `.DS_Store` file, skipped
by name. It narrows the room for a leak; it is not proof of anonymity, and the reviewer of a fixture
change still reads it.

Usage: verify_import_fixtures.py [REPO_ROOT]   (default: the repository this script lives in)
Stdlib only, 3.9 floor.
"""
import csv
import io
import re
import sys
from pathlib import Path

RESOURCES = "server/src/test/resources"
IMPORT_DIR = RESOURCES + "/import"
FIXTURES = IMPORT_DIR + "/erste"
CONTRACT = "docs/erste-csv-contract.md"
FIXTURE_NAME = re.compile(r"statement-[a-z0-9-]+\.csv")
SKIPPED_NAMES = {".DS_Store"}
MARKER = re.compile(
    r"(?<!\w)(?:TEST|TESTOWY|TESTOWA|TESTOWE|TESTOWO|EXAMPLE|PRÓB|PRÓBNA|PRÓBNY)(?!\w)",
    re.IGNORECASE | re.UNICODE,
)
OWN_TRANSFER = "Przelew na rachunek własny"

# One separator class and one mask class for every number rule, so no rule can see a sequence
# that another one has declared out of its range.
SEP = "[ \\-.\u00a0]"
MASKCH = "*\u2022\u00b7"
LONG_TOKEN = re.compile(
    r"(?<![\d%s])[\d%s](?:%s{0,2}[\d%s]){12,}(?![\d%s])" % (MASKCH, MASKCH, SEP, MASKCH, MASKCH)
)
FICTIONAL_IBAN = re.compile(r"(?<!\d)0(?: ?0){21}(?: ?\d){4}(?!\d)")
SHORT_NUMBER = re.compile(r"(?<!\d)\d(?:%s{0,2}\d){8,}(?!\d)" % SEP)
MASK = re.compile(r"\d{4,6}[*\u2022\u00b7]{3,}\d{2,4}")
FICTIONAL_MASK = "000000******0000"
REF = re.compile(r"ref:(\S*)", re.I)
FICTIONAL_REF = re.compile(r"ref:000\d+", re.I)

GROUPED_IBAN = r"00(?: 0000){5} \d{4}"
DATE = re.compile(r"\d{2}-\d{2}-\d{4}")
ISO_DATE = re.compile(r"\d{4}-\d{2}-\d{2}")
AMOUNT = re.compile(r"-?\d+,\d{2}")
SEQUENCE = re.compile(r"[1-9]\d*")
DIGITS = re.compile(r"\d+")
CURRENCY = re.compile(r"[A-Z]{3}")
SUMMARY_ACCOUNT = re.compile(r"'" + GROUPED_IBAN)
TRANSACTION_ACCOUNT = re.compile(GROUPED_IBAN)


def number_problems(text: str) -> list:
    problems = []
    for match in LONG_TOKEN.finditer(text):
        token = match.group()
        if token == FICTIONAL_MASK or FICTIONAL_IBAN.fullmatch(token):
            continue
        if sum(c.isdigit() for c in token) < 4:
            continue
        if any(c in MASKCH for c in token):
            problems.append("a masked long number other than the fictional card mask %s" % FICTIONAL_MASK)
        else:
            problems.append(
                "a long number that is not the fictional IBAN (22 zeros then 4 digits; starts %s...)"
                % re.sub(r"\D", "", token)[:2]
            )
    for match in MASK.finditer(text):
        if match.group() != FICTIONAL_MASK:
            problems.append("a card mask other than the fictional %s" % FICTIONAL_MASK)
    for match in REF.finditer(text):
        if not match.group(1).startswith("000"):
            problems.append("a ref: number that does not start with 000")
    return problems


def short_number_problems(field: str) -> list:
    """Runs of 9 or more digits that are not the fictional ones. A run of 13 or more is also reported
    by number_problems: both use the same separator class, so none passes both."""
    rest = FICTIONAL_REF.sub(" ", field.replace(FICTIONAL_MASK, " "))
    rest = FICTIONAL_IBAN.sub(" ", rest)
    return [
        "a run of 9 or more digits in a field (a PESEL, phone or reference looks like this)"
        for _ in SHORT_NUMBER.finditer(rest)
    ]


def field_problems(number: int, row: list, pattern: dict, marked: dict) -> list:
    """pattern: index -> (label, regex or None for empty-only, empty allowed); marked: free-text indexes."""
    problems = []
    for index, (label, regex, empty_ok) in pattern.items():
        value = row[index]
        if value == "":
            if not empty_ok:
                problems.append("row %d field %d (%s) is empty" % (number, index + 1, label))
        elif regex is None or not regex.fullmatch(value):
            problems.append("row %d field %d is not a valid %s" % (number, index + 1, label))
    for index, label in marked.items():
        value = row[index]
        if not value.strip() or (label == "description" and value == OWN_TRANSFER):
            continue
        if not MARKER.search(value):
            problems.append(
                "row %d %s carries none of the whole words TEST / EXAMPLE / PRÓB" % (number, label)
            )
    return problems


def summary_problems(number: int, row: list) -> list:
    return field_problems(
        number,
        row,
        {
            0: ("export date", ISO_DATE, False),
            1: ("period start date", DATE, False),
            2: ("summary account", SUMMARY_ACCOUNT, False),
            3: ("holder", re.compile(r".+"), False),
            4: ("currency", CURRENCY, False),
            5: ("amount", AMOUNT, False),
            6: ("balance", AMOUNT, False),
            7: ("integer", DIGITS, False),
            8: ("trailing field (must be empty)", None, True),
        },
        {3: "holder"},
    )


def transaction_problems(number: int, row: list) -> list:
    return field_problems(
        number,
        row,
        {
            0: ("booking date", DATE, False),
            1: ("transaction date", DATE, False),
            2: ("description", re.compile(r".+"), False),
            3: ("counterparty", re.compile(r".*"), True),
            4: ("counterparty account", TRANSACTION_ACCOUNT, True),
            5: ("amount", AMOUNT, False),
            6: ("balance", AMOUNT, False),
            7: ("sequence number", SEQUENCE, False),
            8: ("trailing field (must be empty)", None, True),
        },
        {2: "description", 3: "counterparty"},
    )


def csv_problems(text: str) -> list:
    problems = []
    for number, row in enumerate(csv.reader(io.StringIO(text, newline="")), start=1):
        if len(row) != 9:
            problems.append("row %d has %d fields, expected exactly 9" % (number, len(row)))
            continue
        if any("\n" in value or "\r" in value for value in row):
            problems.append("row %d has a line break inside a field" % number)
            continue
        problems += summary_problems(number, row) if number == 1 else transaction_problems(number, row)
        for index, value in enumerate(row):
            for problem in short_number_problems(value):
                problems.append("row %d field %d: %s" % (number, index + 1, problem))
    return problems


def check(root: Path) -> list:
    failures = []
    resources = root / RESOURCES
    files = sorted(
        p for p in (resources.rglob("*") if resources.is_dir() else [])
        if p.is_file() and p.name not in SKIPPED_NAMES
    )
    fixtures = root / FIXTURES
    for path in files:
        rel = path.relative_to(root)
        in_fixtures = fixtures in path.parents
        in_import = (root / IMPORT_DIR) in path.parents
        is_csv = path.suffix.lower() == ".csv"
        if not (in_import or is_csv):
            continue
        if in_fixtures:
            if not FIXTURE_NAME.fullmatch(path.name):
                failures.append("%s: every file here must be named statement-*.csv, lowercase" % rel)
        else:
            failures.append("%s: only statement-*.csv under %s may sit here" % (rel, FIXTURES))
        try:
            text = path.read_bytes().decode("utf-8")
        except UnicodeDecodeError:
            failures.append("%s: not valid UTF-8" % rel)
            continue
        for problem in number_problems(text) + csv_problems(text):
            failures.append("%s: %s" % (rel, problem))
    if not any(FIXTURE_NAME.fullmatch(p.name) and fixtures in p.parents for p in files):
        failures.append("%s holds no fixture file: the gate would be checking nothing" % FIXTURES)
    contract = root / CONTRACT
    if not contract.is_file():
        failures.append("%s is missing" % CONTRACT)
    else:
        text = contract.read_text(encoding="utf-8")
        for problem in number_problems(text):
            failures.append("%s: %s" % (CONTRACT, problem))
        for number, line in enumerate(text.splitlines(), start=1):
            for problem in short_number_problems(line):
                failures.append("%s line %d: %s" % (CONTRACT, number, problem))
    return failures


def main(argv: list) -> int:
    root = Path(argv[1]) if len(argv) > 1 else Path(__file__).resolve().parent.parent
    failures = check(root)
    for failure in failures:
        print("FAIL " + failure, file=sys.stderr)
    if failures:
        return 1
    print("ok: import fixtures and the Erste contract hold only synthetic values")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
