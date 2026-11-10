#!/bin/sh
# Sign the intermediate CSR with the offline root held in the uTrust FIDO2 NFC token
# (PIV applet, slot 9C) over PKCS#11. Token-custody variant of sign.sh — see runbook 46.
#
#   ./sign-piv.sh [token-label]        e.g. ./sign-piv.sh "Identiv uTrust FIDO2 0"
#
# The root key never leaves the token: the key argument is a pkcs11: URI and the PIV
# PIN is prompted by PC/SC immediately before the signature. Never put pin-value=
# in the URI, this script, Ansible or the repo.
#
# Uses --template, never --profile: same reason as sign.sh — a profile silently
# drops the SANs that declare the CA's identity shape (03-signing-csr.md).
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/intermediate_ca.crt"
TMP="$OUT.new"

MOD="${UTRUST_PKCS11_MODULE:-/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so}"
TOKEN="${1:-${UTRUST_TOKEN:-}}"
OBJECT="${UTRUST_OBJECT:-Homelab Root CA}"

# never leave a half-written certificate behind for someone to carry home
trap 'rm -f "$TMP"' EXIT

# --- the signing machine must not have a network -----------------------------
# Identical to sign.sh: the address test also catches an on-link-only machine.
if ! command -v ip >/dev/null 2>&1; then
    echo "ABORT: 'ip' is not available, so this machine's network state cannot be checked." >&2
    exit 1
fi
NET="$(ip -o addr show 2>/dev/null | awk '{ n = $2; sub(/:$/, "", n); if (n != "lo") print "  " n " " $4 }')"
if [ -n "$NET" ]; then
    echo "ABORT: this machine has a non-loopback address:" >&2
    printf '%s\n' "$NET" >&2
    echo "       The root token must never be used on a networked machine." >&2
    echo "       Unplug the cable / disable Wi-Fi (or 'ip link set <dev> down') and re-run." >&2
    exit 1
fi
if ip route 2>/dev/null | grep -q '^default'; then
    echo "ABORT: this machine has a default route — it is not air-gapped." >&2
    echo "       The root token must never be used on a networked machine." >&2
    exit 1
fi

# --- inputs ------------------------------------------------------------------
if [ ! -x "$DIR/step" ]; then
    echo "ABORT: $DIR/step is missing or not executable." >&2
    echo "       If the file is present, you are most likely running this from a" >&2
    echo "       FAT/exFAT USB stick — those filesystems have no executable bit, so" >&2
    echo "       'chmod +x' does nothing there. Copy the bundle to a real filesystem:" >&2
    echo "         cp -r $DIR /tmp/bundle && cd /tmp/bundle && chmod +x step sign-piv.sh" >&2
    exit 1
fi
# the stock static step delegates pkcs11: URIs to the external CGO plugin
if ! command -v step-kms-plugin >/dev/null 2>&1; then
    echo "ABORT: step-kms-plugin is not in PATH — the stock step execs it for pkcs11: URIs." >&2
    echo "       Add the CGO step-kms-plugin v0.17.0 binary (smallstep/step-kms-plugin" >&2
    echo "       release, checksum-verified) to this bundle and PATH, plus libpcsclite1." >&2
    exit 1
fi
[ -f "$MOD" ] || { echo "ABORT: PKCS#11 module $MOD not found (install opensc)." >&2; exit 1; }
[ -f "$DIR/intermediate_ca.csr" ]  || { echo "ABORT: $DIR/intermediate_ca.csr is missing" >&2; exit 1; }
[ -f "$DIR/intermediate-ca.tpl" ] || { echo "ABORT: $DIR/intermediate-ca.tpl is missing" >&2; exit 1; }
[ -f "$DIR/root_ca.crt" ]          || { echo "ABORT: $DIR/root_ca.crt is missing (export it from the token first)" >&2; exit 1; }

if [ -z "$TOKEN" ]; then
    echo "probing token label via pkcs11-tool (pass it as \$1 to skip):"
    pkcs11-tool --module "$MOD" --list-slots 2>/dev/null | sed -n 's/^  token label *: //p' | head -1 > "$TMP.label" || true
    TOKEN="$(head -1 "$TMP.label" 2>/dev/null || true)"
    rm -f "$TMP.label"
fi
[ -n "$TOKEN" ] || { echo "ABORT: no token label — pass it as the first argument." >&2; exit 1; }

URI="pkcs11:module-path=$MOD;token=$TOKEN;object=$OBJECT;type=private"

cd "$DIR"

# --- eyeball the exact CSR before signing --------------------------------------
echo "CSR that will be signed (verify subject + public key now):"
"$DIR/step" certificate inspect intermediate_ca.csr
echo

echo "Signing intermediate_ca.csr with the root on the uTrust token (slot 9C)"
echo "  module : $MOD"
echo "  token  : $TOKEN"
echo "  object : $OBJECT"
echo "(the PIV PIN will be prompted by PC/SC now — once, immediately before the signature)"
echo
"$DIR/step" certificate sign --template intermediate-ca.tpl --not-after 8760h \
    intermediate_ca.csr "$DIR/root_ca.crt" "$URI" \
    > "$TMP"

# --- machine checks: does this certificate actually work? --------------------
# Same checks as sign.sh, run against the temporary file; promoted only when all pass.
echo
echo "Checking the result. Every line must read OK."
FAILED=0

if VERIFY_ERR="$("$DIR/step" certificate verify "$TMP" --roots "$DIR/root_ca.crt" 2>&1)"; then
    echo "  OK    chains to the root in the kit"
else
    echo "  FAIL  does NOT chain to the root in the kit" >&2
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

chk "is a CA certificate"                      '"is_ca"[: ]+true'
chk "path length 0 (issues leaves, no deeper)"  '"max_path_len"[: ]+0'
chk "key usage: certificate sign"              '"certificate_sign"[: ]+true'
chk "key usage: CRL sign"                      '"crl_sign"[: ]+true'
chk "identity shape: SAN present"                    '"dns_names"'
chk "identity shape: SAN carries ca.internal"        'ca\.internal'
chk "identity shape: SAN carries 192.168.2.215"      '192\.168\.2\.215'
chk "validity is 1 year"                             '"length"[: ]+31536000'

if [ "$FAILED" -ne 0 ]; then
    echo >&2
    echo "STOP: this certificate is not fit to install. Nothing has been trusted" >&2
    echo "      yet — the token is untouched, and signing the same CSR again is" >&2
    echo "      safe. The failed certificate was discarded; an earlier one on disk," >&2
    echo "      if any, was left untouched." >&2
    exit 1
fi

mv "$TMP" "$OUT"
echo "Signed -> $OUT"

echo
echo "Unplug the token and return it to the safe."
"$DIR/step" certificate inspect "$OUT"
