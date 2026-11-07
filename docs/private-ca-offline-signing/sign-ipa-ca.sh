#!/bin/sh
# Sign FreeIPA's CA CSR with the offline root held on the secure USB stick.
#
#   ./sign-ipa-ca.sh <destination-path> [passphrase-file]   e.g. /mnt/sdX1 (no default)
#
# The CSR is produced on the IPA guest by `ipa-server-install --external-ca`.
# `--template` is used so the signer asserts the CA shape; the resulting
# certificate must chain to the fleet root and match the IPA CA subject.
set -eu

[ $# -ge 1 ] || { echo "usage: $0 <destination-path> [passphrase-file]" >&2; echo "       e.g. $0 /mnt/sdX1" >&2; exit 1; }
STICK="$1"
PWFILE="${2:-}"
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/ipa-ca.crt"
TMP="$OUT.new"

trap 'rm -f "$TMP"' EXIT

# --- the signing machine must not have a network -----------------------------
if ! command -v ip >/dev/null 2>&1; then
    echo "ABORT: 'ip' is not available, so this machine's network state cannot be checked." >&2
    exit 1
fi
NET="$(ip -o addr show 2>/dev/null | awk '{ n = $2; sub(/:$/, "", n); if (n != "lo") print "  " n " " $4 }')"
if [ -n "$NET" ]; then
    echo "ABORT: this machine has a non-loopback address:" >&2
    printf '%s\n' "$NET" >&2
    echo "       The root key must never be used on a networked machine." >&2
    exit 1
fi
if ip route 2>/dev/null | grep -q '^default'; then
    echo "ABORT: this machine has a default route — it is not air-gapped." >&2
    exit 1
fi

# --- inputs ------------------------------------------------------------------
if [ ! -x "$DIR/step" ]; then
    echo "ABORT: $DIR/step is missing or not executable." >&2
    echo "       Copy the bundle to a real filesystem if you are running it from the stick." >&2
    exit 1
fi
[ -f "$DIR/ipa.csr" ] || { echo "ABORT: $DIR/ipa.csr is missing" >&2; exit 1; }
[ -f "$DIR/ipa-ca.tpl" ] || { echo "ABORT: $DIR/ipa-ca.tpl is missing" >&2; exit 1; }
[ -f "$STICK/root_ca.crt" ] || { echo "ABORT: $STICK/root_ca.crt not found (is the stick mounted?)" >&2; exit 1; }
[ -f "$STICK/root_ca_key" ] || { echo "ABORT: $STICK/root_ca_key not found (is the stick mounted?)" >&2; exit 1; }

cd "$DIR"

echo "Signing ipa.csr with the root on $STICK (5-year IPA CA)"
if [ -n "$PWFILE" ]; then
    [ -r "$PWFILE" ] || { echo "ABORT: passphrase file $PWFILE is not readable" >&2; exit 1; }
    echo "(using the root key passphrase in $PWFILE)"
    echo
    "$DIR/step" certificate sign --template ipa-ca.tpl --not-after 43800h \
        --password-file "$PWFILE" \
        ipa.csr "$STICK/root_ca.crt" "$STICK/root_ca_key" \
        > "$TMP"
else
    echo "(the root key's passphrase will be requested now)"
    echo
    "$DIR/step" certificate sign --template ipa-ca.tpl --not-after 43800h \
        ipa.csr "$STICK/root_ca.crt" "$STICK/root_ca_key" \
        > "$TMP"
fi

# --- machine checks: does this certificate actually work? --------------------
echo
echo "Checking the result. Every line must read OK."
FAILED=0

if VERIFY_ERR="$("$DIR/step" certificate verify "$TMP" --roots "$STICK/root_ca.crt" 2>&1)"; then
    echo "  OK    chains to the root on the stick"
else
    echo "  FAIL  does NOT chain to the root on the stick" >&2
    printf '%s\n' "$VERIFY_ERR" >&2
    FAILED=1
fi

I="$("$DIR/step" certificate inspect --format json "$TMP")"

chk() {
    if printf '%s\n' "$I" | grep -Eq "$2"; then
        echo "  OK    $1"
    else
        echo "  FAIL  $1" >&2
        FAILED=1
    fi
}

chk "is a CA certificate"                       '"is_ca"[: ]+true'
chk "path length 0 (issues leaves, no deeper)"  '"max_path_len"[: ]+0'
chk "key usage: certificate sign"               '"certificate_sign"[: ]+true'
chk "key usage: CRL sign"                       '"crl_sign"[: ]+true'
chk "subject: CN=Certificate Authority"         'Certificate Authority'
chk "subject: O=IPA.INTERNAL"                   'IPA\.INTERNAL'
chk "validity is 5 years"                       '"length"[: ]+157680000'

if [ "$FAILED" -ne 0 ]; then
    echo >&2
    echo "STOP: this certificate is not fit to install. Nothing has been trusted" >&2
    echo "      yet — the root is untouched, and signing the same CSR again is safe." >&2
    exit 1
fi

mv "$TMP" "$OUT"
echo "Signed -> $OUT"

echo
echo "=============================================================="
echo "Read the dump below as well. It must show:"
echo "  Issuer   = CN=Homelab Internal CA (the root)"
echo "  Subject  = CN=Certificate Authority, O=IPA.INTERNAL"
echo "  Validity = ~5 years"
echo "  Basic Constraints = critical CA:TRUE, pathlen:0"
echo "  Key Usage = critical Digital Signature, Certificate Sign, CRL Sign"
echo "=============================================================="
echo
"$DIR/step" certificate inspect "$OUT"
