#!/usr/bin/env bash
# check-utrust.sh — READ-ONLY health check for uTrust FIDO2 NFC USB-A (P/N 905601)
# See docs/research/54-utrust-fido2-nfc-piv-root-diagnostic.md §4.
# OpenSC >= 0.23: `opensc-tool -r` now means --reader, readers are listed with -l.
# Run on the machine where the key is plugged in (workstation, or WSL after
# `usbipd attach --wsl --busid <busid>` from the Windows host). No PIN login,
# writes nothing to the token.
set -u
echo "== USB ==";  lsusb 2>/dev/null | grep -iE 'identiv|04e6|utrust' || echo "  !! no Identiv device"
echo "== reader =="; opensc-tool -l 2>&1
echo "== driver/ATR =="; opensc-tool --name 2>&1; opensc-tool -a 2>&1 | head -2
echo "== PIV AID select (want 9000) =="
opensc-tool -s '00a4040008a000000308000010000000' 2>&1 | tail -1
echo "== CPLC chip (want 40 90 = SLE78) =="
opensc-tool -s '00a4040008a000000151000000' -s '00ca9f7f' 2>&1 | tail -4
MOD="$(find /usr/lib -name 'opensc-pkcs11.so' 2>/dev/null | head -1)"
echo "== PKCS#11 module: ${MOD:-NOT FOUND} =="
[ -n "$MOD" ] && pkcs11-tool --module "$MOD" --list-slots 2>&1
echo "== FIDO2 AAGUID (want 73402251-...) =="
fido2-token -L 2>&1 || echo "  fido2-token failed (install fido2-tools)"
