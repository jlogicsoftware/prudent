#!/usr/bin/env python3
"""Compare, or bring, the hosted Supabase project's sign-up and recovery mail to the repository's.
Run by `task verify:mail-templates:hosted` (check) and `task deploy:mail-templates` (apply).

A hosted project does not read `supabase/config.toml`, so the templates in `supabase/templates/`
reach it only when somebody sends them, and nothing else notices when the two differ (the sibling
product `bugeater-quarkus` records exactly that: "nothing checks it"). The Management API's
`config/auth` endpoint carries the subject and body of each mail, so this reads them back.

  check   GET the project's auth config and fail, naming each field, when a subject or a body is not
          the repository's. Changes nothing.
  apply   PATCH the repository's subjects and bodies, then GET again and run the same comparison. A
          PATCH the API accepted but did not keep is a failure, not a success.

The same files the offline gate checks (`scripts/verify_mail_templates.py`) are the source: the
subject and `content_path` of every `[auth.email.template.*]` in `supabase/config.toml`. Only
`confirmation` and `recovery` are sent; adding another type means adding it to `FIELDS` here and
reading the API reference first.

Needs, from the environment (never written into the repository, ADR-021):
  SUPABASE_ACCESS_TOKEN   a personal access token, minted for the session and revoked afterwards
  SUPABASE_PROJECT_REF    the hosted project's reference
Either missing is exit 2 with the name of the variable, not a skipped check. `SUPABASE_API_URL`
overrides the public API host (the tests point it at a local stub).

Usage: hosted_mail_templates.py check|apply [REPO_ROOT]
Exit: 0 in sync (and, for apply, written); 1 differs or the API refused; 2 not configured.
Stdlib only, 3.9 floor.
"""
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify_mail_templates import CONFIG, sections  # noqa: E402  (the one parser of config.toml)

DEFAULT_API = "https://api.supabase.com"
# Mail type -> the two Management API fields that carry it. Names read from the API's published
# OpenAPI document (UpdateAuthConfigBody), 2026-10-30.
FIELDS = {
    "confirmation": ("mailer_subjects_confirmation", "mailer_templates_confirmation_content"),
    "recovery": ("mailer_subjects_recovery", "mailer_templates_recovery_content"),
}


def wanted(root: Path) -> dict:
    """`{api field: value}` the repository says the project should hold."""
    config = sections((root / CONFIG).read_text())
    out = {}
    for name, (subject_field, body_field) in FIELDS.items():
        if name not in config:
            raise SystemExit(f"{CONFIG} wires no [auth.email.template.{name}]")
        keys = config[name]
        out[subject_field] = keys["subject"]
        out[body_field] = (root / keys["content_path"]).read_text()
    return out


def call(method: str, url: str, token: str, body=None) -> dict:
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {token}", "Content-Type": "application/json", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as e:
        # Never print the response body: it can echo the project's configuration.
        raise SystemExit(f"FAIL  {method} {url.split('/v1/')[-1]} answered {e.code}"
                         + (" — the token is wrong or expired" if e.code in (401, 403) else ""))
    except urllib.error.URLError as e:
        raise SystemExit(f"FAIL  {method} {url} did not answer: {e.reason}")


def differences(want: dict, have: dict) -> list:
    out = []
    for field, value in want.items():
        if field not in have or have[field] is None:
            out.append(f"{field}: the project has no value (the API did not return it)")
        elif have[field].strip() != value.strip():
            out.append(f"{field}: the project's value differs from the repository's")
    return out


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in ("check", "apply"):
        print("Usage: hosted_mail_templates.py check|apply [REPO_ROOT]")
        return 2
    mode = sys.argv[1]
    root = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).resolve().parent.parent
    token, ref = os.environ.get("SUPABASE_ACCESS_TOKEN"), os.environ.get("SUPABASE_PROJECT_REF")
    for name, value in (("SUPABASE_ACCESS_TOKEN", token), ("SUPABASE_PROJECT_REF", ref)):
        if not value:
            print(f"FAIL  {name} is not set; the hosted project cannot be compared without it")
            return 2
    url = f"{os.environ.get('SUPABASE_API_URL', DEFAULT_API).rstrip('/')}/v1/projects/{ref}/config/auth"

    want = wanted(root)
    if mode == "apply":
        call("PATCH", url, token, want)
    drift = differences(want, call("GET", url, token))
    for line in drift:
        print(f"FAIL  {line}")
    if drift:
        print("      Apply with `task deploy:mail-templates`; see docs/persistent-environment.md section 3.")
        return 1
    print(f"ok    {len(FIELDS)} templates and subjects on the hosted project match supabase/templates/"
          + (" (written, then read back)" if mode == "apply" else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
