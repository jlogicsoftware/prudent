#!/bin/sh
# Proves that an origin ANSWERS AS PRUDENT, and fails loudly if it does not.
#
#   sh scripts/check_origin_serves.sh ORIGIN        e.g. https://HOST (no path)
#
# WHY THIS EXISTS. The web bundle is compiled against one origin (WEB_API_URL) before the service
# exists, and every API call it makes goes there. Cloud Run answers a service at more than one
# host, and the one printed by `status.url` is not the one the bundle was built for. A bundle
# built for a host that never serves is otherwise found only by a user, and a bundle opened from
# the other host calls the API cross-site, so by ADR-020's reasoning the SameSite=Lax session
# cookie it depends on is not sent (expected, not yet observed in a browser). Neither state fails
# any status-code check against the host you happened to test (#151, found while proving the
# deploy path in #45 / ADR-065).
#
# WHAT COUNTS AS "ANSWERS". HTTP 200 from /api/v1/health AND a body naming `prudent-server`. A
# 200 alone is not enough: a different service (or a placeholder page) on a reused host also
# answers 200, and that is exactly the host a stale WEB_API_URL points at after a teardown.
#
# Optional environment:
#   ORIGIN_ATTEMPTS        tries before giving up (default 6). A service scaled to zero needs a
#                          cold start, and a fresh revision can take a moment to take traffic.
#   ORIGIN_RETRY_SECONDS   pause between tries (default 5)
#
# Exit 0 when it answers as Prudent; exit 1 otherwise, with the reason on stdout. Nothing here is
# tolerated: a failure that cannot be told from a pass is the defect this script exists to remove.
set -eu

origin="${1:-}"
if [ -z "${origin}" ]; then
  echo "usage: check_origin_serves.sh ORIGIN" >&2
  exit 1
fi
case "${origin}" in
  http://*|https://*) ;;
  *) echo "FAIL  origin must start with http:// or https:// (got '${origin}')"; exit 1 ;;
esac
# A trailing slash would turn the probe into //api/v1/health.
origin="${origin%/}"

attempts="${ORIGIN_ATTEMPTS:-6}"
pause="${ORIGIN_RETRY_SECONDS:-5}"

body=$(mktemp)
trap 'rm -f "${body}" "${body}.err"' EXIT

reason=""
i=1
while [ "${i}" -le "${attempts}" ]; do
  : >"${body}"
  # curl exiting non-zero (DNS failure, refused, TLS, timeout) is a finding, not an accident to
  # swallow: it is captured and reported. Redirects are NOT followed — a redirect to another host
  # is itself the answer to "does THIS origin serve".
  if code=$(curl -sS --max-time 20 -o "${body}" -w '%{http_code}' \
              -H 'X-Zen-Transport: json' "${origin}/api/v1/health" 2>"${body}.err"); then
    if [ "${code}" = "200" ]; then
      if grep -q 'prudent-server' "${body}"; then
        echo "  ok    ${origin} answers as prudent-server"
        rm -f "${body}.err"
        exit 0
      fi
      reason="HTTP 200, but the body does not name prudent-server — something else answers there"
    else
      reason="HTTP ${code} from ${origin}/api/v1/health"
    fi
  else
    reason="no HTTP answer: $(tr '\n' ' ' <"${body}.err")"
  fi
  rm -f "${body}.err"
  if [ "${i}" -lt "${attempts}" ]; then
    sleep "${pause}"
  fi
  i=$((i + 1))
done

echo "  FAIL  ${origin} does not answer as Prudent after ${attempts} tries: ${reason}"
echo "        The web bundle calls this origin for every API request. If it never serves, the"
echo "        app is broken for every user. Rebuild with WEB_API_URL set to a host that does."
exit 1
