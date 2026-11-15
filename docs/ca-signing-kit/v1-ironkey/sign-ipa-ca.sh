#!/bin/sh
# sign-ipa-ca.sh <stick-mount> [passphrase-file]
set -eu

STICK="$1"
PWFILE="${2:-}"
DIR="$(cd "$(dirname "$0")" && pwd)"
SHARED="$DIR"
[ -x "$DIR/step" ] || SHARED="$(cd "$DIR/.." && pwd)"
PATH="$SHARED:$PATH"
export PATH

CSR="$DIR/ipa.csr"
[ -f "$CSR" ] || CSR="$SHARED/ipa.csr"
OUT="$(cd "$(dirname "$CSR")" && pwd)/ipa-ca.crt"
TMP="$OUT.new"
trap '[ -n "$TMP" ] && rm -f "$TMP"' EXIT

"$SHARED/step" certificate sign --template "$SHARED/ipa-ca.tpl" --not-after 8760h \
    ${PWFILE:+--password-file "$PWFILE"} \
    "$CSR" "$STICK/root_ca.crt" "$STICK/root_ca_key" > "$TMP"

"$SHARED/step" certificate verify "$TMP" --roots "$STICK/root_ca.crt" >/dev/null
"$SHARED/step" certificate inspect --format json "$TMP" | grep -Eq '"is_ca"[: ]+true' \
    || { echo "FAIL: not a CA" >&2; exit 1; }

mv "$TMP" "$OUT"
"$SHARED/step" certificate inspect "$OUT"
