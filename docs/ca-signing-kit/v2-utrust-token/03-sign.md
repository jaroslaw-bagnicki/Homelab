# 03 — Sign a CA with the uTrust Security Key

This is the operation that **repeats** — at every signing, including the annual re-sign before the
intermediate expires. Two scripts, one ceremony each.

## Before you start

- [01-setup.md](01-setup.md) is done and `./Test-uTrustKey.ps1` passes.
- The root already exists on the uTrust Security Key ([02](02-root.md)) and `root_ca.crt` is in the kit.
- The CSR is in the kit — `intermediate_ca.csr` from the CA host, or `ipa.csr` from the IPA guest.

## Sign the step-ca intermediate

```sh
cd ~/ca-signing-kit
./New-Intermediate.ps1
```

That is the whole annual ceremony. The script:

1. **Prints the CSR.** Check the subject and the public key on screen — this is the guard against
   signing a request that is not the one the CA host produced.
2. **Signs it** with the root on the uTrust Security Key. PC/SC prompts for the PIV PIN, once,
   immediately before the signature.
3. **Checks the result** and only then promotes it to `intermediate_ca.crt`.

### What it checks

- chains to `root_ca.crt` in the kit
- `CA:TRUE`, `pathlen:0`
- key usage `certSign` + `crlSign`
- SANs present, carrying `ca.internal` and `192.168.2.215`
- validity 1 year

A `FAIL` line means: **stop, carry nothing away.** The certificate is discarded, any certificate
already on disk is left as it was, the uTrust Security Key is untouched, and re-signing the same CSR
is safe.

### Why `--template` and never `--profile`

A profile rebuilds the certificate from its own defaults and silently drops the SANs. The SANs are the
CA's declared identity shape — what the deployment records and audits expect. The script uses
`--template` and machine-checks the SANs afterwards, so a dropped SAN cannot slip through.

(The certificate that actually serves TLS is a separate self-issued leaf the CA builds from `ca.json`'s
provisioner, so the intermediate carries no TLS role itself. The SANs still have to be there.)

## Sign the FreeIPA CA

```sh
./New-IpaCa.ps1
```

Same ceremony, different inputs: `ipa.csr` → `ipa-ca.crt`, `ipa-ca.tpl`, 1 year, subject
`CN=Certificate Authority, O=IPA.INTERNAL` checked.

Bring `ipa.csr` from the IPA guest first — it is produced by `ipa-server-install --external-ca` and is
public, so it can travel by any means.

## Afterwards

```sh
./Test-uTrustKey.ps1   # optional last look before the uTrust Security Key goes away
```

Carry back the public certificates and put the uTrust Security Key in the safe:

| File | Goes to |
|---|---|
| `intermediate_ca.crt` | [runbook 35 §7](../../runbooks/35-deploy-step-ca.md) |
| `ipa-ca.crt` | [runbook 41](../../runbooks/41-deploy-freeipa-server.md) |
| `root_ca.crt` | [runbook 39](../../runbooks/39-trust-private-ca.md), if the root changed |

## Options

Nothing to pass. Both signing scripts find the key themselves:

```sh
./New-Intermediate.ps1
```

The input and output filenames are fixed — `intermediate_ca.csr` → `intermediate_ca.crt`, and
`ipa.csr` → `ipa-ca.crt`. Put the CSR in the kit folder and the script finds it.

## When it refuses

| Symptom | Meaning |
|---|---|
| `The intermediate CSR … is missing` | Bring the file the CA host produced — [runbook 35 §6](../../runbooks/35-deploy-step-ca.md). |
| `No uTrust Security Key found` | The key is not plugged in, or `pcscd` is not running. |
| `step-kms-plugin was not found on PATH` | The plugin is missing from the kit — [01-setup.md](01-setup.md). |
| `This certificate is not fit to install` | A check failed. Nothing was trusted; re-signing is safe. |
