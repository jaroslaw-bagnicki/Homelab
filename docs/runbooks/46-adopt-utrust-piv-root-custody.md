# Private CA — adopt the uTrust FIDO2 NFC token as offline root custody (reissue + trust rotation)

> **Status: authored, NOT yet executed (2026-11-10).** The hardware gates are still pending — run
> [research 54 §4](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md) first and do not start this
> runbook until `check-utrust.sh` passes checks 4 (PIV AID `9000`) and 6 (OpenSC PKCS#11 lists the token).
>
> Move the 10-year **root** from the IronKey key file onto the **uTrust FIDO2 NFC USB-A (P/N 905601),
> PIV applet slot 9C**, by **reissuing** it: the new root key is generated on the token and never
> exists in software. This is a one-time **trust rotation** — new root to every client, both sibling
> CAs re-signed, old root removed by hand — decided 2026-11-10 in
> [issue #193](https://github.com/jaroslaw-bagnicki/Homelab/issues/193); [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)
> is amended accordingly. Diagnostic evidence: [research 54](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md).
>
> ⚠ **The ceremony never touches the network, and the token never touches `pve1` / the `ca` guest.**
> Signing runs on an air-gapped signing machine (live-USB Linux, same discipline as
> [runbook 36](36-private-ca-init.md)) with the token plugged in; the token is unplugged and back in
> the safe outside ceremonies. The live CA is untouched: `ca.json` on the `ca` guest keeps `tpmkms`.

## Why

ADR 38 keeps the root on an IronKey — a passphrase-protected key *file*; every copy is exportable if
the passphrase leaks. The uTrust's PIV applet (confirmed on the actual unit: `certutil -scinfo` →
`Identity Device (NIST SP 800-73 [PIV])`) can hold the root in slot 9C with PIN required immediately
before **each** signature, and the key is non-exportable. Reissue (not import) means the root key
never exists in software at all; the cost is the one-time root redistribution the original ADR 38
text rejected — accepted deliberately in #193. The FIDO2 applet cannot serve (no import,
protocol-bound signatures — research 54 §1); FIDO2 passkeys for Authentik/SSH stay orthogonal.

## Prerequisites

- [ ] `docs/private-ca-offline-signing/check-utrust.sh` run on the signing machine with the token
      attached — checks 1–7 pass: USB `04e6:5a11`, one CCID reader, driver `PIV-II`, PIV AID select
      `9000`, CPLC `40 90` (SLE 78) + serial, `pkcs11-tool --module opensc-pkcs11.so --list-slots`
      lists the token, `fido2-token -L` AAGUID `73402251-f2a8-4f03-873e-3cb6db604b03`
      (decision rule: research 54 §4)
- [ ] Firmware version read from uTrust Key Manager on Windows (the manual: firmware decides applet
      enablement) — record it in research 54 §3
- [ ] Signing host: the **workstation**. Primary: a WSL distro on it (not the dev container — its
      device cgroup blocks usbfs, research 54 §3) with the token attached from Windows
      (`usbipd bind --busid <busid>` + `usbipd attach --wsl --busid <busid>`), `pcscd` running and
      `opensc`, `pcsc-tools`, `libpcsclite1`, `fido2-tools`, `usbutils` installed. Fallback: Windows
      native — OpenSC's Windows PKCS#11 DLL with a Windows `step` + `step-kms-plugin`, or
      `certreq -sign` via the Microsoft PIV minidriver (note: `certreq` applies no template — check
      the issued extensions by hand)
- [ ] Offline signing kit copied to `/tmp` on the signing machine, plus two added binaries:
      the kit's stock static `step` v0.31.0 and the CGO **`step-kms-plugin` v0.17.0**
      (smallstep/step-kms-plugin release, verify against `checksums.txt`) on `PATH` — `step` delegates
      every `pkcs11:` URI to the plugin; without it: `exec: "step-kms-plugin": not found in $PATH`
      (verified 2026-11-10; the whole PKCS#11 path was proven end-to-end against SoftHSM 2.6)
- [ ] The uTrust token, the current `root_ca.crt` (public, from the kit), `intermediate_ca.csr`
      (from runbook 35 §6), `intermediate-ca.tpl`, and `ipa.csr` when the FreeIPA CA is re-signed
- [ ] A safe for the token; the written-down IronKey passphrase still available until phase 5 finishes

## Phase 0 — pre-flight health check

```sh
bash check-utrust.sh        # all seven checks from research 54 §4, read-only, no PIN login
```

All pass → proceed. Check 4 fails → this unit's firmware has PIV disabled for OpenSC; provision/sign
on Windows via uTrust Key Manager instead, or switch to an NFC+ SKU (research 54 §2). Check 6 fails
but 4 passes → OpenSC won't drive it on Linux; do not improvise — same fallback.

## Phase 1 — change the factory defaults on the token

Factory defaults (technical manual): PIV PIN `123456`, PUK `12345678`, management key (3DES)
`010203…0708`. Change all three **before** anything else, on the signing machine with OpenSC:

```sh
MOD=/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so
piv-tool --admin-mode -k   # or: pkcs11-tool --module $MOD --change-pin / --set-pin ...
```

Record the new PIN/PUK in the safe (never in the repo). Do not log the management key anywhere.

## Phase 2 — reissue the root on the token (slot 9C)

The key is generated **on the card**; `step certificate create` only uses an existing on-token key
(pointed at a fresh `object=` it fails `getPublicKey failed: key … not found` — verified), so:

```sh
MOD=/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so
TOKEN='<token label from pkcs11-tool --list-slots>'

# 2a. P-256 key pair in PIV slot 9C; PIN policy "always" is fixed at generation (manual);
#     --login prompts for the PIV PIN — never pin-value
pkcs11-tool --module "$MOD" --keypairgen --key-type EC:prime256v1 \
  --slot-id 0x9C --label "Homelab Root CA" --login

# 2b. self-signed 10-year root cert over that on-token key (URI must carry token= — verified)
./step certificate create "Homelab Internal CA" root_ca.crt --profile root-ca --not-after 87600h \
  --kms "pkcs11:module-path=$MOD;token=$TOKEN" \
  --key "pkcs11:module-path=$MOD;token=$TOKEN;object=Homelab Root CA;type=private"
```

- [ ] `./step certificate inspect root_ca.crt` — `CN=Homelab Internal CA`, P-256, `CA:TRUE, pathlen:1`,
      certSign+crlSign, 10 years
- [ ] `./step certificate fingerprint root_ca.crt` — record the fingerprint **outside the repo** (safe,
      password manager)
- [ ] Test-sign a throwaway CSR with the token, verify it chains to the new root, then discard it:

  ```sh
  ./step certificate sign --not-after 24h probe.csr root_ca.crt \
    "pkcs11:module-path=$MOD;token=$TOKEN;object=Homelab Root CA;type=private" > probe.crt
  ./step certificate verify probe.crt --roots root_ca.crt   # PIN is prompted — per signature
  ```

The PIN prompt per signature is the ceremony behaviour wanted for a root (slot 9C, cardholder
participation). Never put `pin-value=` in a URI, script, Ansible or the repo.

## Phase 3 — sign the sibling CAs with the token

Use the kit's new [`sign-piv.sh`](../private-ca-offline-signing/sign-piv.sh) — the `sign.sh` delta:
same air-gap refusal and same machine checks (chains to root, `is_ca`, `pathlen:0`, SANs
`ca.internal` + `192.168.2.215`, 1 year), but the key argument is the PKCS#11 URI above instead of
`$STICK/root_ca_key`. Run it on the air-gapped signing machine with the token plugged in:

```sh
./sign-piv.sh                  # signs intermediate_ca.csr -> intermediate_ca.crt
./sign-ipa-ca.sh               # FreeIPA CA — same delta, ipa.csr -> ipa-ca.crt (ADR 42)
```

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
   backup copy**, last.

## Backup token

An on-card-generated root has no exportable copy — single token, and token loss = another reissue.
To keep a backup, generate the new root key in software **once** on the air-gapped kit, import it into
**two** uTrust keys (slot 9C), then destroy the software file immediately; the rest of this runbook is
unchanged. Decide before phase 2 and record the choice in research 54.

## Constraints and invariants

- The token is **never** plugged into `pve1` / the `ca` guest (ADR 38: root not reachable by a server
  compromise); workstation signing only with the token unplugged outside ceremonies.
- No air-gap for the **token** ceremony (the key is non-exportable — the residual risk is one rogue
  1-year intermediate signed while the token is plugged in, bounded by the per-signature PIN and the
  on-screen CSR check). The **IronKey** ceremony stays air-gapped until retired. Verify the CSR's
  subject and public key on screen before every signing run.
- No PIN, PUK, management key or `pin-value=` in scripts, Ansible, logs or the repo — PC/SC prompts per
  signature.
- OpenSC must claim the card on Linux (check 6); Identiv ships no Linux PKCS#11 module of its own and
  Key Manager is Windows-only — provisioning/signing on Linux goes through generic `pkcs11:` URIs.

## Abort criteria

- Any `check-utrust.sh` gate fails → stop before phase 1; nothing has been written to the token yet.
- Phase 2 verification fails → the token can be reset and phase 2 retried; no client has trusted
  anything yet.
- Phase 4 step 3 shows any node still on the old root after cutover → fix that node before removing the
  old root; never remove the old root while anything still chains to it.

## References

- [research 54](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md) — the diagnostic: capabilities, gates, verified command shapes
- [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) — amended 2026-11-10: uTrust PIV slot 9C, root reissued
- [issue #193](https://github.com/jaroslaw-bagnicki/Homelab/issues/193) — adoption tracking
- [runbook 36](36-private-ca-init.md) — the IronKey ceremony this replaces · [runbook 35 §6–§7](35-deploy-step-ca.md) — CSR + install · [runbook 39](39-trust-private-ca.md) — root distribution · [runbook 41](41-deploy-freeipa-server.md) — FreeIPA CA
- [offline signing kit](../private-ca-offline-signing/README.md) — `check-utrust.sh`, `sign-piv.sh`, `step` + `step-kms-plugin`
- [research 36 §4–§5](../research/36-step-ca-machine-identity.md) — KMS/custody paths, `step-kms-plugin` requirement
