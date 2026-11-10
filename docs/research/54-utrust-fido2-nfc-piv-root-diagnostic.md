# 54 — HIRSCH SECURE uTrust FIDO2 NFC USB-A as offline root custody for `step-ca` — device diagnostic

**Status**: 🔬 Research — in progress, hardware checks pending
**Date**: 2026-11-08
**Question**: Can the uTrust FIDO2 NFC USB-A (P/N 905601) hold the offline root CA key in its PIV applet
(slot 9C) and sign the `step-ca` intermediate CSR via PKCS#11 from a workstation — the token-custody
upgrade [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) plans (currently IronKey, planned
YubiKey PIV)?
**Related**: [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) · [ADR 42](../decisions/42-pki-topology-sibling-cas.md) · [research 36 §4–§5](36-step-ca-machine-identity.md) · [runbook 35](../runbooks/35-deploy-step-ca.md) · [runbook 36](../runbooks/36-private-ca-init.md) · [offline signing kit](../private-ca-offline-signing/README.md)

> **This is a diagnostic log, not a deployment recipe.** Nothing has been written to the token yet. The
> output so far is document analysis plus the FIDO2-side readout from Hirsch SecureFIDO Manager; the
> decisive PIV/PKCS#11 checks are still pending on hardware (§4).

## Executive summary

1. **The FIDO2 applet cannot be the root CA keystore.** CTAP2 only generates keys on-device (no import)
   and its signatures are protocol-bound (`SHA-256(authenticatorData ‖ clientDataHash)` with RP-ID hash
   and UP/UV flags) — it cannot produce an X.509 CA signature over a CSR. Root custody must go through
   the **PIV smart-card applet over the CCID interface / PKCS#11**.
2. **PIV is documented on the non-plus model.** The uTrust FIDO2 Technical Manual puts a
   PIV-compatible app on the whole family over CCID, and the 2021 datasheet for the plain NFC
   (905601/905602) lists `PIV` in "Secure Element Interface". But the manual also says the **firmware
   version decides which applets a given unit has enabled** — so per-unit verification is mandatory.
   The NFC+ SKU is the one where PIV/OTP management via uTrust Key Manager, Windows 10/11 standalone
   auth and the FIPS 140-3 GOV variant are headline features; it adds no cryptographic strength over
   the plain NFC (same SLE 78 chip, same slots/algorithms).
3. **`step-ca` integration is ceremony-only.** The live CA on the `ca` guest is unchanged — intermediate
   stays in the `pve1` TPM (`tpmkms`, stock binary, [runbook 35 §6](../runbooks/35-deploy-step-ca.md)).
   The token is used only in the offline signing ceremony: `step certificate sign … 'pkcs11:…'` on a
   **CGO-built `step` CLI** on the signing workstation ([research 36 §5](36-step-ca-machine-identity.md)).
   The root token must never be plugged into `pve1` — that would break ADR 38's "root not reachable by a
   server compromise" invariant.
4. **Hardware so far** (Hirsch SecureFIDO Manager 1.0.0 log, 2026-11-08): genuine device
   `VID_04E6&PID_5A11`, AAGUID `73402251-f2a8-4f03-873e-3cb6db604b03` (manual's family AAGUID), FIDO_2_0 +
   U2F_V2 + `hmac-secret`, `rk:true`, `clientPin:true`, MIN PIN 4 / 8 retries, no USB serial descriptor,
   CCID reader enumerates under PC-SC, **no CTAP 2.1 credMgmt** (firmware is FIDO_2_0), and `certutil -scinfo`
   detects the card as `Identity Device (NIST SP 800-73 [PIV])` → **PIV applet present** (§3).
5. **Pending**: the Linux-side gates — PIV AID select → `9000` and `pkcs11-tool --list-slots` (OpenSC/PKCS#11
   must drive slot 9C for the ceremony), CPLC chip check (`40 90` = SLE 78), firmware version from Key
   Manager. Commands and expected values in §4.

## 1. Why the FIDO2 applet is out — and what the PIV applet offers

| | FIDO2/CTAP applet | PIV applet (CCID) |
|---|---|---|
| Key import | ❌ generate-only on device | ✅ import or generate at provisioning (manual: PIN policy set "upon key generation or import") |
| Arbitrary data signing | ❌ signatures bound to CTAP structure | ✅ RSA/ECC sign via PKCS#11 (manual: "enables RSA or ECC sign/encrypt operations using a private key stored on a smart card through common interfaces like PKCS#11") |
| Algorithms | ECDSA P-256 (FIDO card sheet) | RSA 1024/2048/3072, ECC P-256/P-384 — **no RSA 4096** |
| Slots | resident credentials (64) | 9A auth · **9C digital signature** · 9D key mgmt · 9E card auth |
| Slot 9C policy | — | PIN required **immediately before each signature** (cardholder participation per sign — the ceremony behavior wanted for a root) |

## 2. What the vendor documents say (evidence)

- **Technical Manual** (`uTrust_FIDO2_Technical_Manual.pdf`, Identiv/Hirsch): the family "provides a
  PIV-compatible smart card application"; "The CCID interface provides communication for the PIV /
  Smart Card, and OATH"; "The uTrust FIDO2 NFC/NFC+ presents itself … as a USB smart card reader";
  "it is the **firmware version** that determines which of the more specialized functionalities … are
  available". Defaults: PIV PIN `123456`, PUK `12345678`, management key (3DES)
  `010203040506070801020304050607080102030405060708`. CPLC first two bytes `40 90` = Infineon SLE 78.
  AAGUID `73402251-f2a8-4f03-873e-3cb6db604b03` for NFC and NFC+.
- **Datasheet** (`uTrust-FIDO2-NFC-Security-Keys-DS.pdf`, rev 2021-08-02): P/N **905601** (USB-A) /
  905602 (USB-C), "Secure Element Interface: FIDO2, U2F, HOTP, TOTP, **PIV**", "Contactless
  Functionality: Physical Access PIV". Certifications on that sheet: FIDO U2F + FIDO2, CE/FCC — no FIPS.
- **Marketing vs documents**: reseller/manufacturer pages position "PIV available in the NFC+ models"
  and NFC+ = Key Manager PIV/OTP management + Windows 10/11 standalone + FIPS 140-3 GOV variant. The
  manual + base-model datasheet say PIV is in the family. Reading: PIV is a documented interface of the
  905601, but whether a given unit's firmware exposes it must be checked per device.

## 3. Diagnostic log so far (2026-11-08, hardware)

Source: Hirsch SecureFIDO Manager 1.0.0 (Windows), Device Config view + app log.

- ✅ Hardware gate passed: "Identiv uTrust FIDO2 Security Key", `USB\VID_04E6&PID_5A11&MI_00…`
- ✅ FIDO2 over USB HID reads fine; AAGUID allowlist = the family AAGUID above
- ✅ FIDO2 PIN set (after one factory reset — fresh key, no credentials lost; note: FIDO2 reset also
  wipes U2F, per the manual — never do it once passkeys are enrolled)
- ℹ️ No USB serial-number descriptor (serial lives in CPLC/PIV instead)
- ℹ️ PC-SC reader `Identiv uTrust FIDO2 Security Key 0` enumerates → CCID interface present
- ℹ️ No CTAP 2.1 `credMgmt` (firmware FIDO_2_0) → resident credentials can't be listed/deleted
  individually via CTAP; only a full FIDO2 factory reset clears them
- ✅ `certutil -scinfo` (2026-11-08): card = **`Identity Device (NIST SP 800-73 [PIV])`**, ATR
  `3b 96 11 81 21 75 75 54 72 75 73 74 73` (`uuTrusts`) → **the PIV applet is present and enabled on this
  non-plus unit**. The trailing `NTE_BAD_KEYSET` / "Missing stored keyset" is certutil's Microsoft CSP
  keyset *analysis* on a fresh card, not a card fault.

## 4. Pending hardware checks — resume here (VSCode terminal)

Run on the **Linux workstation** (not `pve1`), key plugged in:

```sh
sudo apt install pcscd pcsc-tools opensc libpcsclite1 libfido2-bin   # if missing
sudo systemctl start pcscd
```

| # | Command | Expected if OK |
|---|---|---|
| 1 | `lsusb \| grep -i 04e6` | Identiv `04e6:5a11` uTrust FIDO2 |
| 2 | `opensc-tool -r` | one CCID reader |
| 3 | `opensc-tool --name` | driver `PIV-II` |
| 4 | `opensc-tool -s '00a4040008a000000308000010000000'` | SW **`9000`** → PIV applet enabled on this unit |
| 5 | `opensc-tool -s '00a4040008a000000151000000' -s '00ca9f7f'` | CPLC starts **`40 90`** → SLE 78 chip (serial follows) |
| 6 | `pkcs11-tool --module "$(find /usr/lib -name opensc-pkcs11.so \| head -1)" --list-slots` | token listed → **OpenSC PKCS#11 claims it** (the gate for the ceremony) |
| 7 | `fido2-token -L` | AAGUID `73402251-f2a8-4f03-873e-3cb6db604b03` |

Windows cross-check **done 2026-11-08**: `certutil -scinfo` lists the PIV card (§3). Still wanted from
Key Manager: the **firmware version** (manual: firmware decides applet enablement).

Reference script (same checks, read-only, no PIN login, writes nothing to the token):

```sh
#!/usr/bin/env bash
# check-utrust.sh — READ-ONLY health check for uTrust FIDO2 NFC USB-A (P/N 905601)
set -u
echo "== USB ==";  lsusb | grep -iE 'identiv|04e6|utrust' || echo "  !! no Identiv device"
echo "== reader =="; opensc-tool -r
echo "== driver/ATR =="; opensc-tool --name; opensc-tool -a | head -2
echo "== PIV AID select (want 9000) =="
opensc-tool -s '00a4040008a000000308000010000000' | tail -1
echo "== CPLC chip (want 40 90 = SLE78) =="
opensc-tool -s '00a4040008a000000151000000' -s '00ca9f7f' | tail -4
MOD="$(find /usr/lib -name 'opensc-pkcs11.so' 2>/dev/null | head -1)"
echo "== PKCS#11 module: ${MOD:-NOT FOUND} =="
[ -n "$MOD" ] && pkcs11-tool --module "$MOD" --list-slots
echo "== FIDO2 AAGUID (want 73402251-...) =="
fido2-token -L 2>/dev/null || echo "  install libfido2-bin"
```

**Decision rule**: Windows PIV detection ✅ (done, §3). Remaining gates are Linux checks 4 + 6: both
pass → key cleared for the provisioning ceremony (§5). Check 4 fails → Windows sees PIV but OpenSC cannot
drive it on Linux; then either provision/sign on Windows via uTrust Key Manager, or switch to an NFC+ SKU.

## 5. If verified — provisioning ceremony outline (not yet executed)

1. Change factory defaults first: PIV PIN, PUK, management key (`piv-tool` / `pkcs11-tool` / Key
   Manager).
2. Import the **existing** root key into **slot 9C** with PIN policy **always** (policy is fixed at
   import — manual); install the existing `root_ca.crt` as the slot certificate so the root cert is
   unchanged and only custody moves (ADR 38). Algorithm must be RSA ≤ 3072 or P-256/P-384 — check
   `step certificate inspect root_ca.crt` first (**RSA-4096 will not fit**).
3. Test-sign a throwaway CSR, then **destroy every exportable copy** (IronKey key file + backups) —
   ADR 38: import alone doesn't give custody. Backup = a **second uTrust** with the same key imported.
4. Ceremony signing ([runbook 36](../runbooks/36-private-ca-init.md), `sign.sh` delta) — replace the
   stick's key file with a PKCS#11 URI; PIN is prompted per signature, never put `pin-value=` in the
   URI/script/repo:

   ```sh
   ./step certificate sign --template intermediate-ca.tpl --not-after 8760h \
     intermediate_ca.csr "$STICK/root_ca.crt" \
     'pkcs11:module-path=/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so;object=Homelab Root CA;type=private' \
     > "$TMP"
   ```

   Requires the **CGO `step` CLI** on the signing machine only ([research 36 §5](36-step-ca-machine-identity.md));
   all of `sign.sh`'s machine checks (chains to root, `is_ca`, `pathlen:0`, SANs `ca.internal` +
   `192.168.2.215`, 1 year) run unchanged. `ca.json` on the `ca` guest does **not** change.

## 6. Constraints and risks

- Root token **never** plugged into `pve1` / the `ca` guest (ADR 38 invariant); workstation signing is
  acceptable only with the token unplugged outside ceremonies, per-signature PIN, and CSR public-key
  verification before signing (residual: one rogue 1-year intermediate, key still non-exportable).
- OpenSC must claim the card on Linux — a 2023 report had default `opensc-pkcs11.so` not claiming a
  uTrust under Linux; retest on the actual unit (check 6). Identiv ships no Linux PKCS#11 module of its
  own; Key Manager is Windows-only.
- `step-ca`'s YubiKey-PIV KMS is YubiKey-specific — the uTrust goes through generic `pkcs11:` URIs only.
- FIDO2 applet remains useful for Authentik WebAuthn passkeys / FIDO2 SSH — orthogonal to CA signing.

## References

- `uTrust_FIDO2_Technical_Manual.pdf` (Identiv/Hirsch) — PIV app, slots, policies, defaults, CPLC/SLE78, AAGUID (uploaded during this diagnostic)
- `uTrust-FIDO2-NFC-Security-Keys-DS.pdf` rev 2021-08-02 — P/N 905601/905602, PIV in secure-element interface (uploaded during this diagnostic)
- [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) — three-tier PKI, root custody, PIV-migration ceremony
- [research 36 §4–§5](36-step-ca-machine-identity.md) — KMS/custody paths; CGO build needed for PKCS#11, signing machine only
- [runbook 35 §6–§7](../runbooks/35-deploy-step-ca.md) — CSR emission from the TPM key; `ca.json` `tpmkms`
- [runbook 36](../runbooks/36-private-ca-init.md) + [offline signing kit](../private-ca-offline-signing/README.md) — the ceremony this token would serve
