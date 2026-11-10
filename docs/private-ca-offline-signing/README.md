# Private CA — signing kit for the uTrust Security Key

The root CA's private key lives **inside the uTrust FIDO2 NFC Security Key** (PIV slot 9C) and cannot
be exported. This kit is how you use it: create the root once, then sign the CAs that sit under it.

**Terminology:** "the security key" always means the **physical uTrust USB device**. The word "token"
appears only inside PKCS#11 URIs (`token=<label>`), where it is the standard's name for the card's
slot — it is the same device, not something separate.

Nothing here needs an air-gapped machine. The key cannot leave the security key, so the worst case on a
networked workstation is one rogue certificate signed while the security key is plugged in and the PIN
is entered — not a stolen root. The security key is unplugged outside ceremonies.

## The mental model

```
root key  ── lives in the security key, never leaves it, PIN per signature
   │
   ├── signs ── step-ca intermediate   (1 year, key in pve1's TPM)   ← re-signed annually
   └── signs ── FreeIPA CA             (5 years, key on the IPA guest)
```

Two things follow from that picture, and they explain the whole kit:

- **Creating the root happens once, ever.** Replacing a root is a trust rotation — every client
  re-trusts, both CAs are re-signed, the old root is removed by hand. There is no "re-run".
- **Signing the CAs is the repeating job.** That is the annual ceremony, and it is what the scripts
  are mostly for.

## The scripts

| Script | What it does | How often |
|---|---|---|
| [`Test-Token.ps1`](Test-Token.ps1) | Read-only health check: USB, reader, PIV applet, chip, PKCS#11, FIDO2 AAGUID, tooling. Enters no PIN, writes nothing to the card. | before every ceremony |
| [`New-Root.ps1`](New-Root.ps1) | Creates the 10-year root on the security key: replaces factory credentials, generates the key in slot 9C, writes and verifies the certificate, proves it can sign. | **once, ever** |
| [`New-Intermediate.ps1`](New-Intermediate.ps1) | Signs `intermediate_ca.csr` → `intermediate_ca.crt`, then machine-checks the result. | every year |
| [`New-IpaCa.ps1`](New-IpaCa.ps1) | Signs `ipa.csr` → `ipa-ca.crt`, then machine-checks the result. | when the FreeIPA CA is built or re-signed |

Every script does the same three things: **check the inputs**, **do the one operation**, **verify the
result before letting you keep it**. A failed check leaves the previous certificate untouched and
discards the bad one, so nothing unfit to install is ever carried away.

## Where it runs

**Inside WSL (Ubuntu), on the Windows 11 workstation.** The key, `pcscd`, OpenSC and `step` all live
there, so the scripts run there too — no cross-boundary indirection.

```sh
wsl
cd ~/ca-kit
pwsh ./Test-Token.ps1
```

The scripts refuse to run anywhere else, because the key is not reachable from anywhere else. See
[01-setup.md](01-setup.md).

## The flow

1. **Set up** — [01-setup.md](01-setup.md). Install the tooling in WSL, put `step` and
   `step-kms-plugin` in the kit, attach the security key. Do this once.
2. **Check the security key** — `./Test-Token.ps1`. All checks must pass.
3. **Create the root** — `./New-Root.ps1`, **once ever** — [02-root.md](02-root.md).
4. **Sign the intermediate** — `./New-Intermediate.ps1` — [03-sign.md](03-sign.md). This is the
   repeating ceremony, annual re-sign included.
5. **Sign the FreeIPA CA** — `./New-IpaCa.ps1`, when M1 needs it — [03-sign.md](03-sign.md).
6. **Carry back the public certificates** and put the security key in the safe.

## What you carry back

All public — none of it is secret:

| File | Installed by |
|---|---|
| `root_ca.crt` | [runbook 39](../runbooks/39-trust-private-ca.md) — the trust anchor for the fleet and workstations |
| `intermediate_ca.crt` | [runbook 35 §7](../runbooks/35-deploy-step-ca.md) — the CA serving LAN TLS |
| `ipa-ca.crt` | [runbook 41](../runbooks/41-deploy-freeipa-server.md) — the FreeIPA CA |

## Rules

1. **The root key never exists outside the security key.** There is no key file to copy, back up or destroy.
   Never plug the security key into `pve1` or the `ca` guest — a server compromise must not reach the root.
2. **No PIN, PUK, management key or `pin-value=` in any script, log or the repository.** PC/SC prompts
   for the PIN immediately before each signature; that prompt is the whole security model.
3. **Write the PIV PIN and PUK down before the first ceremony** and keep them in the safe. They are
   the only way back into the security key — lose them and the root is dead.
4. **Never sign with `--profile intermediate-ca`.** A profile rebuilds the certificate from its own
   defaults and silently drops the SANs, which are the CA's declared identity shape. The scripts use
   `--template` and check the SANs afterwards.
5. **`New-Root.ps1` runs once, ever.** The repeating job is `New-Intermediate.ps1`.
6. **Look at the CSR on screen before signing.** The scripts print it. That is the guard against
   signing a request that is not the one the CA host produced.

## Files

| File | Notes |
|---|---|
| `intermediate-ca.tpl` | signing template for the step-ca intermediate — a copy of the versioned source in `ansible/workloads/step-ca/files/`; change both or neither |
| `ipa-ca.tpl` | signing template for the FreeIPA CA |
| `step` | the `step` CLI — **not in git**, added by [01-setup.md](01-setup.md) |
| `step-kms-plugin` | the CGO PKCS#11 plugin — **not in git**, added by [01-setup.md](01-setup.md) |
| `intermediate_ca.csr` | produced on the CA host by the key in `pve1`'s TPM ([runbook 35 §6](../runbooks/35-deploy-step-ca.md)) — **not in git**, bring the file |
| `ipa.csr` | produced on the IPA guest by `ipa-server-install --external-ca` — **not in git**, bring the file |
| `root_ca.crt`, `intermediate_ca.crt`, `ipa-ca.crt` | ceremony output — **not in git** |

## If something goes wrong

| Symptom | What to do |
|---|---|
| `step` fails with `Permission denied` | You are running the kit straight off a USB stick. FAT32, exFAT and NTFS have no executable bit, so `chmod` does nothing there. Copy the kit to a real filesystem first — [01-setup.md](01-setup.md). |
| `step-kms-plugin was not found on PATH` | The plugin is missing from the kit. The stock `step` is a static build that execs it for every `pkcs11:` URI — see [01-setup.md](01-setup.md). |
| `Test-Token.ps1` fails the PIV or PKCS#11 check | OpenSC cannot drive this card. Provision and sign on Windows instead, or use an NFC+ SKU — [research 54 §2](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md). |
| A `FAIL` line appears during signing | Stop and carry nothing away. The security key is untouched and re-signing the same CSR is safe; any certificate already on disk was left as it was. |
| `No smart card reader` | `pcscd` is not running, or the security key is not attached to WSL. `sudo service pcscd start`; for WSL, `usbipd attach --wsl --busid <busid>`. |

## Reference

- [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) — the hierarchy: 10-year offline root, 1-year TPM-bound intermediate
- [ADR 42](../decisions/42-pki-topology-sibling-cas.md) — the two sibling CAs under one root
- [runbook 46](../runbooks/46-adopt-utrust-piv-root-custody.md) — adopting the security key as root custody
- [research 54](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md) — the hardware diagnostic, verified command shapes
- [runbook 35](../runbooks/35-deploy-step-ca.md) — producing the CSR and installing the intermediate
- [runbook 41](../runbooks/41-deploy-freeipa-server.md) — the FreeIPA CA ceremony
