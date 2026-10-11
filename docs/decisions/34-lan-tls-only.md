# LAN Services Are TLS-Only — No Plaintext HTTP

**Date:** 2026-09-20
**Status:** Accepted

---

## Context

The fleet has accumulated LAN-facing HTTP services — the Netdata Parent dashboard on `pve` ([ADR 27](27-monitoring-strategy.md)), the Proxmox web UI, Caddy on the edge appliance ([ADR 24](24-edge-ingress-appliance.md)) and, planned, a log store ([#123](https://github.com/jaroslaw-bagnicki/Homelab/issues/123)). Each was hardened individually: Netdata's dashboard listener is `^SSL=force` (plain HTTP receives its `399` redirect and no content), its stream listener is TLS-only, Proxmox serves `8006` over HTTPS, and `pve`/`lab` UFW carry `80/tcp DENY IN` commented *"block direct HTTP — ingress via the edge appliance"*.

That practice is real but **unwritten**, so nothing stops the next service being deployed over plain HTTP. A rule that exists only in individual configs is one that gets violated silently.

An inventory of LAN listeners (2026-09-20) shows the fleet is currently compliant: `pve` exposes `22`, `8006`, `19996`, `19999`; `lab` and `edge` expose only `22`. No plaintext HTTP service is reachable, and UFW's default-deny closes the two Proxmox defaults that do listen in cleartext — `pve:3128` (spiceproxy, a cleartext HTTP CONNECT proxy) and `pve:111` (rpcbind).

## Decision

**Every LAN-exposed service we deploy serves TLS only; plaintext HTTP is prohibited.**

A plaintext listener is permitted only when all three hold:

1. **the protocol has no TLS-capable alternative at all** — TLS that merely is not configured is **not** an exception, it is non-compliance (second table below);
2. it is listed below with a rationale; and
3. it is restricted to `192.168.2.0/24` by a **verified** rule — asserting a port is "LAN-only" does not satisfy this.

### Exception table — inherent, no TLS alternative exists

| Protocol | Port | Why plaintext is accepted |
|---|---|---|
| mDNS / Avahi | 5353/udp | Service discovery; no TLS variant. Permitted by UFW's stock `before.rules` (accept to `224.0.0.251:5353`), and LAN-scoped because link-local multicast does not cross routers — verified 2026-09-20 by resolving a peer from `pve` |
| DNS (resolver / forwarder) | 53 | Inherently plaintext; DoT/DoH only if adopted |
| NTP / chrony | 123/udp | The protocol has no TLS |

ICMP is not a service listener and is therefore not listed; it remains permitted for reachability.

### Exception table — temporary non-compliance

TLS-capable protocols that are not yet configured for it. Each row carries a removal condition, and this table must not grow by default.

| Protocol | Port | Why it is currently plaintext | Removal condition |
|---|---|---|---|
| NUT | 3493 | `upsd`/`upsc` **do support TLS** — ours is unconfigured, so this is a deployment choice, not an inherent limitation. Anonymous reads are enabled. The listener is now **host-native on `pve`** ([ADR 39](39-nut-host-native.md)) and the host's UFW allows `3493` from `192.168.2.0/24` only; previously, in LXC 213 with no firewall of its own, it was reachable from a non-LAN host (verified 2026-09-20). | Configure NUT TLS (`upsd` + `upsmon` certificates) — or record an explicit accepted-risk waiver in [ADR 39](39-nut-host-native.md) |

**NAS storage is a requirement, not an exception.** NFS and SMB are encryption-capable, so when the NAS joins ([ADR 29](29-nas-backup-target-beetle-m3-omv.md)) the choice must be NFSv4 with `krb5p` or SMB with encryption enabled — plaintext NFS/SMB is not admitted by this ADR.

**Host UFW does not filter container traffic.** A service inside an LXC sits outside the host's UFW chains entirely — true of the VictoriaLogs store in LXC 214, and of any container-hosted workload. Container-hosted services need their own filtering; "the host firewall covers it" is never true for them. (The NUT server no longer fits this case — it is host-native on `pve`, [ADR 39](39-nut-host-native.md), so the host UFW *does* filter its `3493`.)

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
- **"No plaintext anything."** Rejected as unimplementable: DNS, mDNS and NTP offer no TLS alternative at all, so an absolute rule would be broken by the fleet's own baseline services — which teaches people to ignore rules. NUT is **not** in this category: it is TLS-capable and sits in the non-compliance table above.
- **Central TLS termination** (one HTTPS entry point, services plaintext on loopback). Rejected for now: it concentrates the trust decision and the failure domain, and the services concerned already speak native TLS. Revisit if LAN-facing UIs multiply.
- **Private CA (`step-ca`) issuing fleet certificates** — deferred, not rejected, and now tracked as [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126). It is the only way to make certificates *authenticated* rather than merely encrypted, but its real cost is distributing the root to every client device for browser-facing services. Until it lands, ADR 27's self-signed residual stands. The name space it must issue for is settled — `.internal` ([ADR 37](37-lan-name-space-internal.md)).

---

## References

- [ADR 06](06-local-dns-dnsmasq.md) — Local DNS (`.home`, retired by [ADR 37](37-lan-name-space-internal.md)), the plaintext DNS exception
- [ADR 24](24-edge-ingress-appliance.md) — Edge appliance (Caddy, constrained hardware)
- [ADR 27](27-monitoring-strategy.md) — Monitoring strategy; HTTPS-only dashboard and the accepted LAN-trust residual
- [ADR 29](29-nas-backup-target-beetle-m3-omv.md) — NAS (NFS/SMB decision pending)
- [ADR 39](39-nut-host-native.md) — NUT server host-native on `pve` (plaintext `upsd`, LAN-restricted by the host UFW)
