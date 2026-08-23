---
name: long-job
description: Run a build, test suite or native compile that takes minutes without burning turns waiting on it. Use whenever starting `task test`, `task test:native`, `task build:server:native`, `./mvnw test`, `flutter build`, `supabase start`, or any command that has ever taken more than about 30 seconds. Encodes the measured durations for this repo and the rule that foreground `sleep` is never how you wait.
---

# Waiting on a long job

**Never poll with a foreground `sleep`.** Across 103 sessions in this repo and its
siblings, `sleep` was called 350 times for a total of 9,434 seconds — over two and a
half hours of billed wall clock spent doing nothing — and at least eight of those calls
exceeded the Bash timeout and returned an error, costing a further retry. The pattern
`sleep 240; tail -50 log` is the single most expensive habit in the transcripts, closely
followed by `echo waiting` issued 27 times in one session to keep a turn alive.

## The rule

1. **Start it in the background.** Pass `run_in_background: true` to Bash. The harness
   re-invokes you when the command exits — you do not have to watch for it, and its
   output does not sit in your context while it runs.
2. **Do other work while it runs.** Anything that does not depend on the result:
   read the next file, draft the change, prepare the follow-up command.
3. **If you must block on a condition**, use `Monitor` with an until-condition rather
   than a sleep loop. A condition is "the port is listening", "the log line appeared",
   "the revision is serving" — not "some time has passed".
4. **Only for state the harness cannot see** — a Cloud Run rollout, a GitHub Actions
   run, a Cloud Scheduler tick — pick a single interval matched to the job's real
   duration from the table below. One 480-second check beats eight 60-second ones.

## Measured durations in this repo

From 103 sessions of transcripts. p90 is the number to plan against; the max column is
why you do not put a fixed `sleep` in front of any of them.

| Command | p50 | p90 | max |
|---|---|---|---|
| `flutter build` | 6s | 24s | 48s |
| `task test:e2e` | 11s | 37s | 37s |
| `supabase start` | 25s | 37s | 37s |
| `task build` | 8s | 24s | 24s |
| `./mvnw test` | 11s | 19s | 23s |
| `task test:native` | — | — | native compile + Docker smoke; minutes |

Prudent's suites are currently the fastest of the three repos, so the temptation to
foreground them is strongest here. `task test:native` is the exception and the one that
matters: it builds a native image and smokes it in Docker against a throwaway Postgres.
Background it.

The low p50s are not a contradiction: they are the runs that failed fast or were
already warm. Plan for p90, and never assume the max cannot happen — `task test` really
did take twenty minutes once.

## What this looks like

```
# right: start it, keep working, get re-invoked on exit
Bash(command="task test", run_in_background=true)
… do the next piece of work …

# wrong: every one of these appears in the transcripts
sleep 240; tail -50 /tmp/test.log     # times out, and blocks the turn
echo waiting                          # 27 times in one session
./mvnw -q -o test 2>&1 | tail -150    # re-run identically 25 times
```

## Do not re-run to check on it

A background job's result arrives once; re-running the command does not make it arrive
sooner, it starts a second job competing for the same Docker daemon and Dev Services
containers. In a sibling repo the same command was re-issued identically 25 times in a
single session.

If a background job seems stuck, read its output file — the task notification names it —
rather than starting the command again.
