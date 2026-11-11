# 54 — HIRSCH SECURE uTrust FIDO2 NFC USB-A as offline root custody for `step-ca` — device diagnostic

**Status**: ✅ **Resolved** — the key is verified and cleared for the ceremony; the ceremony itself has not run
**Date**: 2026-11-08 (hardware verified 2026-11-10/11)
**Question**: Can the uTrust FIDO2 NFC USB-A (P/N 905601) hold the offline root CA key in its PIV applet
(slot 9C) and sign the `step-ca` intermediate CSR via PKCS#11 from a workstation — the token-custody
upgrade [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) plans (currently IronKey, planned
YubiKey PIV)?  
**Related**: [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) · [ADR 42](../decisions/42-pki-topology-sibling-cas.md) · [research 36 §4–§5](36-step-ca-machine-identity.md) · [runbook 35](../runbooks/35-deploy-step-ca.md) · [runbook 36](../runbooks/36-private-ca-init.md) · [signing kit](../ca-signing-kit/README.md) · [issue #193](https://github.com/jaroslaw-bagnicki/Homelab/issues/193)  

> **This is a diagnostic log, not a deployment recipe.** Nothing has been written to the token yet —
> the key answers over PKCS#11 and holds no root. The document analysis and the FIDO2-side readout from
> Hirsch SecureFIDO Manager are in §2–§3; the PIV/PKCS#11 checks were measured on hardware on
> 2026-11-10/11 (§4), and the five problems that stood in the way are recorded in §7.

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
   the plain NFC (same secure element, same slots/algorithms).
3. **`step-ca` integration is ceremony-only.** The live CA on the `ca` guest is unchanged — intermediate
   stays in the `pve1` TPM (`tpmkms`, stock binary, [runbook 35 §6](../runbooks/35-deploy-step-ca.md)).
   The token is used only in the offline signing ceremony: `step certificate sign … 'pkcs11:…'` on a
   the stock `step` CLI plus the CGO **`step-kms-plugin`** binary in `PATH` on the signing workstation
   ([research 36 §5](36-step-ca-machine-identity.md), §5 step 5 below).
   The root token must never be plugged into `pve1` — that would break ADR 38's "root not reachable by a
   server compromise" invariant.
4. **Hardware so far** (Hirsch SecureFIDO Manager 1.0.0 log, 2026-11-08): genuine device
   `VID_04E6&PID_5A11`, AAGUID `73402251-f2a8-4f03-873e-3cb6db604b03` (manual's family AAGUID), FIDO_2_0 +
   U2F_V2 + `hmac-secret`, `rk:true`, `clientPin:true`, MIN PIN 4 / 8 retries, no USB serial descriptor,
   CCID reader enumerates under PC-SC, **no CTAP 2.1 credMgmt** (firmware is FIDO_2_0), and `certutil -scinfo`
   detects the card as `Identity Device (NIST SP 800-73 [PIV])` → **PIV applet present** (§3).
5. **Hardware gates — all cleared 2026-11-10** (WSL 2, Ubuntu 26.04, key attached with `usbipd`):
   PIV AID select answers `9000`, `pkcs11-tool --list-slots` lists the token as `PIV_II`, and the
   AAGUID matches the family value. **The CPLC reads `96 4D` (NXP JCOP), not `40 90` (Infineon SLE 78)**
   as the manual claims — the chip vendor is irrelevant to the ceremony, so the check was dropped from
   the kit rather than "fixed". Getting the key this far took four fixes, all recorded in
   [01-setup.md](../ca-signing-kit/01-setup.md): polkit refusal, a missing libccid device-table entry,
   USB permissions for the `pcscd` user, and the systemd sandbox. Still wanted from Key Manager: the
   firmware version.
6. **Decision 2026-11-10 ([issue #193](https://github.com/jaroslaw-bagnicki/Homelab/issues/193)): reissue the root on the token — do not import.** The new 10-year root is generated **in slot 9C**, so the key never exists in software. (Import would also fit — the current root is P-256, within the PIV app's ECC P-256/P-384 — but it would pass the key through workstation memory once.) Reissue deliberately accepts the one-time trust rotation ADR 38 originally rejected; ADR 38 is amended on this branch; the procedure and rotation steps are in [runbook 46](../runbooks/46-adopt-utrust-piv-root-custody.md).

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
  `010203040506070801020304050607080102030405060708`. **The manual's CPLC claim (`40 90` = Infineon
  SLE 78) is wrong for this unit** — the measured CPLC reports `96 4D` (NXP) with `JNET` in the serial
  field, i.e. an **NXP JCOP** secure element (§4, measured 2026-11-10). JCOP is the conventional chip for
  PIV tokens; nothing about the ceremony depends on the vendor.
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

### 2026-11-10 — dev-container session (toolchain staged, no key attached)

Run from the WSL2 dev container. The container has **no USB host bus** (`/dev/bus/usb` absent, no
`usbipd` interop), so the on-device checks below still cannot run here — see §4 for how to attach the
key. What this session settled without hardware:

- ✅ **Toolchain staged and baseline-verified**: `pcscd 2.0.3`, `opensc 0.25.0~rc1`, `pcsc-tools
  1.7.1`, `fido2-tools 1.14.0`, `usbutils`, `libpcsclite1`, `softhsm2` installed; `pcscd` running;
  `Test-uTrustKey.ps1` runs clean end-to-end and reports the expected "No smart card readers found"
  with no device. Note for Ubuntu 24.04: the FIDO2 CLI package is **`fido2-tools`** (not
  `libfido2-bin`), and on OpenSC ≥ 0.23 **`-r` means `--reader` — readers are listed with `-l`**.
- ✅ **Root key algorithm — the RSA-4096 worry is moot**: `step certificate inspect root_ca.crt`
  (offline signing kit) → **ECDSA P-256** (also `ECDSA-SHA256` signature, 10-year root). P-256 is
  within the PIV applet's ECC P-256/P-384 → **slot 9C can hold the existing root key** (§5 step 2).
  The intermediate CSR is P-256 too.
- ✅ **PKCS#11 signing path proven end-to-end without hardware** (SoftHSM 2.6 as the stand-in module,
  throwaway keys): the kit's `step` (v0.31.0, sha256 = official release binary, statically linked)
  **execs an external `step-kms-plugin`** for `pkcs11:` URIs — with `step-kms-plugin` v0.17.0
  (smallstep/step-kms-plugin release, checksum-verified, CGO + `libpcsclite.so.1`) in `PATH`,
  `step certificate create … --kms pkcs11:… --key pkcs11:…` and `step certificate sign …
  'pkcs11:module-path=…;token=probe;object=probe-ca;type=private?pin-value=…'` both work and the
  result verifies against the root.
- ⚠️ **Kit gap found**: the offline signing kit ships only `step`. Without `step-kms-plugin` in
  `PATH`, the ceremony command fails with `exec: "step-kms-plugin": executable file not found in
  $PATH` (verified). The token ceremony must add the `step-kms-plugin` binary + `libpcsclite1` on
  the signing machine (§5 step 4, §6).
- ⚠️ **URI shape correction**: `step-kms-plugin` rejects a URI with only `module-path` + `object` —
  `Error: kms uri 'token', 'serial' or 'slot-id' are required`. The §5 example must carry
  `token=<label>` (or `serial`/`slot-id`) in addition to `object=` (verified against SoftHSM).
- ⚠️ **usbipd attach works, but not into the dev container**: 2026-11-10 `usbipd attach --wsl --busid
  2-1` from the Windows host exposed the key at WSL kernel level (`lsusb` in the container shows
  `Bus 001 Device 002: ID 04e6:5a11` via `vhci_hcd`), but the container's device cgroup blocks usbfs
  (`open /dev/bus/usb/001/002`: Operation not permitted), so `pcscd` inside the container still sees
  no readers. Run the §4 checks in a **WSL distro shell directly** (where `/dev/bus/usb` exists after
  the attach), not inside the dev container — or pass the device into the container
  (`--device /dev/bus/usb` at container start).
- ✅ **Measured 2026-11-10 — all of §4 passes** on WSL 2 (Ubuntu 26.04) with the key attached through
  `usbipd`: reader claimed, PIV AID `9000`, OpenSC PKCS#11 lists the token as `PIV_II`, AAGUID matches.
  Two corrections came out of it: the PIV AID APDU needs `Lc=0B` (11-byte AID — the original
  diagnostic sent `Lc=08` with 10 bytes and the card rejected it), and the chip is **NXP JCOP**, not the
  Infineon SLE 78 the manual claims. Four WSL-specific blockers had to be cleared first — polkit, a
  missing libccid device-table entry, USB permissions for the `pcscd` user, and the systemd sandbox
  ([01-setup.md](../ca-signing-kit/01-setup.md)).

## 4. Hardware checks — all measured 2026-11-10/11

Run on the **Linux workstation** (not `pve1`), key plugged in:

```sh
sudo apt install pcscd pcsc-tools opensc libpcsclite1 fido2-tools usbutils   # Ubuntu 24.04 names; libfido2-bin on older releases
sudo systemctl start pcscd        # or: sudo service pcscd start   (no systemd in containers)
```

In the WSL2 dev container there is no USB host bus — attach the key from the **Windows host**
first (Windows PowerShell, not WSL): `usbipd list` → `usbipd bind --busid <busid>` →
`usbipd attach --wsl --busid <busid>`; the device then appears under `/dev/bus/usb` in the WSL
**distro** — run the script in a distro shell, not inside the dev container (the container's device
cgroup blocks usbfs; verified 2026-11-10). On a native Linux workstation the key is simply plugged in.

| # | Command | Expected if OK |
|---|---|---|
| 1 | `lsusb \| grep -i 04e6` | Identiv `04e6:5a11` uTrust FIDO2 |
| 2 | `opensc-tool -l` | one CCID reader (**`-r` is `--reader` on OpenSC ≥ 0.23**) |
| 3 | `opensc-tool --name` | driver `PIV-II` |
| 4 | `opensc-tool -s '00a404000ba000000308000010000100'` | SW **`9000`** → PIV applet enabled on this unit. `Lc` must be `0B` — the 11-byte AID, not the 8 the original diagnostic used |
| 5 | `opensc-tool -s '00a4040008a000000151000000' -s '00ca9f7f'` | CPLC — **measured `96 4D … JNET` = NXP JCOP**, not the `40 90` (SLE 78) the manual claims |
| 6 | `pkcs11-tool --module "$(find /usr/lib -name opensc-pkcs11.so \| head -1)" --list-slots` | token listed → **OpenSC PKCS#11 claims it** (the gate for the ceremony) |
| 7 | `fido2-token -L` | AAGUID `73402251-f2a8-4f03-873e-3cb6db604b03` |

**All seven measured 2026-11-10** on the real unit: 1 ✅, 2 ✅ (after the four WSL fixes), 3 ✅
`PIV-II`, 4 ✅ `9000`, 5 ✅ **NXP JCOP** (manual's SLE 78 claim refuted), 6 ✅, 7 ✅.

Windows cross-check **done 2026-11-08**: `certutil -scinfo` lists the PIV card (§3). Still wanted from
Key Manager: the **firmware version** (manual: firmware decides applet enablement).

**The kit's health check is deliberately smaller than this table.** These seven gates were written when
it was unknown whether the device worked at all — they walk up the stack one layer at a time. Once
`pkcs11-tool` answers, every layer below it is proven, so
[`Test-uTrustKey.ps1`](../ca-signing-kit/Test-uTrustKey.ps1) only checks what PKCS#11 cannot tell you:
that `step` and `step-kms-plugin` are in place, and whether a root key already sits in slot 9C.

**Decision rule — resolved 2026-11-10**: the Linux gates pass, so the key is cleared for the adoption
procedure ([runbook 46](../runbooks/46-adopt-utrust-piv-root-custody.md)). The fallback paths in this
section (provision on Windows, or switch to an NFC+ SKU) were not needed.

## 5. Adoption path (decided 2026-11-10, issue #193) — procedure in runbook 46, ceremony not yet run

The diagnostic answer is **yes, with gates**: reissue the root onto the token's PIV slot 9C — key
generated on-card, never in software — rather than importing the existing P-256 root, accepting the
one-time trust rotation (ADR 38 amended on this branch). The executable procedure lives in
[runbook 46](../runbooks/46-adopt-utrust-piv-root-custody.md) with `New-Intermediate.ps1` /
`New-IpaCa.ps1` in the signing kit;
this log keeps only the findings that shape that path:

- **Gates**: all cleared — Windows PIV detection ✅ (`certutil -scinfo`, §3) and Linux checks 1–7 ✅
  (§4). The fallbacks this section once listed (provision on Windows, switch to NFC+) were not needed.
- **Algorithm**: the existing root and the intermediate CSR are both P-256, within the PIV app's
  ECC P-256/P-384 → slot 9C fits either way; reissue is chosen for custody, not because import
  wouldn't fit.
- **Toolchain**: the kit's static `step` v0.31.0 delegates every `pkcs11:` URI to the external CGO
  **`step-kms-plugin`** — add `step-kms-plugin` v0.17.0 (checksum-verified) + `libpcsclite1` to the kit
  (`exec: "step-kms-plugin": not found in $PATH` otherwise). The PKCS#11 sign path was proven
  end-to-end against SoftHSM 2.6 on 2026-11-10 (root created with the key in the module, CSR signed
  via the URI, result verified).
- **Command shape** (verified): every `pkcs11:` URI needs `token=`/`serial=`/`slot-id` besides
  `object=`; root creation is keygen-on-card first (`pkcs11-tool --keypairgen --slot-id 0x9C …`),
  then `step certificate create --kms … --key …` — `create` cannot generate the key itself
  (`getPublicKey failed: key … not found` on a fresh object).
- **Backup**: an on-card-generated root is single-token unless generated in software once and
  imported into a second uTrust during the ceremony (runbook 46's backup note).

## 6. Constraints and risks

- Root token **never** plugged into `pve1` / the `ca` guest (ADR 38 invariant). Air-gap is **not**
  required for the token ceremony — the key is non-exportable, so workstation signing (WSL/Windows) is
  acceptable with the token plugged in only during the ceremony, per-signature PIN, and CSR
  subject/public-key verification on screen before signing (residual: one rogue 1-year intermediate;
  the key itself cannot leak). The **signing machine is the Windows 11 workstation with WSL (Ubuntu)**;
  the kit's scripts are PowerShell 7 and run either inside WSL or on Windows. The **IronKey is
  retired** — transient solution only, destroyed in runbook 46 phase 4; no future IronKey usage.
- OpenSC **does** claim the card on Linux — measured 2026-11-10 as `PIV-II` (§4). The 2023 report of
  `opensc-pkcs11.so` not claiming a uTrust does not apply to this unit. Identiv ships no Linux PKCS#11
  module of its own; Key Manager is Windows-only, which is why the whole ceremony runs through OpenSC.
- `step-ca`'s YubiKey-PIV KMS is YubiKey-specific — the uTrust goes through generic `pkcs11:` URIs only.
- The kit's `step` is static/non-CGO: `pkcs11:` URIs work only with `step-kms-plugin` (CGO, needs
  `libpcsclite1`) present in `PATH`. **That gap is closed** — the plugin is installed in the kit and
  `01-setup.md` documents how to fetch and verify it; `Test-uTrustKey.ps1` reports it missing if it is
  absent.
- Reissue = one-time full trust rotation (runbook 39 distribution, re-sign both sibling CAs, manual
  old-root removal from trust stores — no CRL/OCSP for roots); an on-card-generated root is
  single-token unless imported into a second token during the ceremony (§5 backup note).
- FIDO2 applet remains useful for Authentik WebAuthn passkeys / FIDO2 SSH — orthogonal to CA signing.

## 7. What went wrong getting the key to answer (2026-11-10/11)

Five problems, each producing the **same** symptom — `opensc-tool -l` → `No smart card readers found`.
They are recorded because the symptom is useless on its own: it points at the reader when the cause can
be four layers away. The running fixes live in [01-setup.md](../ca-signing-kit/01-setup.md).

| # | Cause | What the log said | Fix |
|---|---|---|---|
| 1 | **polkit refuses the client** — `pcscd` asks polkit before serving; WSL has no polkit daemon, so every request is denied | `IsClientAuthorized() … NOT authorized for action: access_pcsc` / `Rejected unauthorized PC/SC client` | `PCSCD_ARGS=--disable-polkit` in `/etc/default/pcscd` |
| 2 | **libccid has no entry for this VID/PID** — it matches readers by a table in `Info.plist`, and `04E6:5A11` is absent | `get_driver() Looking for a driver for VID: 0x04E6, PID: 0x5A11` and nothing after it | append the pair to the three parallel arrays with `plistlib` |
| 3 | **the `pcscd` user cannot open the USB device** — the unit runs `User=pcscd`, but `/dev/bus/usb/…` is `root:root` | `Can't libusb_open(1/2): LIBUSB_ERROR_ACCESS` | udev rule: device → group `pcscd`, mode `0660` |
| 4 | **`ProtectSystem=strict` blocks `/dev`** — the sandbox mounts it read-only, so `libusb` cannot open the device even with correct permissions | silence — no error at all, reader simply absent | `ProtectSystem=full` override |
| 5 | **a stray `pcscd` held the interface** — a `--foreground` debug run left in the background | `Can't claim interface 1/3: LIBUSB_ERROR_BUSY` | kill the stray process, then `systemctl restart pcscd` |

Three traps made this slower than it needed to be:

- **`LIBUSB_ERROR_ACCESS` and `LIBUSB_ERROR_BUSY` look like permission problems but are not.** The
  first was the sandbox (fix 4), the second a competing process (fix 5). `fuser -v /dev/bus/usb/…`
  names the holder in one line.
- **`--auto-exit` makes the daemon look broken.** `pcscd` exits after 60 s idle, so `pgrep` finds
  nothing and the next client start races the reader enumeration. `--force-reader-polling` in
  `PCSCD_ARGS` makes it notice the key without a restart after every `usbipd attach`.
- **`usbipd attach` renumbers the device.** The path moved `/dev/bus/usb/001/002` → `…/003` between
  sessions, so a udev rule keyed to a path (rather than VID/PID) silently stops matching.

Two diagnostic assumptions in this document were also wrong, and were corrected by measurement:

- **The PIV AID APDU was malformed.** The original sent `Lc=08` with a 10-byte AID; the card answers
  `Invalid APDU`. The correct AID is the 11-byte `A000000308000010000100` with `Lc=0B`.
- **The chip is not an Infineon SLE 78.** The vendor manual says CPLC `40 90`; the unit reports
  `96 4D … JNET` — an **NXP JCOP** secure element. Irrelevant to the ceremony, so the kit does not
  check the chip at all.

## 8. Current status (2026-11-11)

| | State |
|---|---|
| Key answers over PKCS#11 | ✅ reader `Identiv uTrust FIDO2 Security Key`, driver `PIV-II` |
| PIV applet | ✅ AID select returns `9000` |
| Root in slot 9C | ❌ not created — the token is still blank |
| `Test-uTrustKey.ps1` | ✅ `key PIV_II` · `step 0.31.0` · `root no root key yet` |
| Ceremony | ⏸ not run — `New-Root.ps1` stops at step 1 |

**Open item blocking the ceremony:** the script's step 1 calls `piv-tool --admin-mode -k`, which **does
not exist** in this OpenSC build (`piv-tool --admin <arg>` is the authentication flag; there is no
change-PIN/change-PUK option). The factory PIN `123456` and PUK `12345678` are published in the vendor
manual, so the root must not be created until they are replaced — the change has to be made with
`pkcs11-tool --change-pin` / `--set-pin`, and the exact invocation is still to be settled.

## References

- `uTrust_FIDO2_Technical_Manual.pdf` (Identiv/Hirsch) — PIV app, slots, policies, defaults, AAGUID
  (uploaded during this diagnostic). Its **CPLC/SLE 78 claim is refuted** for this unit — see §7.
- `uTrust-FIDO2-NFC-Security-Keys-DS.pdf` rev 2021-08-02 — P/N 905601/905602, PIV in secure-element interface (uploaded during this diagnostic)
- [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) — three-tier PKI, root custody (amended 2026-11-10 on this branch: uTrust PIV slot 9C, root **reissued** — issue #193)
- [research 36 §4–§5](36-step-ca-machine-identity.md) — KMS/custody paths; `step-kms-plugin` (CGO, `libpcsclite1`) needed for `pkcs11:` on the signing machine
- [runbook 35 §6–§7](../runbooks/35-deploy-step-ca.md) — CSR emission from the TPM key; `ca.json` `tpmkms`
- [runbook 36](../runbooks/36-private-ca-init.md) — the IronKey ceremony · [runbook 46](../runbooks/46-adopt-utrust-piv-root-custody.md) — the adoption procedure this diagnostic feeds · [signing kit](../ca-signing-kit/README.md) + [`Test-uTrustKey.ps1`](../ca-signing-kit/Test-uTrustKey.ps1) + [`New-Intermediate.ps1`](../ca-signing-kit/New-Intermediate.ps1) — health check and token signing
- [runbook 39](../runbooks/39-trust-private-ca.md) — root distribution to fleet + workstations (reissue step 4)
