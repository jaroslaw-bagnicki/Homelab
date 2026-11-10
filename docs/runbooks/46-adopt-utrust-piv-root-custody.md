# Private CA — adopt the uTrust FIDO2 NFC token as offline root custody (reissue + trust rotation)

> **Status: hardware gates cleared 2026-11-10; the ceremony itself has not run yet.** The key answers
> over PKCS#11 (`PIV_II`), so [research 54 §4](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md)
> is complete and `Test-uTrustKey.ps1` reports the key ready with no root in slot 9C. Getting there
> needed four WSL fixes, all in [01-setup.md](../ca-signing-kit/01-setup.md).
>
> Move the 10-year **root** from the IronKey key file onto the **uTrust FIDO2 NFC USB-A (P/N 905601),
> PIV applet slot 9C**, by **reissuing** it: the new root key is generated on the token and never
> exists in software. This is a one-time **trust rotation** — new root to every client, both sibling
> CAs re-signed, old root removed by hand — decided 2026-11-10 in
> [issue #193](https://github.com/jaroslaw-bagnicki/Homelab/issues/193); [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)
> is amended accordingly. Diagnostic evidence: [research 54](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md).
>
> ⚠ **The token never touches `pve1` / the `ca` guest.** Signing runs on the **Windows 11 workstation
> with WSL (Ubuntu)**, where the token is attached via `usbipd`; the token is unplugged and back in the
> safe outside ceremonies. **No air-gap is required** — the key is non-exportable, so the worst case is
> one rogue certificate signed while the token is plugged in and the PIN entered, not a stolen root.
> The live CA is untouched: `ca.json` on the `ca` guest keeps `tpmkms`.

## Why

ADR 38 keeps the root on an IronKey — a passphrase-protected key *file*; every copy is exportable if
the passphrase leaks. The uTrust's PIV applet (confirmed on the actual unit: `certutil -scinfo` →
`Identity Device (NIST SP 800-73 [PIV])`) can hold the root in slot 9C with PIN required immediately
before **each** signature, and the key is non-exportable. Reissue (not import) means the root key
never exists in software at all; the cost is the one-time root redistribution the original ADR 38
text rejected — accepted deliberately in #193. The FIDO2 applet cannot serve (no import,
protocol-bound signatures — research 54 §1); FIDO2 passkeys for Authentik/SSH stay orthogonal.

## Prerequisites

- [x] `docs/ca-signing-kit/Test-uTrustKey.ps1` run on the signing machine with the token attached —
      **passes 2026-11-10**: the key answers over PKCS#11 as `PIV_II`, PIV AID select returns `9000`,
      AAGUID `73402251-f2a8-4f03-873e-3cb6db604b03`. The chip is **NXP JCOP** (CPLC `96 4D … JNET`),
      not the Infineon SLE 78 the vendor manual claims — irrelevant to the ceremony, so the kit does
      not check it
- [ ] Firmware version read from uTrust Key Manager on Windows (the manual: firmware decides applet
      enablement) — record it in research 54 §3
- [ ] Signing host: the **Windows 11 workstation** with WSL (Ubuntu) and the token attached from
      Windows (`usbipd bind --busid <busid>` + `usbipd attach --wsl --busid <busid>`), `pcscd` running
      and `opensc`, `pcsc-tools`, `libpcsclite1`, `fido2-tools`, `usbutils` installed. The kit's
      scripts are PowerShell 7 and run either inside WSL or on Windows — both drive the same WSL
      toolchain. Fallback: Windows native — OpenSC's Windows PKCS#11 DLL with a Windows `step` +
      `step-kms-plugin`, or `certreq -sign` via the Microsoft PIV minidriver (note: `certreq` applies
      no template — check the issued extensions by hand)
- [ ] Signing kit copied to a real filesystem inside WSL (not a USB stick — FAT/exFAT has no executable
      bit), plus two added binaries: the kit's stock static `step` v0.31.0 and the CGO
      **`step-kms-plugin` v0.17.0** (smallstep/step-kms-plugin release, verify against `checksums.txt`)
      — `step` delegates every `pkcs11:` URI to the plugin; without it:
      `exec: "step-kms-plugin": not found in $PATH` (verified 2026-11-10; the whole PKCS#11 path was
      proven end-to-end against SoftHSM 2.6). See [01-setup.md](../ca-signing-kit/01-setup.md)
- [ ] The uTrust token, the current `root_ca.crt` (public, from the kit), `intermediate_ca.csr`
      (from runbook 35 §6), `intermediate-ca.tpl`, and `ipa.csr` when the FreeIPA CA is re-signed
- [ ] A safe for the token; the written-down IronKey passphrase still available until phase 5 finishes

## Phase 0 — pre-flight health check

```sh
./Test-uTrustKey.ps1        # read-only, no PIN login
```

Expected on a key with no root yet:

```
  key    PIV_II
  step   Smallstep CLI/0.31.0 (linux/amd64)
  root   no root key yet — New-Root.ps1 will create it
```

If the key does not answer over PKCS#11 at all, do not improvise — [01-setup.md](../ca-signing-kit/01-setup.md)
lists the four things that block it on WSL and how to tell them apart from the daemon log.

## Phase 1 — change the factory defaults on the token

Factory defaults (technical manual): PIV PIN `123456`, PUK `12345678`, management key (3DES)
`010203…0708`. Change all three **before** anything else, on the signing machine with OpenSC:

```sh
MOD=/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so
piv-tool --admin-mode -k   # or: pkcs11-tool --module $MOD --change-pin / --set-pin ...
```

Record the new PIN/PUK in the safe (never in the repo). Do not log the management key anywhere.

## Phase 2 — reissue the root on the token (slot 9C)

Run the kit's [`New-Root.ps1`](../ca-signing-kit/New-Root.ps1) — it replaces the factory
credentials, generates the key on the card, writes the self-signed root, verifies its shape and proves
the token can sign. The full walkthrough is [02-root.md](../ca-signing-kit/02-root.md).

```sh
./New-Root.ps1
```

The key is generated **on the card**; `step certificate create` only uses an existing on-token key
(pointed at a fresh `object=` it fails `getPublicKey failed: key … not found` — verified), which is
why the script generates the pair with `pkcs11-tool` first.

- [ ] The script's shape checks all read OK — `CN=Homelab Internal CA`, P-256, `CA:TRUE, pathlen:1`,
      certSign+crlSign, 10 years
- [ ] The script's probe signature chains to the new root (it signs a throwaway CSR and discards it)
- [ ] The fingerprint it prints is recorded **outside the repo** (safe, password manager)

The PIN prompt per signature is the ceremony behaviour wanted for a root (slot 9C, cardholder
participation). Never put `pin-value=` in a URI, script, Ansible or the repo.

## Phase 3 — sign the sibling CAs with the token

```sh
./New-Intermediate.ps1     # intermediate_ca.csr -> intermediate_ca.crt
./New-IpaCa.ps1            # FreeIPA CA — ipa.csr -> ipa-ca.crt (ADR 42)
```

Both machine-check the result (chains to root, `is_ca`, `pathlen:0`, key usage, SANs for the
intermediate, validity) and discard anything that fails. Details:
[03-sign.md](../ca-signing-kit/03-sign.md).

Carry back only the public certificates: `root_ca.crt`, `intermediate_ca.crt`, `ipa-ca.crt`.

## Phase 4 — trust rotation (the accepted cost of reissue)

1. Distribute the **new** `root_ca.crt` to the fleet and workstations — [runbook 39](39-trust-private-ca.md)
   (`ca_trust` role on the connected controller, manual procedure for personal devices); publish it to
   Key Vault as `ca-root-cert` from the controller. Clients now **dual-trust** old + new root.
2. Re-sign both sibling CAs under the new root (phase 3) and install them: the step-ca intermediate by
   [runbook 35 §7](35-deploy-step-ca.md), the FreeIPA/Dogtag CA by [runbook 41](41-deploy-freeipa-server.md)
   ([ADR 42](../decisions/42-pki-topology-sibling-cas.md)). `ca.json` on the `ca` guest does **not** change.
3. Verify fleet-wide that everything chains to the new root (e.g. `step certificate verify` on a leaf
   per node, `update-ca-certificates` output on Linux nodes).
4. Once nothing chains to the old root: **remove the old root from every trust store by hand** — no
   CRL/OCSP covers roots (ADR 38) — and only then **destroy the IronKey `root_ca_key` file and every
   backup copy**, last. This **retires the IronKey completely** — it was a transient solution with no
   future usage: [runbook 36](36-private-ca-init.md) and the former stick flow are retired with it, and
   the offline signing kit is token-only from now on.

## Backup token

An on-card-generated root has no exportable copy — single token, and token loss = another reissue.
To keep a backup, generate the new root key in software **once** on the air-gapped kit, import it into
**two** uTrust keys (slot 9C), then destroy the software file immediately; the rest of this runbook is
unchanged. Decide before phase 2 and record the choice in research 54.

## Constraints and invariants

- The token is **never** plugged into `pve1` / the `ca` guest (ADR 38: root not reachable by a server
  compromise); workstation signing only with the token unplugged outside ceremonies.
- **No air-gap is required for the token ceremony.** The key is non-exportable, so the residual risk is
  one rogue certificate signed while the token is plugged in, bounded by the per-signature PIN and the
  on-screen CSR check. Verify the CSR's subject and public key on screen before every signing run —
  the kit's scripts print it for exactly this reason. (The **IronKey** ceremony stayed air-gapped
  until retired.)
- No PIN, PUK, management key or `pin-value=` in scripts, Ansible, logs or the repo — PC/SC prompts per
  signature.
- OpenSC must claim the card on Linux (check 6); Identiv ships no Linux PKCS#11 module of its own and
  Key Manager is Windows-only — provisioning/signing on Linux goes through generic `pkcs11:` URIs.

## Abort criteria

- Any `Test-uTrustKey.ps1` gate fails → stop before phase 1; nothing has been written to the token yet.
- Phase 2 verification fails → the token can be reset and phase 2 retried; no client has trusted
  anything yet.
- Phase 4 step 3 shows any node still on the old root after cutover → fix that node before removing the
  old root; never remove the old root while anything still chains to it.

## References

- [research 54](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md) — the diagnostic: capabilities, gates, verified command shapes
- [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) — amended 2026-11-10: uTrust PIV slot 9C, root reissued
- [issue #193](https://github.com/jaroslaw-bagnicki/Homelab/issues/193) — adoption tracking
- [runbook 36](36-private-ca-init.md) — 🪦 retired IronKey/stick ceremony this replaces · [runbook 35 §6–§7](35-deploy-step-ca.md) — CSR + install · [runbook 39](39-trust-private-ca.md) — root distribution · [runbook 41](41-deploy-freeipa-server.md) — FreeIPA CA
- [signing kit](../ca-signing-kit/README.md) — `Test-uTrustKey.ps1`, `New-Root.ps1`, `New-Intermediate.ps1`, `New-IpaCa.ps1`, `step` + `step-kms-plugin`
- [research 36 §4–§5](../research/36-step-ca-machine-identity.md) — KMS/custody paths, `step-kms-plugin` requirement
