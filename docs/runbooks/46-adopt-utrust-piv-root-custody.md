# Private CA — adopt a uTrust FIDO2 NFC+ token as offline root custody (reissue + trust rotation)

> **Status: deferred — the IronKey remains custody.** The plain-NFC **905601 is rejected (2026-11-14)**: its
> PIV applet answers AID select but cannot generate a key, has none of the mandatory SP 800-73 data
> objects, and offers no working admin path ([research 54 §9](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md)).
> Nothing here is scheduled: the IronKey stays the root custody ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md),
> amended 2026-11-14) and the [IronKey kit](../ca-signing-kit/v1-ironkey/README.md) is the active one.
> **Run this runbook when a uTrust FIDO2 NFC+** (or a YubiKey 5) arrives — the procedure itself is
> unchanged, only the token model and the timing.
>
> Move the 10-year **root** from the IronKey key file onto a **uTrust FIDO2 NFC+**, PIV applet slot 9C,
> by **reissuing** it: the new root key is generated on the token and never
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
the passphrase leaks. A PIV token can hold the root in slot 9C with PIN required immediately
before **each** signature, and the key is non-exportable. Reissue (not import) means the root key
never exists in software at all; the cost is the one-time root redistribution the original ADR 38
text rejected — accepted deliberately in #193. The FIDO2 applet cannot serve (no import,
protocol-bound signatures — research 54 §1); FIDO2 passkeys for Authentik/SSH stay orthogonal.

**Why the NFC+ and not the plain NFC (905601).** The 905601 was trialled and rejected on 2026-11-14.
It enumerates as a PIV card — AID select `9000`, `certutil -scinfo` sees it, PKCS#11 lists `PIV_II` —
but that is where it stops: no Card Capability Container, no CHUID, `GENERATE KEY PAIR` → `6982` on
every slot, and a management-key handshake that returns `9000` to a wrong response. No key can be
created on it ([research 54 §9](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md)). The vendor's
Key Manager matrix agrees — PIV is ticked for `NFC+` and `GOV` only.

## Prerequisites

- [ ] **A token whose PIV applet actually works** — uTrust FIDO2 NFC+ (preferred) or YubiKey 5. The
      plain-NFC 905601 is rejected (§Why). Verify with the gate in phase 0 before going further
- [ ] `docs/ca-signing-kit/v2-utrust-token/Test-uTrustKey.ps1` run on the signing machine with the token attached —
      must pass **including the `CCC` gate**: a `6A82` on `5FC107` means the applet is a stub and no
      ceremony can succeed, whatever else answers. AAGUID `73402251-f2a8-4f03-873e-3cb6db604b03` is
      the family value for both NFC and NFC+
- [ ] Firmware version read from uTrust Key Manager on Windows (the manual: firmware decides applet
      enablement) — record it in research 54 §3
- [ ] Signing host: the **Windows 11 workstation** with WSL (Ubuntu) and the token attached from
      Windows (`usbipd bind --busid <busid>` + `usbipd attach --wsl --busid <busid>`), `pcscd` running
      and `opensc`, `pcsc-tools`, `libpcsclite1`, `fido2-tools`, `usbutils` installed. The kit's
      scripts are PowerShell 7 and **run only inside WSL** — they reject native Windows via `$IsLinux`
      and hard-code the Linux OpenSC module path. Windows does one thing only: `usbipd` hands the token
      to WSL. There is no Windows-native path.
- [ ] Signing kit copied to a real filesystem inside WSL (not a USB stick — FAT/exFAT has no executable
      bit), plus two added binaries: the kit's stock static `step` v0.31.0 and the CGO
      **`step-kms-plugin` v0.17.0** (smallstep/step-kms-plugin release, verify against `checksums.txt`)
      — `step` delegates every `pkcs11:` URI to the plugin; without it:
      `exec: "step-kms-plugin": not found in $PATH` (verified 2026-11-10; the whole PKCS#11 path was
      proven end-to-end against SoftHSM 2.6). See [01-setup.md](../ca-signing-kit/v2-utrust-token/01-setup.md)
- [ ] The uTrust token, `intermediate_ca.csr` (from runbook 35 §6), `intermediate-ca.tpl`, and
      `ipa.csr` when the FreeIPA CA is re-signed
- [ ] **The current `root_ca.crt` staged OUTSIDE the kit** — `New-Root.ps1` refuses to run while
      `root_ca.crt` exists in the kit directory (it guards against an accidental second root). Move the
      old public root somewhere safe first: you need it for dual-trust during the rotation, and the
      script writes the replacement to that same path
- [ ] A safe for the token; the written-down IronKey passphrase still available until phase 5 finishes

## Phase 0 — pre-flight health check

```sh
pwsh ./Test-uTrustKey.ps1        # read-only, no PIN login
```

Expected on a usable token with no root yet:

```
  key    PIV_II
  applet CCC 5FC107 present
  step   Smallstep CLI/0.31.0 (linux/amd64)
  root   no root key yet — New-Root.ps1 will create it
```

**If the `applet` line reports the CCC missing, stop.** The token enumerates but cannot hold a key —
this is the 905601 failure mode. No amount of PIN, PUK or management-key work will change it; return
the token and get an NFC+ ([research 54 §9](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md)).

If the key does not answer over PKCS#11 at all, do not improvise — [01-setup.md](../ca-signing-kit/v2-utrust-token/01-setup.md)
lists the four things that block it on WSL and how to tell them apart from the daemon log.

## Phase 1 — change the factory defaults on the token

Factory defaults (technical manual): PIV PIN `123456`, PUK `12345678`, management key (3DES)
`010203…0708`. Change all three **before** anything else, on the signing machine with OpenSC:

```sh
MOD=/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so
pkcs11-tool --module $MOD --change-pin          # interactive: old PIN, then new twice
pkcs15-tool --change-puk                        # interactive: old PUK, then new twice
pkcs11-tool --module $MOD --login --login-type so --change-pin   # management key (SO PIN)
```

Each command prompts for the values — never pass a PIN/PUK on the command line or store one in a
script. Confirm each succeeded before continuing; a silent failure here leaves the root protected by a
published secret.

> **On the 905601 this phase cannot run at all** — `CHANGE REFERENCE DATA` returns `6983` and there is
> no PUK keyref (`6A88`). That is the stub applet again, not a credential problem.

Record the new PIN/PUK in the safe (never in the repo). Do not log the management key anywhere.

## Phase 2 — reissue the root on the token (slot 9C)

Run the kit's [`New-Root.ps1`](../ca-signing-kit/v2-utrust-token/New-Root.ps1) — it replaces the factory
credentials, generates the key on the card, writes the self-signed root, verifies its shape and proves
the token can sign. The full walkthrough is [02-root.md](../ca-signing-kit/v2-utrust-token/02-root.md).

```sh
pwsh ./New-Root.ps1
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
pwsh ./New-Intermediate.ps1     # intermediate_ca.csr -> intermediate_ca.crt
pwsh ./New-IpaCa.ps1            # FreeIPA CA — ipa.csr -> ipa-ca.crt (ADR 42)
```

Both machine-check the result (chains to root, `is_ca`, `pathlen:0`, key usage, SANs for the
intermediate, validity) and discard anything that fails. Details:
[03-sign.md](../ca-signing-kit/v2-utrust-token/03-sign.md).

Carry back only the public certificates: `root_ca.crt`, `intermediate_ca.crt`, `ipa-ca.crt`.

## Phase 4 — trust rotation (the accepted cost of reissue)

> ⚠ **Prerequisite — `ca_trust` cannot do dual-trust as it stands.** The role reads **one** Key Vault
> secret (`ca-root-cert`), asserts it against **one** pinned fingerprint (`ca_trust_root_sha256`), and
> writes **one** fixed path (`/usr/local/share/ca-certificates/homelab-root-ca.crt`). Publishing the new
> root therefore either fails the old pin or overwrites the old anchor — there is no window where a node
> trusts both. **Before starting this phase**, extend the role to carry a second anchor (a
> `ca_trust_previous_*` set: secret name, pin, and a distinct filename), so step 1 can publish both and
> step 4 removes one. That role change is its own reviewed change, not part of this runbook.

1. Distribute the **new** `root_ca.crt` to the fleet and workstations — [runbook 39](39-trust-private-ca.md)
   (`ca_trust` role on the connected controller, manual procedure for personal devices); publish it to
   Key Vault as `ca-root-cert` from the controller. With the dual-anchor change above in place, clients
   now **dual-trust** old + new root.
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
- [signing kit](../ca-signing-kit/v2-utrust-token/README.md) — `Test-uTrustKey.ps1`, `New-Root.ps1`, `New-Intermediate.ps1`, `New-IpaCa.ps1`, `step` + `step-kms-plugin`
- [research 36 §4–§5](../research/36-step-ca-machine-identity.md) — KMS/custody paths, `step-kms-plugin` requirement
