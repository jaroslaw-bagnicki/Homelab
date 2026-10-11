#!/bin/sh
# Create the 10-year offline root CA on the secure USB stick. FIRST RUN ONLY.
#
#   ./root.sh <destination-path> [passphrase-file]      e.g. /mnt/sdX1 (no default)
#
# The root key is the one secret in this PKI that cannot be replaced: it signs the
# intermediate, and every client trusts the certificate it belongs to. So it is
# generated here, on a machine with no network, and stored only on the stick.
#
# This script deliberately refuses to run when a root already exists. Replacing a
# root is a trust rotation (issue #144: every client must re-trust), not a re-run.
#
# Uses --profile root-ca, which is correct here and NOT a contradiction of sign.sh's
# "never --profile" rule. A profile rebuilds a certificate from its own defaults, so
# signing a CSR with one discards whatever the requester asked for - for the
# intermediate that silently drops the SANs that declare its identity. A root has no
# SANs to drop (it is never a TLS server) and inherits nothing from a CSR (it is the
# trust anchor). Its whole required shape is CA:TRUE + pathlen>=1 + certSign/crlSign,
# which is exactly what this profile produces.
set -eu

[ $# -ge 1 ] || { echo "usage: $0 <destination-path> [passphrase-file]" >&2; echo "       e.g. $0 /mnt/sdX1" >&2; exit 1; }
STICK="$1"
PWFILE="${2:-}"
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_CN="Homelab Internal CA"
ROOT_LIFETIME="87600h"   # 10 years

# --- the signing machine must not have a network -----------------------------
# Both checks are deliberate: the address test also catches an on-link-only machine.
if ! command -v ip >/dev/null 2>&1; then
    echo "ABORT: 'ip' is not available, so this machine's network state cannot be checked." >&2
    exit 1
fi
NET="$(ip -o addr show 2>/dev/null | awk '{ n = $2; sub(/:$/, "", n); if (n != "lo") print "  " n " " $4 }')"
if [ -n "$NET" ]; then
    echo "ABORT: this machine has a non-loopback address:" >&2
    printf '%s\n' "$NET" >&2
    echo "       The root key must never be created on a networked machine." >&2
    echo "       Unplug the cable / disable Wi-Fi (or 'ip link set <dev> down') and re-run." >&2
    exit 1
fi
if ip route 2>/dev/null | grep -q '^default'; then
    echo "ABORT: this machine has a default route — it is not air-gapped." >&2
    echo "       The root key must never be created on a networked machine." >&2
    exit 1
fi

# --- the tool ---------------------------------------------------------------
if [ ! -x "$DIR/step" ]; then
    echo "ABORT: $DIR/step is missing or not executable." >&2
    echo "       If the file is present, you are most likely running this from a" >&2
    echo "       FAT/exFAT USB stick — those filesystems have no executable bit, so" >&2
    echo "       'chmod +x' does nothing there. Copy the bundle to a real filesystem:" >&2
    echo "         cp -r $DIR /tmp/bundle && cd /tmp/bundle && chmod +x step root.sh sign.sh" >&2
    exit 1
fi

# --- the stick ------------------------------------------------------------
[ -d "$STICK" ] || { echo "ABORT: $STICK is not a directory (is the stick mounted?)" >&2; exit 1; }

# --- the one-way door -------------------------------------------------------
if [ -e "$STICK/root_ca_key" ] && [ -e "$STICK/root_ca.crt" ]; then
    echo "ABORT: a root already exists on $STICK — nothing was created." >&2
    echo >&2
    echo "  This script only ever creates the FIRST root. Re-running it cannot" >&2
    echo "  replace the existing one: every client that already trusts it would" >&2
    echo "  stop trusting the CA. Replacing a root is a rotation with a full" >&2
    echo "  re-trust of the fleet and workstations (issue #144)." >&2
    echo >&2
    echo "  To carry on with the root you already have, run:" >&2
    echo "    ./sign.sh $STICK" >&2
    exit 1
fi

if [ -e "$STICK/root_ca_key" ] || [ -e "$STICK/root_ca.crt" ]; then
    echo "ABORT: $STICK holds an INCOMPLETE root — one file without the other." >&2
    echo "       An earlier creation run must have failed part-way. Nothing was" >&2
    echo "       created now. Inspect it, then remove both files and run again:" >&2
    echo "         ls -l $STICK/root_ca*" >&2
    echo "         rm -f $STICK/root_ca.crt $STICK/root_ca_key" >&2
    exit 1
fi

# --- create -----------------------------------------------------------------
echo "Creating the root CA on $STICK"
echo "  common name : $ROOT_CN"
echo "  lifetime    : $ROOT_LIFETIME (10 years)"
echo "  shape       : CA:TRUE, pathlen:1, keyUsage certSign + crlSign, no SANs"
echo

if [ -n "$PWFILE" ]; then
    [ -r "$PWFILE" ] || { echo "ABORT: passphrase file $PWFILE is not readable" >&2; exit 1; }
    echo "Encrypting the root key with the passphrase in $PWFILE."
    echo
    "$DIR/step" certificate create "$ROOT_CN" \
        "$STICK/root_ca.crt" "$STICK/root_ca_key" \
        --profile root-ca --not-after "$ROOT_LIFETIME" \
        --password-file "$PWFILE"
else
    echo "You will now be asked to choose a passphrase for the root key."
    echo
    echo "  ==> WRITE THE PASSPHRASE DOWN AND PUT IT IN THE SAFE BEFORE YOU LEAVE"
    echo "      THIS MACHINE. It is the only way to use this root key again. Lose it"
    echo "      and the root key is dead - recovery is a new root plus a full"
    echo "      re-trust of every client (issue #144)."
    echo
    "$DIR/step" certificate create "$ROOT_CN" \
        "$STICK/root_ca.crt" "$STICK/root_ca_key" \
        --profile root-ca --not-after "$ROOT_LIFETIME"
fi

# --- verify the shape we just created ---------------------------------------
echo
echo "Checking the result. Every line must read OK."
echo

J="$("$DIR/step" certificate inspect --format json "$STICK/root_ca.crt")"
FAILED=0

chk() {
    if printf '%s\n' "$J" | grep -Eq "$2"; then
        echo "  OK    $1"
    else
        echo "  FAIL  $1" >&2
        FAILED=1
    fi
}

chk "self-signed certificate"                    '"self_signed"[: ]+true'
chk "is a CA certificate (is_ca)"                '"is_ca"[: ]+true'
chk "path length >= 1 (may sign an intermediate)" '"max_path_len"[: ]+[1-9]'
chk "key usage: certificate sign"                '"certificate_sign"[: ]+true'
chk "key usage: CRL sign"                        '"crl_sign"[: ]+true'
chk "validity is 10 years"                       '"length"[: ]+315360000'

if grep -q 'ENCRYPTED' "$STICK/root_ca_key"; then
    echo "  OK    root key is passphrase-protected"
else
    echo "  FAIL  root key is NOT passphrase-protected (plaintext on the stick)" >&2
    FAILED=1
fi

echo
echo "  note: the output above will also say \"valid\": false. That is normal for a"
echo "        root - there is no higher authority to validate it against."
echo "        \"self_signed\": true is the correct check."

if [ "$FAILED" -ne 0 ]; then
    echo >&2
    echo "STOP: the root on $STICK does not have the shape the CA needs." >&2
    echo "      No trust has been distributed yet, so it is safe to discard the" >&2
    echo "      root and start over:" >&2
    echo "        rm -f $STICK/root_ca.crt $STICK/root_ca_key" >&2
    exit 1
fi

# --- fingerprint ------------------------------------------------------------
echo
echo "Root certificate fingerprint — record it OUTSIDE the repo (safe, password"
echo "manager), together with the key passphrase:"
"$DIR/step" certificate fingerprint "$STICK/root_ca.crt"

echo
echo "=============================================================="
echo "Root created. Next: sign the intermediate with it."
echo "  ./sign.sh $STICK"
echo
echo "Before you power this machine off:"
echo "  - unmount and remove the stick, return it to the safe"
echo "  - make sure the root key passphrase is written down in the safe"
echo "=============================================================="
