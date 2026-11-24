#!/bin/sh
# Runs a command with the variables of an env file in its environment (ADR-131):
#
#   scripts/with_env_file.sh deploy/persistent.env task deploy:cloudrun
#
# A variable that is already set in the caller's shell is NOT overwritten, so an operator can
# override one value for one run, and a throwaway environment can be deployed from the same file by
# exporting its own values over it.
#
# The file is data, never code: only `KEY=value` lines and `#` comments are accepted, the value is
# taken literally (no expansion, no quotes stripped), and anything else is refused by line number,
# because a deploy that half-read its configuration targets the wrong environment.
#
# Secrets are refused by name and by shape. The file is committed; a key that looks like a secret
# (SECRET, PASSWORD, TOKEN, PRIVATE, or the DB_ and APP_DB_ credentials) or a value that begins
# `sb_secret_` stops the run before anything is built or deployed.
set -eu

if [ "$#" -lt 2 ]; then
  echo "usage: with_env_file.sh ENV_FILE COMMAND [ARGS...]" >&2
  exit 64
fi
file=$1
shift
if [ ! -f "$file" ]; then
  echo "with_env_file: $file does not exist" >&2
  exit 66
fi

n=0
while IFS= read -r line || [ -n "$line" ]; do
  n=$((n + 1))
  case $line in
    '' | '#'*) continue ;;
  esac
  case $line in
    *=*) ;;
    *) echo "with_env_file: $file:$n is not KEY=value" >&2; exit 65 ;;
  esac
  key=${line%%=*}
  value=${line#*=}
  case $key in
    '' | [!A-Z_]* | *[!A-Z0-9_]*)
      echo "with_env_file: $file:$n has an invalid name (upper-case letters, digits and _ only)" >&2
      exit 65
      ;;
  esac
  case $key in
    *SECRET* | *PASSWORD* | *TOKEN* | *PRIVATE* | DB_* | APP_DB_*)
      echo "with_env_file: $file:$n names $key, which looks like a secret; secrets live in Secret Manager, never here" >&2
      exit 65
      ;;
  esac
  case $value in
    sb_secret_*)
      echo "with_env_file: $file:$n holds an sb_secret_ key for $key; a secret key never goes in a committed file" >&2
      exit 65
      ;;
  esac
  # $key is validated above, so this eval can only test the name.
  if eval "[ -z \"\${$key+x}\" ]"; then
    export "$key=$value"
  fi
done <"$file"

exec "$@"
