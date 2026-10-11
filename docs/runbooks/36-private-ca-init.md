# Private CA — Offline Root and Intermediate Signing (Init + Annual Re-Sign)

> Generate the CA's 10-year **root** on an air-gapped signing machine (a live-USB Linux boot with no
> network at all), keep it on a **secure USB stick** in a safe, and sign the certificate
> request the deploy host produced. Step 1 runs once; step 3 repeats every year, before the intermediate
> expires.
>
> ⚠ **The ceremony never touches the network.** This sits between
> [runbook 35 §6](35-deploy-step-ca.md), which produces the certificate request, and
> [§7](35-deploy-step-ca.md), which installs the signed certificate. Steps 1 and 2 are carried out by
> the [offline signing kit](../private-ca-offline-signing/README.md). The one command that needs a
> network is publishing the root to Key Vault at the end of step 1 — it runs on the controller,
> deliberately away from the signing machine. Installing the root on the fleet is
> [#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144), not covered here.

## Why

[ADR 34](../decisions/34-lan-tls-only.md) made every LAN service TLS-only and admitted the gap: a
certificate a service signs for itself proves nothing, so anyone already on the LAN can still sit in the
middle of the connection. [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) settles the fix
as three tiers — a **root** that is never online and lasts 10 years, an **intermediate** that lasts one
year whose key is sealed inside the `pve` TPM and cannot be copied out, and **leaf** certificates that
last hours or days.

The root is the one secret that cannot be replaced. Compromising `pve` still cannot mint a new
intermediate, and if `pve` or its TPM dies the root is untouched — the fix is to sign a new intermediate
with the same root, not to hand every client a new root to trust. That only holds as long as the root
key is created and used offline.

The `pve` TPM seals the intermediate key so it cannot be copied out
([research 37 §5](../research/37-tpm2-hardware-and-fleet.md)).

## Prerequisites

- [ ] `intermediate_ca.csr` — produced by [runbook 35 §6](35-deploy-step-ca.md)
- [ ] The [offline signing kit](../private-ca-offline-signing/README.md), with `step` in place
- [ ] A machine to use as the signing machine, booted from the YUMI multiboot stick

---

## 1. Create the root certificate on the secure USB stick

Run this only on the signing machine, with the stick mounted:

```sh
./root.sh <destination-path>
```

The script runs `step certificate create` for you, gives the key a passphrase, and sets the root's
lifetime to 10 years. It then checks what it produced and stops if anything is wrong: that the result is
a CA certificate allowed to sign another CA, that it lasts 10 years, that it may sign certificates and
revocation lists, and that the key file is protected. Finally it prints the fingerprint.

It refuses to run if a root already exists, because replacing a root later means every client has to be
told to trust a different one. A wrong root therefore has to be dealt with before it is ever handed out.

The output also reports `valid: false`. That is normal for a root — there is no higher authority to check
it against — and `self_signed: true` is the line that matters.

The root certificate is public and is sent out to clients later
([#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144)). Publish it to Key Vault once, from a
machine with network access — not the signing machine:

```powershell
.\scripts\Set-HomelabCaRootCert.ps1 -Path <path to root_ca.crt>
```

That writes `homelab-bysxdb-kv/ca-root-cert`, the copy every fleet node installs the anchor from. Only
the certificate is published: the script refuses a file that carries a private key, and the key never
leaves the stick. Passphrase handling, the exact refusal messages, and why this step may use
`--profile root-ca` while step 2 must not:
[02-issuing-root-cert.md](../private-ca-offline-signing/02-issuing-root-cert.md).

## 2. Sign the certificate request

```sh
./sign.sh <destination-path>
```

The script signs `intermediate_ca.csr` with a one-year lifetime, then checks the result for you rather
than leaving you to read the certificate: that it chains to the root on the stick, that it is a CA
certificate, that it may sign certificates and revocation lists, that it carries the hostname and IP
address the CA's identity shape requires, and that it lasts a year. It validates the temporary file and
moves it into place only once every check has passed, so a failed run cannot leave a half-finished
certificate behind — or overwrite a good annual one.

Sign with the template, never with `--profile intermediate-ca`. A profile rebuilds the certificate from
its own defaults and quietly drops the hostname and IP address — the SANs that declare the CA's identity
shape. That is not an immediate outage: the certificate that serves TLS is a separate self-issued leaf
named from `ca.json`'s `dnsNames` (runbook 35 §7), but the intermediate would no longer match the shape
this deployment records.

Afterwards, unmount the stick and put it back in the safe, and carry `intermediate_ca.crt` and
`root_ca.crt` back for [runbook 35 §7](35-deploy-step-ca.md). The required contents of the certificate
and the exact failure messages: [03-signing-csr.md](../private-ca-offline-signing/03-signing-csr.md).

> **Acceptance.** `step certificate inspect intermediate_ca.crt` shows: issuer = the root's CN,
> ~1-year validity, **`CA:TRUE, pathlen:0`**, and the **Subject Alternative Name**
> `DNS:ca.internal` + `IP Address:192.168.2.215`.

## 3. Annual re-sign

The intermediate lasts one year, so before it expires the same root signs a fresh one for the same TPM
key:

1. Produce a fresh `intermediate_ca.csr` from the existing TPM key — re-run
   [runbook 35 §6](35-deploy-step-ca.md)'s certificate-request task. Do not recreate the key.
2. Sign it with the kit: `./sign.sh <destination-path>`
   ([03-signing-csr.md](../private-ca-offline-signing/03-signing-csr.md)).
3. Install it and restart the service ([runbook 35 §7](35-deploy-step-ca.md)).

Nothing else changes. No new key, no new root, and no client has to be told anything, because every
client already trusts the same root. Set a reminder about 30 days before expiry; the current expiry is in
`step certificate inspect intermediate_ca.crt`.

Keep the old `intermediate_ca.crt` until the new one verifies against the root
([runbook 35 §7](35-deploy-step-ca.md)) — it is the way back if the signing is wrong, and it stays
valid until it expires.

---

## Verification Checklist

Executed on: **2026-10-11**. The root is self-signed, `CA:TRUE, pathlen:1`, 10 years; the intermediate
chains to it, `CA:TRUE, pathlen:0`, carrying the SANs `ca.internal` + `192.168.2.215`, and lasts one
year; the root is published to Key Vault as `ca-root-cert`.

- [x] Step 1: root created, every check passed, passphrase written into the safe, root published to Key Vault
- [x] Step 2: the intermediate signed, every check passed, stick back in the safe
- [ ] Step 3: annual reminder set — the intermediate expires **2027-10-11**

## Follow-ups

- **Deployment** — [runbook 35](35-deploy-step-ca.md) installs the signed intermediate and starts `step-ca`.
- **Distributing the root** — [#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144), out of scope.
- **Moving the root onto a YubiKey** — ADR 38's planned change. It makes the root impossible to copy out
  and destroys every copy that could be, so it is a ceremony rather than a file move. Out of scope.

## References

- [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) — the three tiers, who holds what, and the 1-year intermediate
- [Research 36 §4–§5](../research/36-step-ca-machine-identity.md) — how the TPM and KMS work
- [Research 37 §5](../research/37-tpm2-hardware-and-fleet.md) — the `pve` Intel PTT TPM, and why the key can be lost
- [Issue #141](https://github.com/jaroslaw-bagnicki/Homelab/issues/141) — the TPM test that settled the approach
- [Runbook 35](35-deploy-step-ca.md) — the deployment this ceremony feeds
- [Offline signing kit](../private-ca-offline-signing/README.md) — the scripts, and the instructions the signing machine follows
- [Runbook 28](28-pve-proxmox-node.md) (Proxmox base) · [ADR 34](../decisions/34-lan-tls-only.md) (TLS-only) ·
  [ADR 37](../decisions/37-lan-name-space-internal.md) (`.internal`)
