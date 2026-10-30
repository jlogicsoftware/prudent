# Snyk Code findings: triage

Snyk Code is run against this public repository (`snyk code test`). A finding is a claim about a data
flow, not a verdict, so each was traced to where its input comes from and who controls it.

**Where ignores live.** Snyk Code does not read ignores from a `.snyk` file; they are stored by Snyk
against the finding (`snyk ignore create --finding-id=… --ignore-type=… --reason=… --expiration=…`,
Consistent Ignores). This file is the written reason behind each of them, so that an ignore can be
audited from the repository and re-applied if the Snyk organisation is ever replaced. Nothing here is
excluded from scanning: every file is still scanned, and a *new* finding in any of them still shows.

Triage of jlogicsoftware/prudent#196 to #200, 2026-10-30.

## Fixed

| Finding | Cause and fix |
|---|---|
| ReDoS in the hooks (#197) — real, though not for the reason Snyk gives | `\bmvnw\b[^|;&]*\b(test\|verify)\b` is quadratic: every `mvnw` in a command rescans to the end of its segment. A 200 KB command made of `mvnw ` took 37 s in a hook that runs on every Bash call. The window is now `{0,256}`, which is linear (0.10 s on the same input). `test_verify_guard.py` times every configured pattern on hostile input and fails above one second. |
| Session id and skill name used as path parts (#196) | The hook payload's `session_id` was joined into a path under `.git`, where `os.path.join` lets an absolute id replace the base and `..` leaves it. It is now one safe component, or a hash of itself when it is not. A skill name from `skill-map.json` that is not a plain name is refused with a message. Regression tests write a hostile id and check that nothing lands outside the guard's directory. |
| Echoed request header in a test server (#200) | The handler passed the request's headers into the function that builds the response. It now records the one header the test asserts on and hands the response builder nothing from the request. Both findings (XSS, header splitting) are gone from the scan. |
| Copy-pasted table-name SQL in four tests (#198) | `UserOwnedRows` is the single place where a table name enters a statement. It rejects anything that is not `[a-z][a-z0-9_]*` and quotes the rest. One of the four findings disappeared; the other three remain because Snyk does not treat the check as a sanitiser (see below). |

## Ignored, with the reason

| Rule | Where | Type | Why it is not a vulnerability here |
|---|---|---|---|
| `python/PT` | `scripts/verify_proto_reflection.py`, `scripts/audit_maven.py`, `scripts/strip_flutter_sourcemap.py` | not-vulnerable | The path is a command-line argument of a developer or CI tool, chosen by whoever runs it. They already hold every right on that file system; the tool crosses no privilege boundary. |
| `python/PT` | `git_guard.py` (`commit-msg` mode), both copies | not-vulnerable | The argument is the message file git itself passes to its own hook. |
| `python/PT` | `skill_guard.py`, `verify_guard.py`, both copies | not-vulnerable | The root is `CLAUDE_PROJECT_DIR`, set by the Claude Code or Codex host that launches the hook; the rest of each path is a fixed suffix. Whoever can set that variable can already run the hook's code. The parts that did come from outside (session id, skill name) are fixed above. |
| `python/reDOS` | `skill_guard.py`, `verify_guard.py`, both copies | not-vulnerable | The expressions come from tracked configuration (`skill-map.json`, `verify-rules.json`), not from input; the input is the developer's own command. The one expression that really was super-linear is fixed above, and a test now bounds the cost of all of them. |
| `java/Sqli/test` | `OperatorErasureTest`, `PrivacyCoverageTest`, `PrivacyDormancyErasureTest` | not-vulnerable | The "input" is a table name read from `information_schema` of the throwaway test database. A name cannot be a bind parameter; `UserOwnedRows` validates and quotes it, and the user id is bound. Test code only. |
| `java/HardcodedPassword/test`, `java/NoHardcodedCredentials/test` | `PrudentRowLevelSecurityTest` | not-vulnerable | The test gives the `zen_runtime` role a login with this password in the Dev Services database, to prove row-level security from a non-owner connection, and takes it away again (`NOLOGIN PASSWORD NULL`) afterwards. The migration creates that role without a login or a password; production's is provisioned out of band, so this value protects nothing real. |
| `java/NonCryptoHardcodedSecret/test` | `SupabaseKeysTest` | not-vulnerable | Fake strings in the shape of a key (`sb_publishable_abc`), the input of a unit test of the key-format check itself. |

Each ignore expires after one year, so the reasoning is re-read rather than inherited.

## Re-checking

```bash
snyk code test --remote-repo-url=https://github.com/jlogicsoftware/prudent
```

Expected: only the findings above, all ignored. Anything else is new and needs the same trace.
