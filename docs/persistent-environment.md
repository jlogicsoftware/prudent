# The persistent environment — a proof of concept, and what is different about it

**Status (2026-10-22): decided, prepared, not created.** No persistent GCP project, Cloud Run
service or Supabase project exists. The owner's decisions are recorded in ADR-068; this document is
what to do with them and what to watch for. It keeps **what is proven, what is only documented by
the provider, and what nobody has tried** apart.

It holds **no environment fact** — no project id or number, region, service name, URL, domain or
Supabase reference — and no credential, now or ever (ADR-021). Everything below is a placeholder:
`PROJECT`, `PROJECT_NUMBER`, `REGION`, `SUPABASE_REGION`, `SERVICE_NAME`, `REF`,
`BILLING_ACCOUNT_ID`, `DOMAIN`, `HOST`. The real values live in the owner's password manager and in
the cloud itself.

The deploy path is not repeated here. `task deploy:cloudrun --summary` is the runbook (steps 1a-4)
and ADR-065, ADR-066 and ADR-067 record what three real, disposable runs taught. This document
covers only the **deltas**: and where it and the runbook disagree, the runbook is right.

## 1. What this environment is

A **proof of concept the owner uses from a phone's browser**. It holds test data. That is the
condition that makes the decisions in ADR-068 acceptable, and it is stated here so nobody has to
rediscover it:

> **Do not enter real finances.** The database has no backup, the project can pause, and one
> deletion loses everything (section 4). Before real money goes in, the backup mechanism (#47) has to
> exist and a restore has to have been done once.

| | Decision (ADR-068) | What it costs |
|---|---|---|
| Supabase plan | **Free**; no backups, risk accepted | Section 4 |
| Region | One European region near the owner, the same continent for GCP and Supabase, chosen once | Not recorded here (ADR-021); changing it later changes the origin (section 5) |
| Owners | **One** Owner; no second Owner, no lien required | A lost or locked account is a lost environment |
| Address | A subdomain of a domain the owner already holds (DNS at Cloudflare) is **tried**; the deterministic `*.run.app` host is the fallback | Section 5 |
| Project id | The bare name is almost certainly taken; the id carries an owner-specific suffix | The id is permanent and not recorded here |
| Sign-in mail | Supabase's default sender | Section 3 |
| Recovery copies | None | Consistent with no backups |
| Native iPhone build | A separate issue, #155 | The phone uses the web app first |

## 2. Systems, and who holds each

One person holds everything, which is the POC's choice rather than a recommendation.

| System | What is held there | Held by |
|---|---|---|
| The Google account that owns the GCP project | Everything in GCP; `roles/owner` | The owner |
| The billing account | The bill; a closed or unpaid account suspends Cloud Run | The owner's organisation's account, chosen at creation |
| The Supabase organisation | The database, GoTrue (sign-in), the project's keys | The owner; the account that is the organisation's member is also the only address the default mail sender will deliver to |
| The Supabase personal access token | Management-API calls (pooler `db_host`, project deletion) | Whoever provisions: minted per session, revoked afterwards, never stored in Secret Manager or Git |
| The domain's DNS (Cloudflare) | The `HOST` record and the ownership-verification record | The owner |
| The deployer's machine | `gcloud` login, Docker, the working copy | Whoever deploys; nothing is kept only there |

**If a second Owner is ever added:** the project has no Google organisation, so granting
`roles/owner` to another consumer account with `gcloud projects add-iam-policy-binding` may be
refused or require an emailed invitation; that was not tried. Try it on a disposable project before
relying on it.

**A reduced-privilege deploy account** (not needed while the owner deploys as Owner — and these roles
are *derived by reading what the tasks call, not proven*): Cloud Run Admin, Service Account User on
the runtime service account, Artifact Registry Writer, Cloud Scheduler Admin, Service Usage Admin for
the one-time API enablement, Secret Manager Admin for the one-time creation, **Secret Accessor on the
five secrets the tasks read** (`DB_URL`, `DB_USERNAME`, `DB_PASSWORD`, `APP_DB_PASSWORD` in
`deploy:cloudrun`; `SITE_URL` in `deploy:check-origin-config` and `verify:deploy`), and a role with
`resourcemanager.projects.get` (the pre-build check runs `gcloud projects describe`). To find out
which is wrong, re-run `task deploy:cloudrun` under that account.

The **runtime** service account holds `roles/secretmanager.secretAccessor` and nothing else (runbook
step 1f). It is granted on the project, so it can read every secret in it; that is acceptable only
because the project holds nothing but this application's secrets. Keep it that way.

## 3. Secrets and sign-in

The twelve secrets and how each is created are runbook step 2. What follows is only what the runbook
does not say.

| Secret | Rotation | Status |
|---|---|---|
| `DB_PASSWORD` | Reset in Supabase, **then** a new secret version, then a deploy | Never exercised |
| `APP_DB_PASSWORD` | A new secret version plus `task deploy:cloudrun`; the deploy applies it to the role (ADR-066) | Proven on a throwaway Postgres, **not** against a live service |
| `ZEN_JOBS_TRIGGER_TOKEN` | New version, deploy, **then** update the scheduler header: `gcloud scheduler jobs update http prudent-jobs-tick --update-headers=...` | Flag exists in gcloud 587; never run |
| `SUPABASE_KEY` | Read again from the dashboard or Management API. How Supabase rotates it, and what that invalidates, was not tried | Unknown |
| The rest | Derived from `REF`, the host or fixed text; recreate rather than rotate | — |

`gcloud secrets create` accepts `--version-destroy-ttl="86400s"` (the format is in `--help`): a
destroyed version is then recoverable for a day. Cheap; not used by the proven runs.

**The Secret Manager copy of the database password is the only copy**, unless the owner keeps one.
For a POC Supabase can reset it, so losing it costs a reset, not the data.

**Known hygiene gaps, reported not fixed:** the scheduler header carries the trigger token on the
`gcloud` command line (ADR-065), and so does `supabase projects create --db-password`; both are
visible in the process list while they run. On a personal machine that is small. And the **running
service is handed `DB_USERNAME` and `DB_PASSWORD`** (the DDL role) as well as `APP_DB_*`, because
`%prod.quarkus.flyway.username/password` in `application.properties` have no default, so the service
cannot start without them even though it does not migrate at boot. The role `zen_runtime` exists so
the running service holds a role RLS applies to; handing it the DDL pair undoes that. Not a POC
blocker; a real-data blocker, tracked as #156.

**Sign-in.** Registering is how a user gets in, and Supabase sends the confirmation mail. Its
default sender delivers **only to members of the Supabase organisation, 2 messages an hour**, and is
not meant for production (Supabase's documentation). For one user who is the organisation's member
that works: register with that address. Before registering, in the Supabase dashboard set the **Site
URL** and the **Redirect URLs** to `SITE_URL`, `AUTH_REDIRECT_URI` and `AUTH_REDIRECT_URIS`: a
missing entry fails silently (GoTrue falls back to the Site URL and the mail opens the wrong
application), and **this list was never set in any run**, so no real sign-in link has ever been
followed. That is the first thing to try, and it is unproven.

## 4. Free plan: what it means in practice

- **No backups.** Free has none (Supabase's documentation tells you to export with `db dump`), and
  deleting a project deletes whatever backups exist. Accepted. This is why the table above says not
  to enter real finances.
- **It can pause.** Supabase pauses an idle Free project. The scheduler's hourly call reaches the
  service, which may touch the database and so may keep the project awake — **that was not
  measured**; do not rely on it. A paused project answers errors from the service until it is
  resumed in the dashboard. To notice: `supabase projects list` shows the status.
- **The slot.** The account already holds a Free project that is active and one that is paused (the
  limit is two *active*). The persistent project takes the second active slot, so the paused one must
  stay paused while it runs, or it will be refused or break the persistent one.
- **One mistake loses all of it.** `supabase projects delete` and runbook step 4 are the same
  command pointed at different things. Step 4 now says so. A project lien is a cheap guard
  (section 7) and is **not required** for the POC.

## 5. The address: a subdomain, tried; `*.run.app`, as the fallback

The deterministic `*.run.app` host is proven and needs nothing. A subdomain of a domain the owner
already holds is **not proven**, so this section is a plan to try and a fallback to return to.

What Google's documentation says (read 2026-10-22; Cloud Run "Mapping custom domains"):

- Cloud Run **domain mappings are Preview** — "not production-ready" and "not recommended for
  production services". Acceptable for a POC, and the reason this is a try.
- The chosen region must be one that supports them. The page lists a European one that matches the
  decision; **confirm the live region list before creating the project**, since a region change
  later changes the origin.
- The base domain must be **verified for the Google account** (`gcloud domains verify DOMAIN`, then
  completed in Search Console, which asks for a DNS record at the registrar/DNS host). That is the
  owner's interactive step; it cannot be scripted from here.
- Cloud Run generates the DNS records the subdomain needs; read them with
  `gcloud beta run domain-mappings describe --domain HOST` (`resourceRecords`). Google does not name a
  CNAME target in that page, so do not assume one.
- The certificate "usually takes about 15 minutes but can take up to 24 hours".
- A third-party CDN "might inadvertently intercept validation requests", and the page names a
  Cloudflare setting ("Always use https" off).

**On Cloudflare:** a record set to **DNS only** (grey cloud) returns the real answer and Cloudflare
does not route the HTTP traffic (Cloudflare's documentation). Use DNS only, for two reasons. Google
validates the mapping through DNS and warns about intercepting proxies. And jZen's rule is that
nothing sits between the client and Cloud Run — a proxy would change the forwarded-address count the
rate limiter trusts (`zen.ratelimit.forwarded-hops`, jZen ADR-053). **That DNS-only is what makes this
work was not tried.**

**The order that needs one native build** (the bundle is compiled against the origin, so the origin
must be fixed before the build):

1. Create the project and secrets with `SITE_URL`, `AUTH_REDIRECT_URI` and `CORS_ORIGINS` set to
   `https://HOST` (not the `run.app` form).
2. `WEB_API_URL=https://HOST` and `WEB_API_URL_ALLOW_OTHER=1`, then `task deploy:check-origin-config`
   (the `SITE_URL` equality still applies and has no override) and `task deploy:cloudrun`.
3. **Expect that first deploy to end "DEPLOY NOT ACCEPTED".** The service is up, but `HOST` does not
   resolve to it yet, so the origin probe fails. That is the designed failure, not a bug.
4. Create the mapping (`gcloud beta run domain-mappings create --service SERVICE_NAME --domain HOST
   --region REGION`), verify the base domain if not done, add the records Cloud Run prints at
   Cloudflare as **DNS only**, wait for the certificate.
5. `SERVICE_URL=https://HOST task verify:deploy` — the cheap re-probe the failure message offers.
   Green means the origin works with no rebuild.
6. Set the Supabase Site URL and Redirect URLs (section 3).

**If it does not work** within a reasonable wait (the certificate can take hours), do not debug
Cloudflare for an evening: the fallback is the proven path with `WEB_API_URL` the deterministic host,
which needs `SITE_URL` etc. changed and **a rebuild**. Decide by the end of the day; a POC is not
worth a week on DNS.

## 6. Failure and recovery — what is true, what is not

| Event | Recovery | Status |
|---|---|---|
| A bad revision | Redeploy a known-good commit (`task deploy:cloudrun` refuses a dirty tree), or `gcloud run services update-traffic --to-revisions=REVISION=100`. A rollback onto an older image can find the schema ahead of it: the migration job refuses (exit 2) | Refusal proven (`test:native`); traffic move not run |
| Service scaled to zero is slow | Expected (`--min-instances=0`). `check_origin_serves.sh` retries | Cold start not measured by Prudent |
| A secret lost or wrong | Section 3 | Mostly un-exercised |
| GCP project deleted | Restorable for 30 days (`gcloud projects undelete PROJECT`); the project number, and so the deterministic host, return with it | Holding window observed as `DELETE_REQUESTED` (ADR-065); undelete not run |
| The origin has to change | New `WEB_API_URL`, new `SITE_URL`/`AUTH_REDIRECT_URI`/`CORS_ORIGINS`, Supabase Site URL and Redirect URLs, **a rebuilt bundle** | `deploy:check-origin-config` and `deploy:accept-origin` catch a wrong host; a live migration of an origin was never done |
| Supabase project paused or deleted | Resume (paused); not recoverable (deleted) | Section 4 |

## 7. Protecting it from the throwaway teardown (optional for the POC)

Runbook step 4 (`gcloud projects delete`, `supabase projects delete`) is for an environment made to
be thrown away, and now says so. Prudent has no `destroy` task, so the risk is a person pasting
commands. If the owner wants a guard anyway:

- **A project lien** — `gcloud alpha resource-manager liens create --project=PROJECT
  --restrictions=resourcemanager.projects.delete --reason="..." --origin="prudent-persistent"`. The
  command is alpha-only: **install the component first** (`gcloud components install alpha`) or it
  stops on an interactive prompt. Google documents that a lien blocks deletion of the project; it
  does not say in so many words that `gcloud projects delete` is refused, and it protects against an
  accident, not against the Owner removing it. Test it once on a disposable project before trusting
  it. It does nothing for Supabase.
- **A label at creation** — `gcloud projects create ... --labels=prudent-environment=persistent`
  (`--labels` is on `projects create`; `projects update` has no labels flag in gcloud 587), so
  `gcloud projects describe` shows what it is before anyone runs step 4. It protects nothing.
- **A budget alert** — `gcloud billing budgets create` needs the Cloud Billing Budget API enabled
  first (`gcloud services enable billingbudgets.googleapis.com`), a `--budget-amount` with a currency,
  and a scope (`--filter-projects=projects/PROJECT_NUMBER`, whose exact form was not verified). Not
  tried.

## 8. Provisioning, as deltas to the runbook

`task deploy:cloudrun --summary` is the authority for steps 1a-3. Run from the **main checkout** (`task`
does not load from a git worktree, ADR-065). Stop on the first failure.

1. **Before anything:** the decisions are in ADR-068; the Supabase token is minted for this session;
   `~/.docker/config.json` is copied aside.
2. **Runbook 1a-1f**, with the project id carrying the owner's suffix, the display name saying it is
   persistent, and the label above. A new project answers `PERMISSION_DENIED` on the registry for a
   few minutes: wait, repeat.
3. **Generate the database password into Secret Manager first**, then create the Supabase project in
   `SUPABASE_REGION`, take the pooler `db_host` from the Management API, create the other eleven
   secrets (runbook step 2) with `SITE_URL` etc. set to the origin you will build against (section 5).
4. **Build and deploy** (section 5, steps 2-5, or the plain `run.app` route).
5. **Scheduler** (runbook step 3), then `task verify:deploy`.
6. **Supabase Site URL and Redirect URLs** (section 3), then **register one user from the phone's
   browser** with the organisation member's address, follow the mail, sign in, create and read back a
   record. Record what happened in an ADR. This is the part nothing has ever exercised.
7. **Clean up the machine only:** restore `~/.docker/config.json` if it changed; revoke the Supabase
   token; unset the exported variables. The environment stays.

## 9. Proven, documented, never done

**Proven**, by three real disposable runs (ADR-065, ADR-066, ADR-067): the deploy end to end; the
runtime login; the origin checks; `verify:deploy`; a Scheduler trigger answered with HTTP 200; the
corrected teardown.

**Documented by the provider, not tried here:** domain mappings and their region list; the
verification flow; Cloudflare's DNS-only meaning; liens; Supabase's backup policy and default mail
sender; `--version-destroy-ttl`.

**Never done:** any registration or sign-in against a deployed service from any device; a phone
reaching the service; the Supabase redirect list; a custom domain; a rotation on a live service; a
restore of anything; a lien; an undelete; a deployer without Owner.

## 10. Still open

- **The DDL pair in the running service** (section 3), #156: a change to `deploy:cloudrun` and an ADR,
  before real data.
- **A native iPhone build** against the deployed origin, #155. No task builds, signs or
  distributes one, and `prudent://auth-callback` works only with a native build installed.
- **Backups (#47)** are not provided by this environment and are not closed by it.
