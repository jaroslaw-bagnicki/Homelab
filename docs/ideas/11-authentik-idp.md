# Idea 11 — Authentik as the Lab Identity Provider

> One login, one MFA prompt and one audit trail for every LAN service: **Authentik** as the
> fleet's identity provider — in front of the services that have no login of their own
> (**Caddy `forward_auth`**) and behind the ones that speak **OIDC** or **LDAP**. Names and
> TLS are being solved ([idea 10](10-internal-ca-dns-stack.md),
> [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)); what remains is **who** is
> calling.

**Status**: 🧠 Idea — no lab decision taken yet  
**Date**: 2026-10-17 (hosting follow-up 2026-10-18)  
**Sources**: [Gemini — what Authentik is, Caddy/VictoriaLogs integration, local-only deployment](https://share.gemini.google/hybMZLfvSa85) (published 2026-10-17) · [Gemini — Authentik hosting and integration](https://gemini.google.com/share/df958018b379) (published 2026-10-18), written up as [research 42](../research/42-authentik-hosting.md)  
**Related**: [ADR 34](../decisions/34-lan-tls-only.md) (transport, not users) · [idea 10](10-internal-ca-dns-stack.md) (the access stack this sits on) · [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) / [ADR 37](../decisions/37-lan-name-space-internal.md) (TLS and names) · [ADR 36](../decisions/36-log-collector-fluentbit.md) / [ADR 35](../decisions/35-log-store-victorialogs.md) (log shipping) · [ADR 31](../decisions/31-static-address-scheme.md) (guest addressing) · [ADR 22](../decisions/22-k3s-arc-homelab.md) (k3s platform)

---

## Context

Authentication today is per service — and only some services have it:

| LAN service | Auth today |
|---|---|
| Proxmox VE UI | local PAM realm, no MFA |
| Netdata Parent | **none** — unauthenticated dashboard, the residual accepted in [ADR 27](../decisions/27-monitoring-strategy.md) |
| VictoriaLogs | HTTP basic auth, password from Key Vault |
| OMV NAS | local OMV users |

[ADR 34](../decisions/34-lan-tls-only.md) already draws the line: it governs **transport only**
and explicitly leaves authenticating *users* to each service. Every new service repeats the same
work, MFA does not exist, and nobody can answer "who logged in from where" across the fleet.

The planned access stack ([idea 10](10-internal-ca-dns-stack.md),
[#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126)) puts one Caddy in front of
everything on `.internal` — exactly the place to ask an identity provider whether a request may
pass.

## What Authentik brings (per the source thread)

- **Four integration paths**: OIDC/OAuth2, SAML 2.0, an LDAP outpost and proxy/forward auth — the
  widest spread of the compared candidates, so one directory serves apps with native SSO and apps
  without any.
- **Flows and stages, plus policies**: the login journey is assembled from stages (password, MFA,
  consent) and gated by rules — UI rules for simple cases, Python expression policies for the rest
  (group, source IP, request headers).
- **MFA**: TOTP, **WebAuthn/passkeys** (YubiKey, Windows Hello, Touch ID) and backup codes.
- **Outposts**: Go sidecars, embedded in the server or run next to the protected app, that handle
  proxy auth or emulate LDAP without exposing the admin plane; the proxy outpost is embedded by
  default, so it adds no container unless it runs externally.
- **Shape**: Python/Django server + worker and PostgreSQL — **Redis was removed in 2025.10**, so it
  is no longer part of the stack; Docker Compose or the Kubernetes Helm chart.
- **Audit**: events go to stdout — the thread's VictoriaLogs path is a collector, not a native
  integration.

## Where it fits the lab

- **The planned LAN Caddy is the forward-auth hook**: `forward_auth` per site asks the authentik
  proxy outpost and forwards the identity headers — no per-service login page.
- **Names and TLS are already planned**: `auth.internal` behind the wildcard in
  [idea 10](10-internal-ca-dns-stack.md), certificate from `step-ca`. That is also what makes
  **passkeys** usable — WebAuthn refuses bare IPs and plain HTTP.
- **Root distribution is the prerequisite**: passkeys and warning-free HTTPS need the private root
  on client devices ([#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144)).
- **Logs — reuse what exists**: ship authentik's stdout through the fleet's **Fluent Bit**
  ([ADR 36](../decisions/36-log-collector-fluentbit.md)) into VictoriaLogs
  ([ADR 35](../decisions/35-log-store-victorialogs.md)). The thread suggests Vector; Fluent Bit is
  already on every node.
- **Proxmox and OMV are the interesting targets**: Proxmox VE has a native OIDC realm in recent
  releases (to confirm on 9.2.2), otherwise the LDAP outpost covers it. OMV has **no native OIDC** —
  OMV 8 added a UI authentication *plugin framework*, not a provider — so today it is forward auth at the
  `edge` Caddy plus OMV's own login ([research 44](../research/44-omv-identity-integration.md)).

## Candidates

| Option | Verdict | Reason |
|---|---|---|
| **Authentik** | **Leading candidate** | OIDC + SAML + LDAP + forward auth in one; policies and MFA managed in the UI; cost is a server + worker + PostgreSQL stack (Redis removed in 2025.10) |
| Authelia | Fallback — if forward auth is the only need | Lightest (Go) and quickest to run, but OIDC-first — the thread notes SAML absent or limited — and file-driven with a minimal admin UI, so no directory for Proxmox/OMV |
| Keycloak | Rejected as overkill | Full enterprise feature set, JVM appetite and operational surface out of proportion to a homelab |

Entra ID appears in the thread only as a **federation source** (its guest-account scenario) — not
as a candidate for the lab's local identity provider.

## Placement — open

| Host | Shape | Assessment |
|---|---|---|
| **`lab`** (M910q) | Docker Compose now; k3s workload later | **Leading candidate** — 16 GB is the fleet's only real headroom, and `lab` is already the workload host; the k3s migration ([ADR 22](../decisions/22-k3s-arc-homelab.md)) lifts it later. The follow-up thread endorses it: the IdP beside the always-on stacks shortens the auth hop and local outpost management |
| `pve` | unprivileged LXC, fits the `.21x` guest scheme | **Tight** — 8 GB already carries Netdata, NUT, VictoriaLogs, `step-ca` and the planned HA VM + two LXCs; authentik adds a server, a worker and PostgreSQL (Redis is gone since 2025.10), plus an external outpost only if the embedded one is not used |
| `edge` | native or Docker beside Caddy | **No room** — 2 GB total ([hardware](../hardware.md)), and the ingress box already has to carry Caddy for the inbound plane ([ADR 24](../decisions/24-edge-ingress-appliance.md)) |
| `cloudlab` | Compose on the VPS | **Rejected** — an IdP for LAN services must not depend on the WAN, and it would put the admin plane on the public internet |

Hosting follow-up ([research 42](../research/42-authentik-hosting.md)): [ADR 40](../decisions/40-internal-dns-proxy-edge.md)'s `edge` Caddy gates each site with `forward_auth` ([`copy_headers`](https://caddyserver.com/docs/caddyfile/directives/forward_auth)), native-OIDC apps skip it, and audit goes out as JSON through the existing Fluent Bit ([ADR 36](../decisions/36-log-collector-fluentbit.md)). The IdP beside the always-on stacks is sound **only** with three guards: management planes stay reachable without SSO, resource limits keep logins fast, and the PostgreSQL dump ships **together** with `AUTHENTIK_SECRET_KEY`.

## Open questions

- **Single point of failure** — authentik down means every forward-auth service is down. What is
  the break-glass path (Caddy site bypass, local Proxmox realm) and the acceptable RTO? Portainer/
  Dockge, Caddy admin and the Proxmox UI must not sit behind SSO, or the fix needs the thing that broke.
- **Backup** — the PostgreSQL dump and `AUTHENTIK_SECRET_KEY` must be backed up **together** (MFA
  secrets and encrypted fields depend on the key); where does that pair fit the NAS/restic plan?
- **Outpost placement and the forward-auth hop** — an embedded outpost on the IdP host makes the
  `edge` Caddy call it across the LAN; that hop must be TLS or earn a row in the
  [ADR 34](../decisions/34-lan-tls-only.md) exception table, and a proxy outpost on the proxy host
  may be the cleaner shape. Verify the outpost's HTTPS listener.
- **Placement vs k3s timing** — if authentik lands on `lab` as a Compose stack it moves again when
  [ADR 22](../decisions/22-k3s-arc-homelab.md) executes; decide whether to wait, or to accept the
  second migration (Helm chart, or the Compose stack left beside k3s).
- **First protected services** — start with what cannot authenticate itself (Netdata) and what has
  native OIDC (Proxmox, Grafana later); leave basic-auth services alone until proven.
- **Federation scope** — GitHub/Entra ID as upstream IdP is possible; the thread's Entra
  guest-account mapping is a B2B feature the lab has no use for. Local accounts + passkeys first.
- **Claims to verify upstream** — Proxmox OIDC realm, OMV LDAP support, and the outpost's HTTPS listener; the
  follow-up thread's Compose file is from 2024 and its env-var spellings are unverified (the Redis removal it
  predates is confirmed — [research 42](../research/42-authentik-hosting.md)).

## References

- [Gemini thread — Authentik: overview, Caddy/VictoriaLogs integration, local-only deployment](https://share.gemini.google/hybMZLfvSa85)
- [Gemini thread — Authentik hosting and integration](https://gemini.google.com/share/df958018b379) → [research 42](../research/42-authentik-hosting.md)
- [ADR 34](../decisions/34-lan-tls-only.md) · [idea 10](10-internal-ca-dns-stack.md) · [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) · [ADR 37](../decisions/37-lan-name-space-internal.md) · [ADR 36](../decisions/36-log-collector-fluentbit.md) · [ADR 35](../decisions/35-log-store-victorialogs.md) · [ADR 31](../decisions/31-static-address-scheme.md) · [ADR 22](../decisions/22-k3s-arc-homelab.md) · [ADR 40](../decisions/40-internal-dns-proxy-edge.md)
