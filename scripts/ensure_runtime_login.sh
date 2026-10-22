#!/bin/sh
# Gives the least-privilege runtime role, zen_runtime, a login and the password the service will
# present — between the migration and the first revision that serves.
#
# WHY THIS EXISTS. zen-identity's migration creates zen_runtime NOLOGIN with no password, on
# purpose: a credential in a migration is plaintext in git. Nothing else ever gives it one, and the
# service connects as it (APP_DB_USERNAME), so without this step the first revision of any new
# environment dies at startup with `FATAL: (EAUTHQUERY) user not found in the database` — which
# reads like a wrong username. It was found by the first real deploy (ADR-065, #45); no local gate
# could see it because test:native served as the DDL role. Both `task deploy:cloudrun` and
# `task test:native` run this script, so the step a deploy depends on is the step a gate exercises.
#
# IT IS IDEMPOTENT, and re-running it is a feature: it sets the role's password to what the secret
# holds now, so rotating APP_DB_PASSWORD and deploying again takes effect instead of leaving the
# role and the secret quietly disagreeing.
#
# Inputs are environment variables, never arguments, so a password never lands in a process list:
#   DB_URL            jdbc:postgresql://HOST:PORT/DB — the DDL role's URL. A session-mode pooler or a
#                     direct connection; a transaction-mode pooler was not tried.
#   DB_USERNAME       the DDL role (it owns zen_runtime, so it may alter it)
#   DB_PASSWORD       its password
#   APP_DB_PASSWORD   the password to give zen_runtime
# Optional:
#   PSQL_IMAGE        the client image (default postgres:17-alpine; needs psql 15+ for \getenv)
#   PSQL_DOCKER_ARGS  extra `docker run` arguments, e.g. --network NAME to reach a container
#
# psql runs in Docker because a deploy already needs Docker and a laptop does not reliably have a
# psql. ALTER ROLE ... PASSWORD is, as anywhere, logged in the clear if the server logs DDL.
set -eu

: "${DB_URL:?DB_URL is required}"
: "${DB_USERNAME:?DB_USERNAME is required}"
: "${DB_PASSWORD:?DB_PASSWORD is required}"
: "${APP_DB_PASSWORD:?APP_DB_PASSWORD is required}"

case "$DB_URL" in
  jdbc:postgresql://*) ;;
  *) echo "DB_URL must be a jdbc:postgresql:// URL (got a different scheme)." >&2; exit 1 ;;
esac

conn="postgresql://${DB_USERNAME}@${DB_URL#jdbc:postgresql://}"

# $PSQL_DOCKER_ARGS is split on purpose: it is a list of docker flags.
# shellcheck disable=SC2086
if ! PGPASSWORD="$DB_PASSWORD" APP_PW="$APP_DB_PASSWORD" \
     docker run --rm -i ${PSQL_DOCKER_ARGS:-} -e PGPASSWORD -e APP_PW \
       "${PSQL_IMAGE:-postgres:17-alpine}" psql -v ON_ERROR_STOP=1 -q "$conn" >/dev/null <<'SQL'
\getenv app_pw APP_PW
ALTER ROLE zen_runtime WITH LOGIN PASSWORD :'app_pw';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'zen_runtime' AND rolcanlogin) THEN
    RAISE EXCEPTION 'zen_runtime still cannot log in';
  END IF;
END
$$;
SQL
then
  echo "Could not give zen_runtime a login. Either the connection failed (check DB_URL, the DDL" >&2
  echo "credentials, and that the pooler is in session mode), or the role does not exist — which" >&2
  echo "means the migration job has not run to completion against this database." >&2
  exit 1
fi

echo "zen_runtime has a login."
