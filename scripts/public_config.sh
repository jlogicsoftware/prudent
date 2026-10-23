#!/bin/sh
# The public configuration `deploy:cloudrun` hands Cloud Run as plain environment variables
# (jlogicsoftware/prudent#166), checked and derived in one place so it can be proved without a
# deploy. SOURCE it (`. scripts/public_config.sh`); it does not print anything on success.
#
# WHY THESE ARE NOT SECRETS. SUPABASE_URL, SITE_URL, CORS_ORIGINS, AUTH_REDIRECT_URI and
# AUTH_REDIRECT_URIS are public by construction: the origin is in the app's own bundle, the
# redirect addresses are in the app and in the identity provider's allowlist. Storing them in
# Secret Manager implied a confidentiality they do not have, was billed per version per month, and
# made the real secrets harder to pick out.
#
# Inputs, from the operator's shell like WEB_API_URL (never committed, ADR-021):
#   WEB_API_URL          the origin the web bundle is compiled to call
#   SUPABASE_URL         https://REF.supabase.co
#   AUTH_REDIRECT_URIS   comma-separated native return addresses, e.g. the app's custom scheme.
#                        Empty means no native client can sign in and nothing else notices, so
#                        it is required rather than defaulted.
#   SMTP_HOST            the mail relay's host name, for the dormancy warnings (ADR-072). Required:
#                        a service without a sender boots, looks healthy, and can never warn anyone,
#                        so no dormant account is ever erased.
#   SMTP_FROM            the sender address those warnings come from. Required, for the same reason.
#   SMTP_PORT            optional, 587 when unset. The service speaks STARTTLS, which is the
#                        submission port's mode; 465 (implicit TLS) is not what it is configured for.
# The relay's login (SMTP_USERNAME, SMTP_PASSWORD) is NOT here: those two are secrets.
# Derived, so they cannot disagree with the bundle's origin:
#   SITE_URL             = WEB_API_URL
#   CORS_ORIGINS         = WEB_API_URL
#   AUTH_REDIRECT_URI    = WEB_API_URL/auth/callback
# Exporting one of the derived three to anything else is refused: a value that silently lost to
# the derivation would be a configuration nobody chose.
#
# On any problem it prints what is wrong to stderr and EXITS the shell that sourced it.

_pc_missing=0
for _pc_v in WEB_API_URL SUPABASE_URL AUTH_REDIRECT_URIS SMTP_HOST SMTP_FROM; do
  eval "_pc_val=\${$_pc_v:-}"
  if [ -z "${_pc_val}" ]; then
    echo "MISSING: ${_pc_v}" >&2
    _pc_missing=1
  fi
done
if [ "${_pc_missing}" -ne 0 ]; then
  echo >&2
  echo "These are public configuration: exported and passed to Cloud Run as plain values," >&2
  echo "not created in Secret Manager (#166, ADR-072). See 'task deploy:cloudrun --summary'." >&2
  exit 1
fi

# gcloud splits a --set-env-vars value on commas, so a comma inside a single-valued variable would
# turn one setting into two; AUTH_REDIRECT_URIS is the one list, passed with its own delimiter
# (`^@^`), so an `@` inside it would split it wrongly. Whitespace is never part of a URL.
for _pc_v in WEB_API_URL SUPABASE_URL; do
  eval "_pc_val=\${$_pc_v}"
  case "${_pc_val}" in
    *,* | *[[:space:]]* | *@*)
      echo "${_pc_v} must be a plain URL (no comma, whitespace or @): ${_pc_val}" >&2
      exit 1 ;;
  esac
done
case "${AUTH_REDIRECT_URIS}" in
  *@* | *[[:space:]]* | *, | ,*)
    echo "AUTH_REDIRECT_URIS must not contain @ or whitespace, or start or end with a comma:" >&2
    echo "${AUTH_REDIRECT_URIS}" >&2
    exit 1 ;;
esac

# The mail settings. SMTP_HOST is a bare host name: a scheme or a port in it is the usual mistake
# and Quarkus would try to resolve the whole string. SMTP_FROM is one address: gcloud splits a
# --set-env-vars value on commas, and a display-name form ("Name <a@b>") is not what the mailer's
# `from` takes as a plain value here.
case "${SMTP_HOST}" in
  *[!A-Za-z0-9.-]* | -* | .* | *.)
    echo "SMTP_HOST must be a bare host name (no scheme, port, path or whitespace): ${SMTP_HOST}" >&2
    exit 1 ;;
esac
case "${SMTP_FROM}" in
  *[[:space:],\<\>\"]* | @* | *@ | *@*@* | *@*[!A-Za-z0-9.-]* | *@.* | *@-*)
    echo "SMTP_FROM must be one plain address, local@host: ${SMTP_FROM}" >&2
    exit 1 ;;
  *@*.*) ;;
  *) echo "SMTP_FROM must be one plain address, local@host: ${SMTP_FROM}" >&2
     exit 1 ;;
esac
SMTP_PORT="${SMTP_PORT:-587}"
case "${SMTP_PORT}" in
  '' | *[!0-9]* | 0*)
    echo "SMTP_PORT must be a port number, got: ${SMTP_PORT}" >&2
    exit 1 ;;
esac
if [ "${#SMTP_PORT}" -gt 5 ] || [ "${SMTP_PORT}" -gt 65535 ]; then
  echo "SMTP_PORT must be a port number, got: ${SMTP_PORT}" >&2
  exit 1
fi

case "${SUPABASE_URL}" in
  https://?*) ;;
  *) echo "SUPABASE_URL must be an https:// URL, got: ${SUPABASE_URL}" >&2; exit 1 ;;
esac

# Every entry needs a scheme. A bare word here is accepted by gcloud and by Quarkus and rejected
# only when a client tries to sign in.
_pc_rest="${AUTH_REDIRECT_URIS}"
while [ -n "${_pc_rest}" ]; do
  _pc_entry="${_pc_rest%%,*}"
  case "${_pc_rest}" in *,*) _pc_rest="${_pc_rest#*,}" ;; *) _pc_rest="" ;; esac
  case "${_pc_entry}" in
    ?*://?*) ;;
    *) echo "AUTH_REDIRECT_URIS has an entry without a scheme and a target: '${_pc_entry}'" >&2
       exit 1 ;;
  esac
done

_pc_origin="${WEB_API_URL%/}"
for _pc_pair in "SITE_URL=${_pc_origin}" "CORS_ORIGINS=${_pc_origin}" \
                "AUTH_REDIRECT_URI=${_pc_origin}/auth/callback"; do
  _pc_name="${_pc_pair%%=*}"
  _pc_want="${_pc_pair#*=}"
  eval "_pc_have=\${$_pc_name:-}"
  if [ -n "${_pc_have}" ] && [ "${_pc_have}" != "${_pc_want}" ]; then
    echo "${_pc_name} is set to ${_pc_have}, but it is derived from WEB_API_URL and must be" >&2
    echo "${_pc_want}. Unset it; the bundle is served same-origin by the service, so there is" >&2
    echo "nothing for it to disagree with." >&2
    exit 1
  fi
done

SITE_URL="${_pc_origin}"
CORS_ORIGINS="${_pc_origin}"
AUTH_REDIRECT_URI="${_pc_origin}/auth/callback"
export SITE_URL CORS_ORIGINS AUTH_REDIRECT_URI SMTP_PORT
