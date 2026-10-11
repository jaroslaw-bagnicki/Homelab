# Idea 10 — Internal DNS + Private CA + Reverse Proxy Stack

> Give the LAN one **name space**, one **certificate authority** and one **HTTPS entry point**:
> a local resolver answers `*.internal` with the stack's IP, **Caddy** terminates TLS and routes
> by hostname, and **step-ca** issues the certificates as a private ACME server — so every LAN
> service gets a **trusted, self-renewing** certificate instead of a browser warning. The name space is
> settled ([ADR 37](../decisions/37-lan-name-space-internal.md) — `.internal`); what is missing is the
> stack that serves it. DNSMasq is **gone** — never reinstalled after the M910q OS refresh, so
> [ADR 06](../decisions/06-local-dns-dnsmasq.md) is retired — leaving the fleet with **no LAN name
> resolution at all** today, while Caddy's per-instance internal CA
> ([ADR 07](../decisions/07-reverse-proxy-caddy.md)) is not a fleet trust anchor
> ([ADR 34](../decisions/34-lan-tls-only.md) defers that to [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126)).

**Status**: 📋 Planned — decided by [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) (three-tier chain, key custody, `step-ca`, host `pve`); implementation not started
**Date**: 2026-09-29 (extended 2026-09-30; decided 2026-10-04)
**Source**: [Gemini — pseudo-domains for local networks](https://share.gemini.google/UPNAO3UsBe8l) (published 2026-09-29) · [machine identity](https://share.gemini.google/5jgOfXFrcdLV) · [step-ca overview](https://share.gemini.google/B603IrdX0Zgq) · [TPM 2.0 in business](https://share.gemini.google/9Ph6gwBvDzmk) · [step-ca architecture](https://share.gemini.google/xB7DpeltqTaG) (all 2026-09-30, published 2026-10-04)
**Related**: [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) (the decision) · [research 35](../research/35-private-ca-and-lan-naming.md) (naming + stack) · [research 36](../research/36-step-ca-machine-identity.md) (tool, key custody, placement, DR) · [research 37](../research/37-tpm2-hardware-and-fleet.md) (TPM hardware) · [ADR 37](../decisions/37-lan-name-space-internal.md) (`.internal`; DNSMasq and `.home` retired) · [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) (implementation tracker) · [ADR 34](../decisions/34-lan-tls-only.md) · [ADR 06](../decisions/06-local-dns-dnsmasq.md) / [ADR 07](../decisions/07-reverse-proxy-caddy.md) (incumbents) · [ADR 31](../decisions/31-static-address-scheme.md) (a guest on `pve`) · [ADR 22](../decisions/22-k3s-arc-homelab.md) (k3s — the `lab` blocker)

---

## Context

[ADR 34](../decisions/34-lan-tls-only.md) made every LAN service TLS-only, then admitted the gap: with
self-signed certificates the transport is encrypted but the server is **unauthenticated** — a LAN MITM
still wins, and users learn to click past warnings. Fixing that needs a **private CA**, which is
[#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126). The name it issues **for** is now
settled — `.internal` ([ADR 37](../decisions/37-lan-name-space-internal.md)) — and that ADR also
retired DNSMasq and `.home`: with DNSMasq gone and nothing deployed in its place,
**the fleet has no LAN name resolution at all** — nodes are reached by static IP
([ADR 31](../decisions/31-static-address-scheme.md)) and by mDNS `.local` names. A private CA is only
useful if services renew themselves against it, so the natural shape is one stack —
**resolver + proxy + CA** — which also gets DNS, TLS and naming deployed together rather than one at a
time.

## The stack

```
client ── DNS: grafana.internal → stack IP ──► [ local DNS ]  (Unbound / AdGuard Home)
                                                     │
client ── HTTPS ──────────────────────────────────► [ Caddy ] ──► services (Netdata, Proxmox UI, …)
                                                        │
                                          ACME ◄────────┴──────► [ step-ca ] (private CA)
```

- **One wildcard DNS rule** (`*.‹lan-domain›` → the node's IP) means a new service needs a `Caddyfile`
  entry and nothing else.
- **Caddy** owns TLS termination and hostname routing; **`step-ca`** issues short-lived certificates
  over ACME, which Caddy renews automatically on the internal Docker network.
- Candidate deployment: **one Docker Compose stack in an unprivileged LXC on `pve`** — Proxmox
  snapshots/PBS then back up names, routing rules and the CA's private key as a unit.

## Name space — decided: `.internal`

**Decided 2026-09-29** ([ADR 37](../decisions/37-lan-name-space-internal.md)): the LAN name space is
**`.internal`** — a single label, reserved by ICANN (2024) for private use and guaranteed never to be
delegated. `.home` and DNSMasq are retired with it. RFC/ICANN authority and the full analysis:
[research 35 §1](../research/35-private-ca-and-lan-naming.md).

| Name | Verdict | Reason |
|---|---|---|
| **`.internal`** | **Adopted** | ICANN 2024 reservation; a single label — short, and safe to issue certificates for |
| `.home.arpa` | Rejected | RFC 8375's standard home name space, but a **second-level** name and too long for everyday use |
| `.home` (incumbent) | Retired | No RFC and no ICANN reservation; DNSMasq was never reinstalled after the M910q refresh |
| `.lan` | Rejected | No standard at all, despite ubiquitous router use |
| Subdomain of the owned public domain | Fallback | Publicly trusted TLS via DNS-01 with **zero client configuration** — at the cost of publishing internal hostnames in public DNS |
| `.local` | mDNS only | RFC 6762 reserves it for mDNS; unusable in a unicast resolver (breaks Apple devices) |

## Host — the shortlist

**Not decided.** Three platforms are on the table (2026-09-29), each carrying the operator's own caveat:

| Host | Shape | Status / concern |
|---|---|---|
| **`pve`** | Docker Compose workload in an unprivileged **LXC** | The operator's lean — snapshot-able, light, and it fits the `21x` guest scheme ([ADR 31](../decisions/31-static-address-scheme.md)) |
| **`edge`** | **Bare metal** on the Wyse 3040 | Unclear whether the 3040's resources carry this stack, and bare-metal upkeep looks heavier than a Compose workload |
| **`lab`** | **k3s** workload on the M910q | **Blocked** — k3s is not installed yet ([ADR 22](../decisions/22-k3s-arc-homelab.md), [#44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44)) |

The OPNsense options the source thread evaluated are **not in the current shortlist** — the router's
built-in CA has no ACME *server*, and a native FreeBSD `step-ca` binary falls outside its XML backup.
Detail: [research 35 §7](../research/35-private-ca-and-lan-naming.md).

## Tool, key custody and shape — decided ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md))

The 2026-09-30 threads sharpened the three open pieces; **ADR 38 settled them**:

- **Tool: `step-ca`.** It covers ACME (proxies, k3s), OIDC identity-based issuance, and SSH
  certificates from one small binary — the machine-identity outcome of SPIRE or Vault PKI without the
  second control plane. SPIRE is the heavyweight alternative, Vault the middle ground.
  [research 36 §1–§3](../research/36-step-ca-machine-identity.md)
- **Certificate chain.** Three tiers — **10-year root**, **1-year intermediate**, short-lived leaves;
  the root signs the intermediate, the intermediate signs the leaves.
  ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md))
- **Key custody.** Root private key **offline on an IronKey** (later a YubiKey PIV); intermediate key in
  the **`pve` TPM 2.0** — an **Intel PTT firmware TPM**, not a discrete chip
  ([research 37 §5](../research/37-tpm2-hardware-and-fleet.md)) — and the TPM path is pure Go, so the
  stock `step-ca` binary suffices. An emulated vTPM is explicitly **not** a security boundary
  ([research 37 §6](../research/37-tpm2-hardware-and-fleet.md)); **Azure Key Vault** and a **YubiHSM**
  remain fallbacks. [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)
- **Shape.** CA on **`pve`** (required by the TPM), provisioned by Ansible — [research 36 §5](../research/36-step-ca-machine-identity.md)
  leans toward a **dedicated unprivileged LXC** with `/dev/tpmrm0` bound through, rather than one shared
  Compose stack with Caddy + Unbound.
- **Disaster recovery.** Losing `pve` or its TPM costs **only the intermediate**: re-sign a new one with
  the offline root, leaving the root and its distribution untouched, so there is **no client re-trust** and
  no propagation window. Only a root loss forces a re-issue and redistribution.
  [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) · [research 36 §6](../research/36-step-ca-machine-identity.md)

## Open questions

- **Resolver**: Unbound vs AdGuard Home vs dnsmasq — the one part of the stack **ADR 38 deliberately
  leaves open**.
- **Wildcard vs per-service leaves** — ADR 38 fixes short-lived leaves but not whether one wildcard sits
  on the proxy or each service gets its own.
- **Deployment shape** — dedicated LXC vs VM, as a native systemd service on the stock binary.
- **One wildcard on the proxy, or per-service leaves?** Simplest operationally, but the same key sits
  in front of every service, and one expiry takes everything down together.
- **Resolver**: Unbound vs AdGuard Home vs dnsmasq.
- **Client trust rollout** — a managed workstation may refuse a private root, and Firefox keeps its
  own trust store. This is the argument for the public-subdomain fallback.
- **The rename itself** — the NAS carries the old domain today
  ([runbook 32](../runbooks/32-beetle-m3-omv-setup.md)) and is repointed with the stack, not before
  ([ADR 37](../decisions/37-lan-name-space-internal.md)).
- **Nothing measured**: RAM/CPU on the Wyse 5070 — and on the 3040 if `edge` wins — and the
  Docker-in-LXC recipe are unverified.

## References

- [research 35 — private CA and LAN domain naming](../research/35-private-ca-and-lan-naming.md) — findings, snippets and the full option analysis
- [ADR 37](../decisions/37-lan-name-space-internal.md) · [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) · [ADR 34](../decisions/34-lan-tls-only.md) · [ADR 06](../decisions/06-local-dns-dnsmasq.md) · [ADR 07](../decisions/07-reverse-proxy-caddy.md) · [ADR 22](../decisions/22-k3s-arc-homelab.md)
