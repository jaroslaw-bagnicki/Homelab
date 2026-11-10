#!/bin/sh
# Sign FreeIPA's CA CSR with the offline root held on the uTrust token
# (PIV applet, slot 9C) over PKCS#11 — see runbook 46 / kit doc 03.
#
#   SIGN_PIV_ALLOW_NETWORK=1 ./sign-ipa-ca.sh [token-label]
#
# The root key never leaves the token: the key argument is a pkcs11: URI and the
# PIV PIN is prompted by PC/SC immediately before the signature. Never put
# pin-value= in the URI, this script, Ansible or the repo.
#
# The CSR is produced on the IPA guest by `ipa-server-install --external-ca`.
# `--template` is used so the signer asserts the CA shape; the resulting
# certificate must chain to the fleet root and match the IPA CA subject.
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/ipa-ca.crt"
TMP="$OUT.new"

MOD="${UTRUST_PKCS11_MODULE:-/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so}"
TOKEN="${1:-${UTRUST_TOKEN:-}}"
OBJECT="${UTRUST_OBJECT:-Homelab Root CA}"

trap 'rm -f "$TMP"' EXIT

# --- network check (same policy as sign-piv.sh) ---------------------------------
# The token's root key is non-exportable, so signing on the networked workstation
# is accepted residual risk; warn loudly and require an explicit opt-in.
if ! command -v ip >/dev/null 2>&1; then
    echo "ABORT: 'ip' is not available, so this machine's network state cannot be checked." >&2
    exit 1
fi
NET="$(ip -o addr show 2>/dev/null | awk '{ n = $2; sub(/:$/, "", n); if (n != "lo") print "  " n " " $4 }')"
if [ -n "$NET" ] || ip route 2>/dev/null | grep -q '^default'; then
    if [ "${SIGN_PIV_ALLOW_NETWORK:-0}" != "1" ]; then
        echo "WARNING: this machine is networked:" >&2
        printf '%s\n' "$NET" >&2
        ip route 2>/dev/null | grep '^default' >&2 || true
        echo "  Accepted only because the uTrust root key is non-exportable (runbook 46):" >&2
        echo "  worst case is one rogue certificate signed while the token is plugged in." >&2
        echo "  Re-run with SIGN_PIV_ALLOW_NETWORK=1 to proceed on this machine." >&2
        exit 1
    fi
    echo "NOTE: networked machine, SIGN_PIV_ALLOW_NETWORK=1 — residual risk accepted (runbook 46)."
fi

# --- inputs ------------------------------------------------------------------
if [ ! -x "$DIR/step" ]; then
    echo "ABORT: $DIR/step is missing or not executable (copy the kit to /tmp and chmod +x)." >&2
    exit 1
fi
if ! command -v step-kms-plugin >/dev/null 2>&1; then
    echo "ABORT: step-kms-plugin is not in PATH — the stock step execs it for pkcs11: URIs." >&2
    echo "       Add the CGO step-kms-plugin binary to the kit and PATH, plus libpcsclite1." >&2
    exit 1
fi
[ -f "$MOD" ] || { echo "ABORT: PKCS#11 module $MOD not found (install opensc)." >&2; exit 1; }
[ -f "$DIR/ipa.csr" ]      || { echo "ABORT: $DIR/ipa.csr is missing (bring it from the IPA guest)" >&2; exit 1; }
[ -f "$DIR/ipa-ca.tpl" ]   || { echo "ABORT: $DIR/ipa-ca.tpl is missing" >&2; exit 1; }
[ -f "$DIR/root_ca.crt" ]  || { echo "ABORT: $DIR/root_ca.crt is missing (provision the root on the token first)" >&2; exit 1; }

if [ -z "$TOKEN" ]; then
    TOKEN="$(pkcs11-tool --module "$MOD" --list-slots 2>/dev/null | sed -n 's/^  token label *: //p' | head -1)"
fi
[ -n "$TOKEN" ] || { echo "ABORT: no token label — pass it as the first argument." >&2; exit 1; }

URI="pkcs11:module-path=$MOD;token=$TOKEN;object=$OBJECT;type=private"

cd "$DIR"

# --- eyeball the exact CSR before signing --------------------------------------
echo "CSR that will be signed (verify subject + public key now):"
"$DIR/step" certificate inspect ipa.csr
echo

echo "Signing ipa.csr with the root on the uTrust token (slot 9C, 5-year IPA CA)"
echo "  module : $MOD"
echo "  token  : $TOKEN"
echo "  object : $OBJECT"
echo "(the PIV PIN will be prompted by PC/SC now — once, immediately before the signature)"
echo
"$DIR/step" certificate sign --template ipa-ca.tpl --not-after 43800h \
    ipa.csr "$DIR/root_ca.crt" "$URI" \
    > "$TMP"

# --- machine checks: does this certificate actually work? --------------------
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
    echo "      yet — the token is untouched, and signing the same CSR again is safe." >&2
    exit 1
fi

mv "$TMP" "$OUT"
echo "Signed -> $OUT"

echo
echo "Unplug the token and return it to the safe."
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
