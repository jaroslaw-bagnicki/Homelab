# Private CA — 10-Year Offline Root, TPM-Bound Intermediate, Short-Lived Leaves

**Date:** 2026-10-04
**Status:** Accepted

---

## Context

[ADR 34](34-lan-tls-only.md) made every LAN service **TLS-only** and then admitted its own gap: with
per-service self-signed certificates the transport is *encrypted* but the server is *unauthenticated*, so
a LAN MITM still succeeds and users learn to click past warnings. The ADR deferred the fix — a **private
CA** — to [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126).

Two pieces have since been settled:

- **The name space**: `.internal`, with DNSMasq and `.home` retired ([ADR 37](37-lan-name-space-internal.md)).
- **The analysis**: [research 35](../research/35-private-ca-and-lan-naming.md) (naming, ACME/wildcards,
  root distribution), [research 36](../research/36-step-ca-machine-identity.md) (tool selection,
  provisioners, key custody, host shape, disaster recovery) and
  [research 37](../research/37-tpm2-hardware-and-fleet.md) (TPM hardware).

What #126 still owed was the **certificate hierarchy and key custody** — how many tiers, where each key
lives, and how long each certificate lasts. That is this ADR.

The requirements the chain has to meet:

- **Authenticated TLS**, not just encrypted — a client must be able to verify the service.
- **No manual renewal toil and no expiry outage** — issuance and renewal must be automatic.
- **A root that is not reachable by an attacker who compromises a server** — the fleet's most exposed host
  must not be able to mint new intermediates.
- **A CA key that can be rebuilt if its host dies** — TPM-bound keys cannot be restored elsewhere, so the
  recovery story has to be a re-issue, not a backup.

## Decision

Adopt a **three-tier PKI** issued and renewed by **`step-ca`**:

1. **Root CA — 10 years.** The private key is kept **offline on an IronKey**. It is used only to sign the
   intermediate, so it is touched rarely. The intended upgrade is to move the root key into a **YubiKey
   PIV** so the key becomes non-exportable; the plan is to keep the same root certificate and change only
   its custody. **The PIV migration is a ceremony, not a file move**: import the key into a PIV slot,
   verify that it signs, then **destroy every exportable copy** — the IronKey copy and any backups of the
   key file. Importing alone does not make the existing copies non-exportable, so the custody benefit is
   only real once those copies are gone. (Generating a *new* root on the token is the alternative, and is
   rejected because it forces the root redistribution the offline-root design exists to avoid.) The
   **root certificate is distributed to the fleet and to workstations** — Ansible for the
   fleet, manually or by script for workstations.
2. **Intermediate CA — 1 year**, signed by the root. Its private key is stored in the **TPM 2.0 on
   `pve`** — the Wyse 5070's **Intel PTT firmware TPM**, not a discrete chip (measured 2026-10-04;
   [research 37 §5](../research/37-tpm2-hardware-and-fleet.md)) — so signing happens in hardware and the
   key never exists in the clear. Only the intermediate is online.
3. **Leaves — short-lived**, signed by the intermediate: server certificates for the reverse proxy
   (Caddy) and the services behind it, issued over **ACME** so they renew automatically. **Lifetime: 24 h
   default, 7 d maximum** — `step-ca`'s own default, capped so a mis-set provisioner cannot mint
   long-lived leaves. **No CRL or OCSP is operated**: revocation relies entirely on the short lifetime,
   so a compromised leaf stays trusted until it expires. That is an accepted residual, not an oversight.

The CA runs on **`pve`** — the TPM makes that host a hard requirement, since the intermediate key cannot
move to another machine. The container/VM shape is an implementation detail, not part of this decision
([research 36 §5](../research/36-step-ca-machine-identity.md) leans toward a dedicated unprivileged LXC
with the TPM bound through, rather than one all-in-one stack).

> **Assumptions recorded for review** (the operator was unavailable when this ADR was written):
> the IronKey is treated as an **encrypted offline carrier for the root key file**, not as a PKCS#11/PIV
> token — `step-ca` can sign *from* PKCS#11 HSMs, TPM 2.0 and YubiKey PIV, but not from an ordinary
> encrypted USB drive, so the IronKey participates in the rare root-signing ceremony rather than serving
> live sign operations. If the IronKey is in fact a PKCS#11/PIV-capable device, only this custody
> sentence needs amending.

## Consequences

- **The ADR 34 gap closes** once leaves are deployed: LAN services present certificates a client can
  verify against the fleet root, which is the whole point of the exercise.
- **The root is never online**, so compromising `pve` cannot forge a new intermediate — the worst case is
  a stolen 1-year intermediate, not a stolen root.
- **TPM key custody needs no custom build** — `tpmkms` is pure Go and compiled into the stock `step-ca`
  binary, so the CA stays an ordinary packaged service (the CGO / `step-ca-hsm` build is for PKCS #11 and
  YubiKey PIV). That contradicts Smallstep's docs page, so it was **verified on `pve` on 2026-10-04** —
  the stock binary served a CA from a TPM-held intermediate and issued a chain-verified leaf
  ([research 36 §5](../research/36-step-ca-machine-identity.md)).
- **The `pve` TPM is firmware, not a discrete chip.** Measured 2026-10-04, the Wyse 5070 exposes an
  **Intel PTT** firmware TPM, so the trust anchor is platform firmware rather than a separate
  tamper-resistant part, and a BIOS update, a `Clear TPM` or an NVRAM reset can **destroy the sealed
  key** ([research 37 §5](../research/37-tpm2-hardware-and-fleet.md)). PTT is still a genuine TPM 2.0
  implementation, so the key stays non-exportable, and the recovery path below absorbs the loss — a PTT
  wipe costs a re-signing ceremony, not a re-trust — but it will be needed more often than with a
  discrete chip.
- **Recovery is cheap because the root stays offline: only the intermediate is re-issued.** If `pve` or
  its TPM dies, the intermediate key is gone but the **root is unaffected** — the runbook re-signs a
  fresh 1-year intermediate with the offline root, and the fleet and workstations keep trusting the same
  root. There is **no root re-issue and no client re-trust window**, so a `pve` failure is contained to
  the intermediate. Short-lived leaves then re-enrol automatically. Only the loss of the *root* key
  forces a new root and a full redistribution — which is exactly why the root is the one key kept offline
  on the IronKey, with the YubiKey PIV upgrade planned to make it non-exportable.
- **Root distribution is the adoption cost.** Every client that should trust LAN names needs the root
  installed. The fleet is covered by Ansible; **workstations and personal devices are manual**, and a
  managed/corporate workstation may refuse a private root while Firefox keeps its own trust store — the
  constraint [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) already records.
- **A 1-year intermediate means a recurring signing ceremony** with the offline root — a manual touchpoint
  roughly annually. Acceptable at this scale.
- **A device compromise cannot be fixed by revocation alone** within a leaf's lifetime; short-lived leaves
  are the mitigation ([research 36 §2](../research/36-step-ca-machine-identity.md)).
- **Wildcards, if used, need DNS-01 or manual issuance** — never HTTP-01
  ([research 35 §4](../research/35-private-ca-and-lan-naming.md)).
- **Out of scope here**: the resolver choice (Unbound vs AdGuard Home vs dnsmasq), the wildcard-vs-
  per-service leaf question, and the SSH-certificate use of the same CA. They remain open in
  [idea 10](../ideas/10-internal-ca-dns-stack.md).
- **The decision is recorded here; [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) stays open as
  the implementation tracker** for the build.

### Alternatives Considered

- **Keep per-service self-signed certificates** (the ADR 34 status quo) — encrypted but unauthenticated;
  rejected because it does not close the gap the private CA exists to close.
- **Hold root and intermediate online together on one host** — the all-in-one Compose shape. Rejected:
  a single host compromise would expose the root, and short-lived renewals mean the root would sit on a
  busy network service ([research 36 §5](../research/36-step-ca-machine-identity.md)).
- **Intermediate (or root) in Azure Key Vault** — a genuinely supported path that matches
  [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126)'s original sketch
  ([research 36 §4](../research/36-step-ca-machine-identity.md)). Rejected for now in favour of local,
  offline custody: it puts a cloud dependency and an internet round-trip into the trust anchor. **Remains
  the fallback** if TPM/YubiKey custody proves impractical.
- **Root key in a YubiKey PIV immediately** — the stated intent, but sequenced after the IronKey start;
  PIV custody also needs the CGO build.
- **SPIFFE/SPIRE or HashiCorp Vault as the identity platform** — both evaluated and rejected as heavier
  than a five-node fleet needs; `step-ca` covers ACME, OIDC and SSH certificates in one binary
  ([research 36 §1](../research/36-step-ca-machine-identity.md)).
- **`mkcert` / a public subdomain + DNS-01** — the lighter options from research 35; `mkcert` is
  single-developer only, and the public-subdomain route publishes internal names and needs DNS-provider
  access at renewal. Kept as a client-trust fallback, not adopted.
