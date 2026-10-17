# 39 — Caddy on OPNsense — Evaluated and Rejected

**Source**: [Gemini chat 27 — "Caddy na OPNsense"](https://gemini.google.com/share/fa4ae290d23a)
(3.6 Flash; thread created 2026-10-12, published 2026-10-17). One question, one answer: whether
Caddy can run on the OPNsense router, and how.

**Scope**: the router as a **TLS-terminating reverse proxy** — a placement question for the Caddy
routing layer ([ADR 20](../decisions/20-caddy-single-routing-layer.md)), not a DNS question (that is
[research 38](38-technitium-dns.md)). The planned OPNsense install itself
([#96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96), [idea 07](../ideas/07-opnsense-futro-s930.md))
is unaffected.

**Status**: ❌ **Rejected** by the operator (2026-10-17). Evaluated, technically possible, not adopted.
The facts below are kept so the question does not need re-researching.

> ⚠️ **Verification status**: the mechanics are transcribed from the thread and were not exercised on
> a running OPNsense box. Plugin name, menu paths and package behaviour are thread claims.

---

## §1 — What the thread established

Caddy **can** run on OPNsense. Two paths exist:

### Method 1 — the `os-caddy` plugin (the thread's recommendation)

1. **Free ports 80/443 first.** OPNsense's own GUI listens on them; move it under
   `System → Settings → Administration` (e.g. HTTP `8080`, HTTPS `8443`) before Caddy starts.
2. Install `os-caddy` from `System → Firmware → Plugins`.
3. Configure under `Services → Caddy`: reverse-proxy sites, subdomains, access control lists (ACL),
   and TLS via ACME (Let's Encrypt / ZeroSSL) or custom CA certificates.

Properties that matter: the plugin is **community-maintained**, integrated with the WebGUI (MVC/API),
manages certificate lifecycle, and **keeps its configuration in `config.xml`** — so it survives
OPNsense backups and upgrades.

### Method 2 — the FreeBSD package (CLI)

```
pkg install caddy
sysrc caddy_enable="YES"          # /etc/rc.conf.d/caddy
service caddy start
```

Caddyfile at `/usr/local/etc/caddy/Caddyfile`. **Not integrated with the OPNsense backup**
(`config.xml`), so the Caddyfile needs its own backup path — a standing drift risk.

## §2 — Verdict and reasons

Rejected. The thread answers "can it be done", not "should it be done here":

| # | Reason | Source |
|---|---|---|
| 1 | It creates a **second routing layer**. The fleet's rule is one Caddyfile as the single routing source of truth, with a dedicated ingress appliance owning public/LAN entry | [ADR 20](../decisions/20-caddy-single-routing-layer.md), [ADR 24](../decisions/24-edge-ingress-appliance.md) |
| 2 | **Neither path is Ansible-managed.** The plugin's config lives in `config.xml`, the manual path lives in a hand-edited Caddyfile outside the backup — both outside the repo and outside host configuration management | ADR 10 pattern; thread fact |
| 3 | The **GUI port shift is permanent.** Moving the firewall's admin surface to 8080/8443 to free 80/443 is a maintenance cost paid forever for a role the router does not need | thread fact |
| 4 | **Separation of planes.** The Futro's job is routing, firewall, DHCP and later VPN ([idea 07](../ideas/07-opnsense-futro-s930.md)); TLS termination and certificate lifecycle are the service plane's job, already owned by the Caddy layer and `step-ca` ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)) | assessment |
| 5 | Nothing is gained: the proxy still has to exist elsewhere for services that do not live on the router, so the router copy would be a *second* configuration to keep in sync | assessment |

## §3 — If the question ever returns

- **Only `os-caddy`**, never the FreeBSD package — backup and upgrade integration is the deciding
  difference.
- Revisit only if the decision changes so that the **router becomes the single ingress** (i.e. the Caddy
  layer moves there wholesale rather than being duplicated), which would contradict
  [ADR 20](../decisions/20-caddy-single-routing-layer.md) and [ADR 24](../decisions/24-edge-ingress-appliance.md).
- The OPNsense box keeps its DNS-adjacent roles — DHCP and, potentially, a forwarding resolver in
  front of the `.internal` resolver ([research 38 §9](38-technitium-dns.md), [#96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96)).

## References

- [ADR 20](../decisions/20-caddy-single-routing-layer.md) — Caddy as the single routing layer
- [ADR 24](../decisions/24-edge-ingress-appliance.md) — dedicated edge ingress appliance
- [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) — the CA that issues the certificates
- [Idea 07](../ideas/07-opnsense-futro-s930.md) — OPNsense router on the Futro S930
- [Research 35 §7](35-private-ca-and-lan-naming.md) — the related OPNsense rejection for the CA stack
- [Research 38](38-technitium-dns.md) — the `.internal` resolver research
