# 03 — Signing the intermediate CSR

Signs `intermediate_ca.csr` with the offline root. This is the operation that **repeats** — run it at
every signing, including the annual re-sign before the intermediate expires.

## Before you start

- The bundle is on the signing machine and `step` runs, and the stick is mounted — [README](README.md)
  steps 2–4.
- The **secure USB stick** is mounted and already holds the root (`root_ca.crt`, `root_ca_key`). If it does not,
  create it first: [02](02-issuing-root-cert.md).

## Run it

```sh
./sign.sh <destination-path>
```

It runs exactly this, and asks for the root key's passphrase — or takes it from a file, as in
[02](02-issuing-root-cert.md):

```sh
./step certificate sign --template intermediate-ca.tpl --not-after 8760h \
  intermediate_ca.csr <destination-path>/root_ca.crt <destination-path>/root_ca_key \
  > intermediate_ca.crt.new      # checked first, renamed to intermediate_ca.crt once it passes
```

**`--template`, never `--profile intermediate-ca`.** A profile rebuilds the certificate from its own
defaults and silently drops the SANs — the intermediate's declared identity shape. Measured 2026-10-11:
the certificate that serves TLS is a **separate self-issued leaf** the CA builds from `ca.json`'s
`dnsNames` (runbook 35 §7), so a SAN-less intermediate is not an instant outage — it is a silent change
to the CA's declared shape, and the deployment record asserts those SANs. The template makes the
**signer** assert the shape rather than inheriting it from the requester.

If you ever edit `intermediate-ca.tpl`, the working shape is a top-level `dnsNames` / `ipAddresses`
pair. A `sans` list of plain strings fails with `cannot unmarshal string into
Certificate.sans.0 of type x509util.SubjectAlternativeName`, and a nested `{"dnsNames":…}` object is
silently ignored, producing a certificate with no SAN at all.

The script signs into a temporary file, runs every check on that file, and only then renames it into
place — so a failed run cannot leave a half-written certificate to carry home, and cannot overwrite the
previous year's good certificate either.

## Acceptance

`sign.sh` machine-checks the result and prints the certificate. **Every check must pass:**

| Check | Expected |
|---|---|
| chain | `certificate verify` succeeds against the root on the stick |
| is a CA | `is_ca: true` |
| path length | `max_path_len: 0` — it issues leaves, nothing deeper |
| key usage | `certificate_sign` and `crl_sign` |
| SAN | `dns_names` present, containing `ca.internal` and `192.168.2.215` |
| validity | 1 year |

The SAN rows are the important ones. They assert the CA's **declared identity shape** — an identity
policy, not a TLS requirement: the certificate that answers TLS is the separate self-issued leaf named
from `ca.json`'s `dnsNames` (runbook 35 §7). An intermediate without those SANs would still serve the
CA, but it would no longer match the shape this CA is documented to carry.

Read the printed dump as well. It must show issuer `CN=Homelab Internal CA`, subject
`CN=Homelab Intermediate CA`, ~1 year of validity, `critical CA:TRUE, pathlen:0`, key usage
`Digital Signature, Certificate Sign, CRL Sign`, and a Subject Alternative Name of `DNS:ca.internal` /
`IP Address:192.168.2.215`.

## If it refuses

| Symptom | What to do |
|---|---|
| `error decrypting ... decryption password incorrect` | Wrong root key passphrase. Nothing was written; re-run with the right one. |
| "`root_ca.crt` not found" | The stick is not mounted, or holds no root — see [02](02-issuing-root-cert.md). |
| SAN line absent, or a `FAIL` line | Stop and do not carry the certificate home. No trust has been distributed, the root is untouched, and re-signing the same CSR is safe. |

## The annual re-sign

ADR 38 sets the intermediate at **1 year**, so roughly annually the same root re-signs a fresh
certificate for the **same TPM key**:

1. On the `ca` guest, re-run runbook 35 §6's CSR task — a fresh `intermediate_ca.csr` from the existing
   TPM key. Do **not** recreate the key.
2. Sign it here.
3. Install it and restart the service (runbook 35 §7).

No new key, no root re-issue, no client re-trust — the fleet and workstations keep trusting the same
root, so there is no propagation window. That is the payoff of the offline root.
