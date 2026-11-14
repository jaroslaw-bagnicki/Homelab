# v1 — IronKey signing kit (active)

The root CA's private key is an **encrypted key file on a secure USB stick**, used only from an
air-gapped machine. This kit creates the root once and signs the CAs under it.

> **This is the active kit.** The token kit ([`../v2-token/`](../v2-token/README.md)) is the planned
> upgrade but is dormant until a working PIV token is acquired. See the
> [parent README](../README.md).

## What this is, and is not

The fleet CA's **offline root** is created here, the **`step-ca` intermediate** is signed by it, and
(for M1) the **FreeIPA CA** CSR is signed by the same root. All of it happens on a machine with no
network of any kind, because the root's private key lives on the stick and must never touch a
networked machine. This bundle carries the tool, the requests and the recipes, so the signing machine
needs **nothing installed and nothing downloaded**.

**Any live Linux will do.** SystemRescue 13 is the default; an Ubuntu Live desktop works just as well.
Nothing has to be installed: the bundled `step` is statically linked, so it does not care what the host
distribution is. Only two things matter — **no network**, and a shell to run the steps below.

If you use Ubuntu Live rather than SystemRescue, three differences:

| | SystemRescue 13 | Ubuntu Live |
|---|---|---|
| Who you are | `root` | user `ubuntu` with passwordless `sudo` — prefix `sudo` where needed (`mkdir`, `mount`) |
| Removable media | **not** auto-mounted — run `mountall`, or mount it yourself (step 4) | **auto-mounted** under `/media/ubuntu/<label>` — use that path |
| Network | nothing brings it up | NetworkManager may connect by itself — **disable Wi-Fi / unplug the cable** before touching the stick. Both scripts abort if they find **any non-loopback address** (or a default route). |

It does **not** start the CA and does **not** distribute trust. Nothing in the bundle is private — the
CSR and the template are public. The one secret it produces is the **root key**, and that must leave
the signing machine only on the stick, back into the safe.

## Contents

| File | What it is |
|---|---|
| [`01-building-step.md`](01-building-step.md) | puts the `step` CLI into this bundle — on the connected machine, before you leave |
| [`02-issuing-root-cert.md`](02-issuing-root-cert.md) | creates the 10-year root on the stick — **once ever** |
| [`03-signing-csr.md`](03-signing-csr.md) | signs the intermediate CSR with that root — every signing |
| `root.sh` | creates the root CA on the stick; first run only |
| `sign.sh` | signs the `step-ca` intermediate CSR with the stick root, then machine-checks the result |
| `sign-ipa-ca.sh` | signs FreeIPA's `ipa.csr` (from `ipa-server-install --external-ca`) with the same root |
| `step` | the `step` CLI, linux/amd64 — **not stored in git** (42 MB upstream binary), added by 01 |
| `intermediate_ca.csr` | the certificate request, created on the CA host by the key in `pve1`'s TPM — **not stored in git** |
| `intermediate-ca.tpl` | the signing template — the extensions the finished certificate must carry |
| `ipa-ca.tpl` | the FreeIPA CA signing template |

`intermediate-ca.tpl` and `ipa-ca.tpl` are **shared** with the token kit and live one level up in
[`../`](../). Both kits sign the same CSRs with the same root.

## The flow

1. **Build the bundle** — [`01-building-step.md`](01-building-step.md). Do this on the connected
   machine, before you leave for the air-gapped one.
2. **Create the root** — `./root.sh <stick-mount>` — [`02-issuing-root-cert.md`](02-issuing-root-cert.md).
   **Once ever.**
3. **Sign the intermediate** — `./sign.sh <stick-mount>` — [`03-signing-csr.md`](03-signing-csr.md).
   This is the annual job.
4. **Sign the FreeIPA CA** — `./sign-ipa-ca.sh <stick-mount>`, when the IPA CA is built or re-signed.

Both scripts take the stick's mount path as their first argument and an optional passphrase file as the
second. Neither has a default — the destination is always explicit.

## Why `--template` and not `--profile`

`sign.sh` and `sign-ipa-ca.sh` use `--template`, never `--profile`: a profile rebuilds the certificate
from its own defaults and silently drops the SANs that declare the CA's identity.

`root.sh` uses `--profile root-ca`, and that is **not** a contradiction. A root has no SANs to drop (it
is never a TLS server) and inherits nothing from a CSR (it is the trust anchor). Its whole required
shape is CA:TRUE + pathlen≥1 + certSign/crlSign, which is exactly what that profile produces.

## Related

- [Parent README](../README.md) — both kits side by side
- [runbook 36](../../runbooks/36-private-ca-init.md) — the operational ceremony this kit serves
- [ADR 38](../../decisions/38-private-ca-hierarchy-and-custody.md) — root custody decision
- [runbook 39](../../runbooks/39-trust-private-ca.md) — distributing the root
