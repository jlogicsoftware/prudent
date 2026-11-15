#!/usr/bin/env python3
"""Proves scripts/verify_import_fixtures.py can fail. Run by `task verify:import-fixtures` first.

Each test builds a throwaway tree from a clean base and requires the verdict it should give, so a
gate that stopped matching would not read green forever.
"""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "verify_import_fixtures.py"
GOOD_ROW = (
    "03-01-2026,02-01-2026,DOP. MC 000000******0000 PŁATNOŚĆ KARTĄ 1.00 PLN SKLEP TESTOWY,,,"
    '"-1,00","9,00",2,\n'
)
GOOD_BLIK = (
    "03-01-2026,03-01-2026,Zakup BLIK SKLEP TESTOWY ref:00000000001,SKLEP TESTOWY,"
    '00 0000 0000 0000 0000 0000 0010,"-1,00","8,00",3,\n'
)
SUMMARY = "2026-01-31,01-01-2026,'00 0000 0000 0000 0000 0000 0001,JAN TESTOWY,PLN,\"0,00\",\"10,00\",9,\n"
CONTRACT = "# contract\n00 0000 0000 0000 0000 0000 0001 is fictional.\n"


def run(mutate=None) -> subprocess.CompletedProcess:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        fixtures = root / "server/src/test/resources/import/erste"
        fixtures.mkdir(parents=True)
        (root / "docs").mkdir()
        (fixtures / "statement-a.csv").write_text(SUMMARY + GOOD_ROW + GOOD_BLIK, encoding="utf-8")
        (root / "docs/erste-csv-contract.md").write_text(CONTRACT, encoding="utf-8")
        if mutate:
            mutate(root, fixtures)
        return subprocess.run(
            [sys.executable, "-I", str(SCRIPT), str(root)], capture_output=True, text=True
        )


def append(text: str):
    def mutate(root, fixtures):
        with open(fixtures / "statement-a.csv", "a", encoding="utf-8") as f:
            f.write(text)
    return mutate


class VerifyImportFixtures(unittest.TestCase):
    def assertFails(self, result, needle):
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(needle, result.stderr)

    def test_clean_tree_passes(self):
        result = run()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_real_looking_iban_fails(self):
        row = GOOD_BLIK.replace("00 0000 0000", "12 3456 7890")
        self.assertFails(run(append(row)), "fictional IBAN")

    def test_unspaced_iban_fails(self):
        row = GOOD_BLIK.replace("00 0000 0000 0000 0000 0000 0010", "12345678900000000000000010")
        self.assertFails(run(append(row)), "fictional IBAN")

    def test_real_looking_card_mask_fails(self):
        self.assertFails(run(append(GOOD_ROW.replace("000000******0000", "123456******7890"))), "card mask")

    def test_unmasked_card_number_fails(self):
        self.assertFails(run(append(GOOD_ROW.replace("000000******0000", "1234567890123456"))), "long number")

    def test_ref_must_look_invented(self):
        self.assertFails(run(append(GOOD_BLIK.replace("ref:00000000001", "ref:12345678901"))), "ref:")

    def test_row_without_marker_fails(self):
        row = GOOD_ROW.replace("SKLEP TESTOWY", "SKLEP SPOZYWCZY")
        self.assertFails(run(append(row)), "none of the whole words")

    def test_non_utf8_fails(self):
        def mutate(root, fixtures):
            (fixtures / "statement-a.csv").write_bytes(b"\xb3\xea\xf1 TEST,x,y,z\n")
        self.assertFails(run(mutate), "not valid UTF-8")

    def test_fixture_name_must_be_statement(self):
        def mutate(root, fixtures):
            (fixtures / "statement-a.csv").rename(fixtures / "example_export_9999-99-99.csv")
        self.assertFails(run(mutate), "named statement-*.csv")

    def test_no_fixture_fails(self):
        def mutate(root, fixtures):
            (fixtures / "statement-a.csv").unlink()
        self.assertFails(run(mutate), "no fixture file")

    def test_contract_with_real_iban_fails(self):
        def mutate(root, fixtures):
            (root / "docs/erste-csv-contract.md").write_text("12 3456 7890 1234 5678 9012 3456\n", encoding="utf-8")
        self.assertFails(run(mutate), "erste-csv-contract.md")

    def test_missing_contract_fails(self):
        def mutate(root, fixtures):
            (root / "docs/erste-csv-contract.md").unlink()
        self.assertFails(run(mutate), "is missing")

    def test_zero_prefixed_but_not_fictional_iban_fails(self):
        row = GOOD_BLIK.replace("00 0000 0000 0000 0000 0000 0010", "00 1234 5678 9012 3456 7890 1234")
        self.assertFails(run(append(row)), "fictional IBAN")

    def test_marker_must_be_a_whole_word(self):
        for word in ("LATEST", "PROBLEM", "CONTESTANT"):
            row = GOOD_ROW.replace("SKLEP TESTOWY", "SKLEP " + word)
            self.assertFails(run(append(row)), "none of the whole words")

    def test_marker_needed_in_counterparty_too(self):
        row = GOOD_BLIK.replace("SKLEP TESTOWY,00", "REAL MERCHANT,00")
        self.assertFails(run(append(row)), "counterparty carries none")

    def test_marker_needed_in_description_too(self):
        row = GOOD_BLIK.replace("Zakup BLIK SKLEP TESTOWY", "Zakup BLIK REAL MERCHANT")
        self.assertFails(run(append(row)), "description carries none")

    def test_summary_holder_needs_marker(self):
        def mutate(root, fixtures):
            path = fixtures / "statement-a.csv"
            path.write_text(path.read_text(encoding="utf-8").replace("JAN TESTOWY", "JAN KOWALSKI", 1), encoding="utf-8")
        self.assertFails(run(mutate), "row 1 holder carries none")

    def test_own_transfer_phrase_is_exempt_only_with_marked_counterparty(self):
        good = "04-01-2026,04-01-2026,Przelew na rachunek własny,FIRMA TESTOWA JAN TESTOWY,00 0000 0000 0000 0000 0000 0002,\"5,00\",\"9,00\",4,\n"
        self.assertEqual(run(append(good)).returncode, 0)
        self.assertFails(run(append(good.replace("FIRMA TESTOWA JAN TESTOWY", "JAN KOWALSKI"))), "counterparty carries none")

    def test_eleven_digit_number_in_text_fails(self):
        row = GOOD_ROW.replace("SKLEP TESTOWY", "SKLEP TESTOWY 44051401359")
        self.assertFails(run(append(row)), "9 or more digits")

    def test_spaced_phone_number_fails(self):
        row = GOOD_ROW.replace("SKLEP TESTOWY", "SKLEP TESTOWY 600 700 800")
        self.assertFails(run(append(row)), "9 or more digits")

    def test_uppercase_extension_fails(self):
        def mutate(root, fixtures):
            (fixtures / "statement-a.csv").rename(fixtures / "statement-a.CSV")
        self.assertFails(run(mutate), "lowercase")

    def test_other_extensions_fail(self):
        for name in ("notes.txt", "export.tsv", "sheet.xlsx", "Statement-b.csv"):
            def mutate(root, fixtures, name=name):
                (fixtures / name).write_bytes(b"x")
            self.assertFails(run(mutate), name)

    def test_real_file_name_in_fixtures_fails(self):
        def mutate(root, fixtures):
            (fixtures / "example_export_9999-99-99.csv").write_text(SUMMARY + GOOD_ROW, encoding="utf-8")
        self.assertFails(run(mutate), "example_export_9999-99-99.csv")

    def test_ds_store_is_skipped(self):
        def mutate(root, fixtures):
            (fixtures / ".DS_Store").write_bytes(b"\x00")
        self.assertEqual(run(mutate).returncode, 0)

    def test_long_numbers_with_other_separators_fail(self):
        cases = {
            "hyphen iban": "12-3456-7890-1234-5678-9012-3456",
            "dot iban": "12.3456.7890.1234.5678.9012.3456",
            "nbsp iban": "12\u00a03456\u00a07890\u00a01234\u00a05678\u00a09012\u00a03456",
            "hyphen card": "5412-7512-3456-1234",
            "dot card": "5412.7512.3456.1234",
            "nbsp card": "5412\u00a07512\u00a03456\u00a01234",
            "space card": "5412 7512 3456 1234",
        }
        for name, number in cases.items():
            row = GOOD_ROW.replace("SKLEP TESTOWY", "SKLEP TESTOWY " + number)
            result = run(append(row))
            self.assertEqual(result.returncode, 1, name)
            self.assertIn("long number", result.stderr, name)

    def test_masked_cards_fail(self):
        for mask in ("5412 75** **** 1234", "5412 75\u2022\u2022 \u2022\u2022\u2022\u2022 1234", "541275******1234", "5412-75**-****-1234"):
            row = GOOD_ROW.replace("SKLEP TESTOWY", "SKLEP TESTOWY " + mask)
            self.assertFails(run(append(row)), "masked long number")

    def test_fictional_mask_and_iban_still_pass(self):
        self.assertEqual(run(append(GOOD_BLIK)).returncode, 0)

    def test_short_run_with_dot_or_nbsp_fails(self):
        for number in ("600.700.800", "600\u00a0700\u00a0800"):
            row = GOOD_ROW.replace("SKLEP TESTOWY", "SKLEP TESTOWY " + number)
            self.assertFails(run(append(row)), "9 or more digits")

    def test_ten_fields_fail(self):
        self.assertFails(run(append(GOOD_ROW.rstrip("\n") + "x,\n")), "expected exactly 9")

    def test_eight_fields_fail(self):
        self.assertFails(run(append(GOOD_ROW.rstrip("\n")[:-1] + "\n")), "expected exactly 9")

    def test_blank_line_fails(self):
        self.assertFails(run(append("\n")), "expected exactly 9")

    def test_nonempty_trailing_field_fails(self):
        row = GOOD_ROW.replace(",2,\n", ",2,JAN\n")
        self.assertFails(run(append(row)), "field 9 is not a valid trailing field")

    def test_counterparty_account_must_be_empty_or_fictional(self):
        row = GOOD_ROW.replace(',,,"-1,00"', ',,JAN KOWALSKI,"-1,00"')
        self.assertFails(run(append(row)), "field 5 is not a valid counterparty account")

    def test_embedded_newline_fails(self):
        row = GOOD_ROW.replace("SKLEP TESTOWY", 'SKLEP TESTOWY\nJAN KOWALSKI').replace("03-01-2026,02-01-2026,", '03-01-2026,02-01-2026,"', 1)
        row = row.replace('KOWALSKI,,,', 'KOWALSKI",,,', 1)
        self.assertFails(run(append(row)), "line break inside a field")

    def test_transaction_dates_must_be_dd_mm_yyyy(self):
        self.assertFails(run(append(GOOD_ROW.replace("03-01-2026,02-01-2026", "2026-01-03,02-01-2026"))), "field 1 is not a valid booking date")
        self.assertFails(run(append(GOOD_ROW.replace("03-01-2026,02-01-2026", "03-01-2026,2/1/2026"))), "field 2 is not a valid transaction date")

    def test_amount_and_balance_shape(self):
        self.assertFails(run(append(GOOD_ROW.replace('"-1,00"', '"-1.00"'))), "field 6 is not a valid amount")
        self.assertFails(run(append(GOOD_ROW.replace('"-1,00"', '"-1,0"'))), "field 6 is not a valid amount")
        self.assertFails(run(append(GOOD_ROW.replace('"9,00"', '"9,000"'))), "field 7 is not a valid balance")
        self.assertFails(run(append(GOOD_ROW.replace('"-1,00"', "-1,00"))), "expected exactly 9")

    def test_sequence_must_be_digits(self):
        self.assertFails(run(append(GOOD_ROW.replace(',2,\n', ',x2,\n'))), "field 8 is not a valid sequence number")
        self.assertFails(run(append(GOOD_ROW.replace(',2,\n', ',,\n'))), "field 8 (sequence number) is empty")

    def test_empty_description_fails(self):
        row = "03-01-2026,02-01-2026,,,,\"-1,00\",\"9,00\",2,\n"
        self.assertFails(run(append(row)), "field 3 (description) is empty")

    def _summary_mutation(self, old, new):
        def mutate(root, fixtures):
            path = fixtures / "statement-a.csv"
            path.write_text(path.read_text(encoding="utf-8").replace(old, new, 1), encoding="utf-8")
        return mutate

    def test_summary_fields_are_checked(self):
        cases = [
            ("2026-01-31,", "31-01-2026,", "field 1 is not a valid export date"),
            ("01-01-2026,'", "2026-01-01,'", "field 2 is not a valid period start date"),
            (",'00 0000", ",00 0000", "field 3 is not a valid summary account"),
            (",'00 0000 0000 0000 0000 0000 0001", ",'12 3456 7890 1234 5678 9012 3456", "field 3 is not a valid summary account"),
            ("JAN TESTOWY,PLN", "JAN TESTOWY,pln", "field 5 is not a valid currency"),
            ("JAN TESTOWY,PLN", "JAN TESTOWY,PLNX", "field 5 is not a valid currency"),
            ('"0,00"', '"0,0"', "field 6 is not a valid amount"),
            ('"10,00",9', '"10.00",9', "field 7 is not a valid balance"),
            (",9,\n", ",9x,\n", "field 8 is not a valid integer"),
            (",9,\n", ",9,JAN\n", "field 9 is not a valid trailing field"),
        ]
        for old, new, needle in cases:
            self.assertFails(run(self._summary_mutation(old, new)), needle)

    def test_summary_holder_must_not_be_empty(self):
        self.assertFails(run(self._summary_mutation("JAN TESTOWY", "")), "field 4 (holder) is empty")

    def test_csv_anywhere_in_resources_fails(self):
        for rel in ("export.csv", "import/other.csv", "import/erste/sub/data.CSV", "misc/Real.Csv"):
            def mutate(root, fixtures, rel=rel):
                path = root / "server/src/test/resources" / rel
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(SUMMARY + GOOD_ROW, encoding="utf-8")
            self.assertFails(run(mutate), rel.split("/")[-1])

    def test_non_csv_elsewhere_in_resources_is_ignored(self):
        def mutate(root, fixtures):
            (root / "server/src/test/resources/application.properties").write_text("a=b\n", encoding="utf-8")
        self.assertEqual(run(mutate).returncode, 0)

    def test_contract_with_nine_digit_run_fails(self):
        def mutate(root, fixtures):
            (root / "docs/erste-csv-contract.md").write_text("call 600 700 800 now\n", encoding="utf-8")
        self.assertFails(run(mutate), "erste-csv-contract.md line 1")

    def test_contract_with_hyphenated_long_number_fails(self):
        def mutate(root, fixtures):
            (root / "docs/erste-csv-contract.md").write_text("12-3456-7890-1234-5678-9012-3456\n", encoding="utf-8")
        self.assertFails(run(mutate), "long number")


if __name__ == "__main__":
    unittest.main()
