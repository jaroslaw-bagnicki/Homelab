# LAN Services Are TLS-Only — No Plaintext HTTP

**Date:** 2026-09-20
**Status:** Proposed

---

## Context

The fleet has accumulated LAN-facing HTTP services — the Netdata Parent dashboard on `pve` ([ADR 27](27-monitoring-strategy.md)), the Proxmox web UI, Caddy on the edge appliance ([ADR 24](24-edge-ingress-appliance.md)) and, planned, a log store ([#123](https://github.com/jaroslaw-bagnicki/Homelab/issues/123)). Each was hardened individually: Netdata's dashboard listener is `^SSL=force` (plain HTTP receives its `399` redirect and no content), its stream listener is TLS-only, Proxmox serves `8006` over HTTPS, and `pve`/`lab` UFW carry `80/tcp DENY IN` commented *"block direct HTTP — ingress via the edge appliance"*.

That practice is real but **unwritten**, so nothing stops the next service being deployed over plain HTTP. A rule that exists only in individual configs is one that gets violated silently.

An inventory of LAN listeners (2026-09-20) shows the fleet is currently compliant: `pve` exposes `22`, `8006`, `19996`, `19999`; `lab` and `edge` expose only `22`. No plaintext HTTP service is reachable, and UFW's default-deny closes the two Proxmox defaults that do listen in cleartext — `pve:3128` (spiceproxy, a cleartext HTTP CONNECT proxy) and `pve:111` (rpcbind).

## Decision

**Every LAN-exposed service we deploy serves TLS only; plaintext HTTP is prohibited.**

A plaintext listener is permitted only when all three hold:

1. the protocol has no TLS-capable alternative *in our deployment*;
2. it is listed in the exception table below with a rationale; and
3. it stays firewall-restricted to `192.168.2.0/24`.

### Exception table

| Protocol | Port | Why plaintext is accepted |
|---|---|---|
| mDNS / Avahi | 5353/udp | Service discovery; no TLS variant |
| DNS (resolver / forwarder) | 53 | Inherently plaintext; DoT/DoH only if adopted |
| NTP / chrony | 123/udp | The protocol has no TLS |
| NUT | 3493 | `upsd`/`upsc` are plaintext ([ADR 30](30-ups-nut-graceful-shutdown.md)); NUT can do TLS but ours is unconfigured, and the port is LAN-only |
| ICMP | — | Reachability |
| NFS / SMB | 2049 / 445 | Decided when the NAS joins ([ADR 29](29-nas-backup-target-beetle-m3-omv.md)) — NFSv4 with Kerberos, or SMB signing plus encryption |

This ADR governs the **transport** only. Authenticating *users* stays per-service: Netdata's dashboard is unauthenticated on a trusted LAN (the residual accepted in ADR 27), while the planned log store takes HTTP basic auth from day one.

### Enforcement

- `docs/workloads.md` carries the rule in its convention list, so it is answered at the point of work rather than remembered.
- **Netdata as a monitored control** — the `httpcheck` and `x509check` collectors ship with the installed agent and can assert that each LAN service answers HTTPS, that plaintext is refused or redirected, and that certificates are not near expiry. A rule nobody measures decays.
- The UFW `80/tcp DENY IN` rules remain the firewall backstop.

## Consequences

- One rule replaces per-service judgement; a new workload has a single compliance question to answer.
- Plaintext HTTP can no longer be justified by convenience — a service either serves TLS or appears in the exception table.
- Existing practice becomes documented rather than implicit; Netdata, Proxmox and the `80/tcp DENY` rules already satisfy it.
- **Encryption is not authentication** — with self-signed certificates the transport is encrypted but the server is unverified, so a LAN MITM still succeeds. ADR 27 already accepts this residual, and this ADR does not narrow it.
- The exception table needs maintenance: a protocol added by a future workload must be justified here, not assumed.

### Alternatives Considered

- **No rule — per-service hardening** (status quo). Rejected: it works until someone deploys in a hurry, and compliance cannot be distinguished from luck.
- **"No plaintext anything."** Rejected as unimplementable: DNS, mDNS, NTP and NUT offer no TLS alternative in our deployment, so an absolute rule would be broken by the fleet's own baseline services — which teaches people to ignore rules.
- **Central TLS termination** (one HTTPS entry point, services plaintext on loopback). Rejected for now: it concentrates the trust decision and the failure domain, and the services concerned already speak native TLS. Revisit if LAN-facing UIs multiply.
- **Private CA (`step-ca`) issuing fleet certificates** — deferred, not rejected. It is the only way to make certificates *authenticated* rather than merely encrypted, but its real cost is distributing the root to every client device for browser-facing services. Tracked as a follow-up ADR; until then ADR 27's self-signed residual stands.

---

## References

- [ADR 06](06-local-dns-dnsmasq.md) — Local DNS (`.home`), the plaintext DNS exception
- [ADR 24](24-edge-ingress-appliance.md) — Edge appliance (Caddy, constrained hardware)
- [ADR 27](27-monitoring-strategy.md) — Monitoring strategy; HTTPS-only dashboard and the accepted LAN-trust residual
- [ADR 29](29-nas-backup-target-beetle-m3-omv.md) — NAS (NFS/SMB decision pending)
- [ADR 30](30-ups-nut-graceful-shutdown.md) — NUT (plaintext `upsd`, LAN-restricted)
