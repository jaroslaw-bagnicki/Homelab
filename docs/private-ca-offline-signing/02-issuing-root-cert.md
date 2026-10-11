# 02 — Issuing the root certificate

Creates the 10-year root CA on the IronKey. **First run only** — once in the life of this CA.

## Before you start

- The bundle is on the signing machine and `step` runs, and the IronKey is mounted — [README](README.md)
  steps 2–4.
- The **IronKey is mounted**, and holds **no root yet**. That is where the root is written.
- **Skip this document completely** if the IronKey already holds a root, as it will on the annual
  re-sign. The repeat job is [03](03-signing-csr.md).

## Run it

```sh
./root.sh /mnt/ironkey
```

`root.sh` creates a passphrase-protected root key **on the IronKey**, and refuses to run if a root is
already there: replacing a root is a trust rotation — every client would have to re-trust — not a
re-run.

When it asks for a passphrase, **write it down and put it in the safe before you leave the machine.** It
is the only way to use this root key again; lose it and the key is dead.

To drive it non-interactively, put the passphrase in a file on `/tmp` and pass the path as a second
argument — then delete that file before powering off:

```sh
./root.sh /mnt/ironkey /tmp/rootpass.txt
```

### Why `--profile root-ca` is right here

[03](03-signing-csr.md) says never to sign a CSR with `--profile`, and `root.sh` uses one. That is not a
contradiction: a profile rebuilds a certificate from its own defaults, so signing a CSR with one
discards whatever the requester asked for — for an intermediate, that silently drops the SANs it needs
as a TLS server. A root has nothing to discard: it needs no SANs (it is never a TLS server) and
inherits nothing from a CSR (it is the trust anchor).

## Acceptance

`root.sh` checks all of this itself. **Every line must read OK:**

| Check | Expected |
|---|---|
| self-signed | `self_signed: true` |
| is a CA | `is_ca: true` |
| path length | `max_path_len` ≥ 1 — it must be able to sign an intermediate |
| key usage | `certificate_sign` and `crl_sign` |
| validity | 10 years |
| key protection | the key file says `ENCRYPTED` |

Ignore `"valid": false` in the JSON — that is normal for a root, since there is no higher authority to
validate it against. `self_signed: true` is the correct check.

It then prints the root fingerprint. **Record it outside the repo**, in the safe or a password manager,
together with the passphrase.

## If it refuses

| Symptom | What to do |
|---|---|
| "a root already exists" | Correct — it never replaces a root. Carry on with [03](03-signing-csr.md). |
| "holds an INCOMPLETE root" | An earlier run failed part-way. Remove `root_ca.crt` **and** `root_ca_key` from the IronKey, then run it again. |
