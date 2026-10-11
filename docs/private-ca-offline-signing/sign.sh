#!/bin/sh
# Sign the intermediate CSR with the offline root held on the secure USB stick.
#
#   ./sign.sh [/path/to/stick] [passphrase-file]      (default: /mnt/stick)
#
# Uses --template, never --profile: a profile rebuilds the certificate from its own
# defaults and silently drops the SANs, producing an intermediate that passes an
# issuer check and then fails every TLS request (measured 2026-10-11).
set -eu

STICK="${1:-/mnt/stick}"
PWFILE="${2:-}"
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/intermediate_ca.crt"
TMP="$OUT.new"

# never leave a half-written certificate behind for someone to carry home
trap 'rm -f "$TMP"' EXIT

# --- the signing machine must not have a network -----------------------------
if command -v ip >/dev/null 2>&1 && ip route 2>/dev/null | grep -q '^default'; then
    echo "ABORT: this machine has a default route — it is not air-gapped." >&2
    echo "       The root key must never be used on a networked machine." >&2
    exit 1
fi

# --- inputs ------------------------------------------------------------------
if [ ! -x "$DIR/step" ]; then
    echo "ABORT: $DIR/step is missing or not executable." >&2
    echo "       If the file is present, you are most likely running this from a" >&2
    echo "       FAT/exFAT USB stick — those filesystems have no executable bit, so" >&2
    echo "       'chmod +x' does nothing there. Copy the bundle to a real filesystem:" >&2
    echo "         cp -r $DIR /tmp/bundle && cd /tmp/bundle && chmod +x step root.sh sign.sh" >&2
    exit 1
fi
[ -f "$DIR/intermediate_ca.csr" ]  || { echo "ABORT: $DIR/intermediate_ca.csr is missing" >&2; exit 1; }
[ -f "$DIR/intermediate-ca.tpl" ]  || { echo "ABORT: $DIR/intermediate-ca.tpl is missing" >&2; exit 1; }
[ -f "$STICK/root_ca.crt" ]      || { echo "ABORT: $STICK/root_ca.crt not found (is the stick mounted?)" >&2; exit 1; }
[ -f "$STICK/root_ca_key" ]      || { echo "ABORT: $STICK/root_ca_key not found (is the stick mounted?)" >&2; exit 1; }

cd "$DIR"

echo "Signing intermediate_ca.csr with the root on $STICK"
if [ -n "$PWFILE" ]; then
    [ -r "$PWFILE" ] || { echo "ABORT: passphrase file $PWFILE is not readable" >&2; exit 1; }
    echo "(using the root key passphrase in $PWFILE)"
    echo
    "$DIR/step" certificate sign --template intermediate-ca.tpl --not-after 8760h \
        --password-file "$PWFILE" \
        intermediate_ca.csr "$STICK/root_ca.crt" "$STICK/root_ca_key" \
        > "$TMP"
else
    echo "(the root key's passphrase will be requested now)"
    echo
    "$DIR/step" certificate sign --template intermediate-ca.tpl --not-after 8760h \
        intermediate_ca.csr "$STICK/root_ca.crt" "$STICK/root_ca_key" \
        > "$TMP"
fi

mv "$TMP" "$OUT"
echo "Signed -> $OUT"

# --- machine checks: does this certificate actually work? --------------------
echo
echo "Checking the result. Every line must read OK."
FAILED=0

if VERIFY_ERR="$("$DIR/step" certificate verify "$OUT" --roots "$STICK/root_ca.crt" 2>&1)"; then
    echo "  OK    chains to the root on the stick"
else
    echo "  FAIL  does NOT chain to the root on the stick" >&2
    printf '%s\n' "$VERIFY_ERR" >&2
    FAILED=1
fi

I="$("$DIR/step" certificate inspect --format json "$OUT")"

chk() {
    if printf '%s\n' "$I" | grep -Eq "$2"; then
        echo "  OK    $1"
    else
        echo "  FAIL  $1" >&2
        FAILED=1
    fi
}

chk "is a CA certificate"                      '"is_ca"[: ]+true'
chk "path length 0 (issues leaves, no deeper)"  '"max_path_len"[: ]+0'
chk "key usage: certificate sign"              '"certificate_sign"[: ]+true'
chk "key usage: CRL sign"                      '"crl_sign"[: ]+true'
chk "SAN exists (a missing SAN breaks TLS)"    '"dns_names"'
chk "SAN contains ca.internal"                 'ca\.internal'
chk "SAN contains 192.168.2.215"               '192\.168\.2\.215'
chk "validity is 1 year"                       '"length"[: ]+31536000'

if [ "$FAILED" -ne 0 ]; then
    echo >&2
    echo "STOP: this certificate is not fit to install. Nothing has been trusted" >&2
    echo "      yet — the root is untouched, and signing the same CSR again is" >&2
    echo "      safe. Do not carry $OUT back." >&2
    exit 1
fi

# --- human-readable view ----------------------------------------------------
echo
echo "=============================================================="
echo "Read the dump below as well. It must show:"
echo "  Issuer                   = CN=Homelab Internal CA (the root)"
echo "  Subject                  = CN=Homelab Intermediate CA"
echo "  Validity                 = ~1 year"
echo "  Basic Constraints        = critical  CA:TRUE, pathlen:0"
echo "  Key Usage                = critical  Digital Signature, Certificate Sign, CRL Sign"
echo "  Subject Alternative Name = DNS:ca.internal / IP Address:192.168.2.215"
echo "=============================================================="
echo
"$DIR/step" certificate inspect "$OUT"
