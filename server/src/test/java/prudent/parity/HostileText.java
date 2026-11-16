package prudent.parity;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * The hostile text inputs every golden vector file runs: white space that one Java method sees and
 * another does not, combining marks, the Turkish i, astral characters, lone surrogates, controls
 * that {@code trim()} removes and {@code strip()} keeps. All synthetic (ADR-088): no real account
 * number, no real name.
 */
final class HostileText {

  private HostileText() {}

  /** A grinning face, U+1F600: one code point, two UTF-16 units. */
  static final String ASTRAL = "😀";

  /** Inputs about text in general: trimming, stripping, blankness, counting. */
  static List<String> general() {
    List<String> inputs =
        new ArrayList<>(
            Arrays.asList(
                null,
                "",
                " ",
                "\t\n\r",
                "\u000B\u000C",
                "\u0000",
                "\u0001",
                "\u001C\u001D\u001E\u001F",
                "\u0085",
                " ",
                " ",
                "       ",
                " ",
                "   ",
                "​",
                "  ",
                " ",
                " ",
                "　",
                "᠎",
                "﻿",
                "a",
                " a ",
                "\ta\n",
                "\u0001a\u0001",
                " a ",
                " a ",
                " a ",
                "\u0085a\u0085",
                "﻿a﻿",
                "　a　",
                "é",
                "é",
                " é ",
                "İ",
                "ı",
                "i̇",
                "ß",
                "ſ",
                "ﬀ",
                ASTRAL,
                " " + ASTRAL + " ",
                "\uD800",
                "\uDC00",
                "a\uD800b",
                "\uDC00\uD800",
                "Bread and milk",
                " Bread  and milk "));
    inputs.add("x".repeat(500));
    inputs.add("x".repeat(501));
    inputs.add(ASTRAL.repeat(500));
    inputs.add(ASTRAL.repeat(501));
    inputs.add(" " + ASTRAL.repeat(500) + " ");
    inputs.add(" " + ASTRAL.repeat(500) + " ");
    inputs.add(" " + ASTRAL.repeat(500));
    inputs.add("é".repeat(250));
    inputs.add("é".repeat(251));
    return inputs;
  }

  /** Inputs about currency codes. */
  static List<String> currencies() {
    return Arrays.asList(
        null,
        "",
        "   ",
        "PLN",
        "pln",
        "Pln",
        " pln ",
        "\tPLN\n",
        "\u0000usd\u001F",
        " PLN",
        "PLN ",
        " PLN",
        "eur\u0085",
        "﻿EUR",
        "ınr",
        "İNR",
        "inr",
        "ſek",
        "ßp",
        "ﬀ",
        "ﬀr",
        "ＰＬＮ",
        "ṔLN",
        "PL",
        "PLNN",
        "ABC",
        "XXX",
        "XTS",
        "XAU",
        "EUR",
        "USD",
        "UAH",
        "GBP",
        "CHF",
        "JPY",
        ASTRAL,
        "\uD800LN",
        "P\uDC00N");
  }

  /** Inputs about bank account numbers. Every digit run is synthetic (check digits 00). */
  static List<String> accountNumbers() {
    String twentySix = "00000000000000000000000001";
    return Arrays.asList(
        null,
        "",
        "   ",
        " ",
        "  ",
        twentySix,
        "PL" + twentySix,
        "pl" + twentySix,
        "Pl" + twentySix,
        "PL00 0000 0000 0000 0000 0000 0001",
        " pl00 0000 0000 0000 0000 0000 0001 ",
        "PL00 0000 0000 0000 0000 0000 0001",
        "PL00 0000 0000 0000 0000 0000 0001",
        "PL00 0000 0000 0000 0000 0000 0001",
        "PL00　0000　0000　0000　0000　0000　0001",
        "PL00\u00850000\u00850000\u00850000\u00850000\u00850000\u00850001",
        "PL00\t0000\n0000\r0000\u000B0000\u000C0000 0001",
        "PL00﻿0000000000000000000001",
        "PL00​0000000000000000000001",
        "PL" + twentySix.substring(1),
        "PL" + twentySix + "0",
        "DE00000000000000000000",
        "de00000000000000000000",
        "GB00XXXX00000000000000",
        "gb00xxxx00000000000000",
        "123456789",
        "1234567890",
        "1".repeat(34),
        "1".repeat(35),
        "ABCDEFGHIJ",
        "abcdefghij",
        "ıBCDEFGHIJ",
        "İBCDEFGHIJ",
        "ßBCDEFGHIJ",
        "ſBCDEFGHIJ",
        "０".repeat(10),
        "éBCDEFGHIJ",
        "éBCDEFGHIJ",
        ASTRAL + "000000000",
        "\uD800000000000",
        "0000000000\uDC00",
        "PL-00-0000",
        "Cash wallet",
        "cash wallet");
  }

  /** Inputs about civil dates, beyond the systematic sweep. */
  static List<String> dates() {
    return Arrays.asList(
        null,
        "",
        " ",
        "2026-11-15",
        " 2026-11-15",
        "2026-11-15 ",
        "2026-11-15T00:00",
        "2026-11-15Z",
        "2026-1-15",
        "2026-11-5",
        "26-11-15",
        "02026-11-15",
        "+2026-11-15",
        "+10000-01-01",
        "+999999999-12-31",
        "+1000000000-01-01",
        "-999999999-01-01",
        "-1000000000-01-01",
        "-0001-01-01",
        "-0000-01-01",
        "+0000-01-01",
        "0000-01-01",
        "-10000-01-01",
        "9999-12-31",
        "２０２６-11-15",
        "٢٠٢٦-11-15",
        "2026/11/15",
        "2026-11-15\u0000",
        "2026‐11‐15",
        "2026-+1-15",
        "2026-11-+5",
        "2026--1-15");
  }

  /** Inputs about months. */
  static List<String> months() {
    return Arrays.asList(
        null,
        "",
        " ",
        "2026-11",
        "2026-01",
        "2026-12",
        "2026-00",
        "2026-13",
        "0000-01",
        "9999-12",
        "+2026-11",
        "-2026-11",
        "10000-01",
        "2026-1",
        "2026-11-01",
        " 2026-11",
        "2026-11 ",
        "２０２６-11",
        "٢٠٢٦-11",
        "2026/11");
  }
}
