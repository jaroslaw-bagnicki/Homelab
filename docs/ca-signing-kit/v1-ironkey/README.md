# v1 — IronKey signing kit (active)

The root CA's private key is an **encrypted key file on a USB stick**. This kit creates the root once,
then signs the CAs under it.

> The token kit ([`../v2-utrust-token/`](../v2-utrust-token/README.md)) is the planned upgrade but is
> dormant until a working PIV token is acquired. See the [parent README](../README.md).

## Contents

| File | What it is |
|---|---|
| [`01-building-step.md`](01-building-step.md) | puts the `step` CLI into this bundle — on the connected machine, before you leave |
| [`02-issuing-root-cert.md`](02-issuing-root-cert.md) | creates the 10-year root on the stick — **once ever** |
| [`03-signing-csr.md`](03-signing-csr.md) | signs the `step-ca` intermediate CSR — every year |
| [`04-signing-ipa-ca.md`](04-signing-ipa-ca.md) | signs FreeIPA's `ipa.csr` — **once per IPA CA**, on the Windows workstation |
| `root.sh` | creates the root CA on the stick; first run only |
| `sign.sh` | signs the intermediate CSR, then verifies the result |
| `step` | the CLI, linux/amd64 — **not in git** (42 MB), added by 01 |
| `step.exe` | the CLI, windows/amd64 — **not in git** (45 MB), for [04](04-signing-ipa-ca.md) |
| `intermediate_ca.csr` | the request, created on the CA host by `pve1`'s TPM key — **not in git** |
| `intermediate-ca.tpl` | the intermediate's required extensions |
| `ipa-ca.tpl` | the FreeIPA CA shape |

`intermediate-ca.tpl` and `ipa-ca.tpl` are **shared** with the token kit and live one level up in
[`../`](../). Both kits sign the same CSRs with the same root.

## The flow

1. **Build the bundle** — [`01`](01-building-step.md). On the connected machine, before you leave.
2. **Create the root** — `./root.sh <stick-mount>` — [`02`](02-issuing-root-cert.md). **Once ever.**
3. **Sign the intermediate** — `./sign.sh <stick-mount>` — [`03`](03-signing-csr.md). The annual job.
4. **Sign the FreeIPA CA** — the `step.exe certificate sign` command in [`04`](04-signing-ipa-ca.md).
   Once per IPA CA, on the Windows workstation.

Both scripts take the stick's mount path as the first argument and an optional passphrase file as the
second. Neither has a default — the destination is always explicit.

## The root key passphrase

`root_ca_key` on the stick is **encrypted**. Its passphrase is held in **Keeper Vault** — never on the
stick, never in this repo. Open the entry before any run that signs, and record the root fingerprint
beside it when the root is created ([02](02-issuing-root-cert.md)). Lose the passphrase and the root
key is dead, which means a full trust rotation ([ADR 38](../../decisions/38-private-ca-hierarchy-and-custody.md)).

## The ceremony machine

The root key is an encrypted file on the stick, so an **air-gapped live-USB boot** is recommended —
keeping the key off a connected host shrinks the window in which it could be exposed. That is a
recommendation, not an invariant: the scripts warn when they find a network and carry on, and the
operator decides.

**Any live Linux will do.** The bundled `step` is statically linked, so nothing needs installing — only
a shell and a copy of the bundle on a real filesystem. SystemRescue 13 is the default; an Ubuntu Live
desktop works too:

| | SystemRescue 13 | Ubuntu Live |
|---|---|---|
| Who you are | `root` | user `ubuntu`, passwordless `sudo` — prefix `sudo` where needed |
| Removable media | **not** auto-mounted — run `mountall`, or mount it yourself | auto-mounted under `/media/ubuntu/<label>` |
| Network | nothing brings it up | NetworkManager may connect by itself |

Running it on your normal Windows workstation also works — that is what [04](04-signing-ipa-ca.md) does,
and it is the proven path for the FreeIPA CA.

## Why `--template` and not `--profile`

`sign.sh` uses `--template`, never `--profile`: a profile rebuilds the certificate from its own defaults
and silently drops the SANs that declare the CA's identity. The FreeIPA CA command in
[`04`](04-signing-ipa-ca.md) uses `--template` for the same reason.

`root.sh` uses `--profile root-ca`, and that is **not** a contradiction. A root has no SANs to drop (it
is never a TLS server) and inherits nothing from a CSR (it is the trust anchor). Its whole required
shape is CA:TRUE + pathlen≥1 + certSign/crlSign, which is exactly what that profile produces.
