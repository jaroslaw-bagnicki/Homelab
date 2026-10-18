# 42 — Authentik Hosting — Placement, Caddy Forward Auth, Guest Federation and Local-Only Deployment

**Source**: Gemini thread (3.6 Flash), created 2026-10-16 02:10, published 2026-10-18 07:23 —
"Czym jest Authentik" ([chat](https://gemini.google.com/share/df958018b379)). Eight turns, in Polish;
transcribed here in English.

**Scope**: the **hosting and integration** half of [idea 11](../ideas/11-authentik-idp.md) — where
Authentik should run in this fleet, how Caddy gates traffic with it, how its audit trail reaches
VictoriaLogs, how Entra ID guests map onto it, what a LAN-only deployment contains, and what changes when
the always-on container workload moves to its own Docker node. The product comparison (Authentik vs
Authelia vs Keycloak) is already in idea 11 and is **not repeated**.

**Status**: 📝 Analysis — **no lab decision taken**. The thread refines idea 11's open placement question;
it does not settle it. Break-glass and backup remain open (§9).

> **Verification status.** Claims were checked against the authentik release notes and Caddy's directive
> reference in this pass. The thread's Docker Compose stack is from an older release and did **not** survive
> the check (§8); the live fleet facts (Fluent Bit present, `lab` as the Docker node, `edge` as ingress)
> come from [ADR 36](../decisions/36-log-collector-fluentbit.md), [ADR 24](../decisions/24-edge-ingress-appliance.md)
> and [overview](../overview.md).

---

## Decision summary

| Question | What the thread lands on |
|---|---|
| How Caddy enforces Authentik | **`forward_auth`** to the embedded proxy outpost with `copy_headers`; `caddy-security` (OIDC plugin) is the alternative when native OIDC is preferred (§2) |
| Audit trail into VictoriaLogs | No native integration — ship `stdout` through a collector. The thread proposes **Vector**; this fleet already runs **Fluent Bit** (§3) |
| Entra ID guest accounts | Authentik has no `userType` — model guests as a **group** fed by a property mapping on the OIDC/SAML claim (§4) |
| Local-only deployment | Compose stack behind Caddy with `tls internal`, local DNS for every subdomain, HTTPS mandatory for **passkeys** (§5) |
| Where to run it, first answer | **Not** k3s (churn) and **not** `edge` (2 GB) — an LXC/VM on the Proxmox node, so the IdP does not depend on the platform it protects (§6) |
| Where to run it, given a Docker node | **On the Docker node is fine** — shorter auth latency, local Docker outpost management, one deployment model — with three guards: break-glass, resource limits, PostgreSQL backup (§6–§7) |
| Integration models with services | **Forward auth** for services with no login; **native OIDC** for services that have one — Caddy just proxies for the latter (§6) |
| Verdict | Pragmatic and defensible; the risk that matters is not placement but **self-dependency** (§7) |

---

## Context

[Idea 11](../ideas/11-authentik-idp.md) settled *what* Authentik is for — SSO, MFA and forward auth for
LAN services — and left *where it runs* open, with `lab` as the leading candidate. Between that capture and
this thread the operator added a planned **Docker node for always-on containerised services** — in this
fleet, `lab`, the M910q workload host, Docker today → k3s later
([ADR 22](../decisions/22-k3s-arc-homelab.md)) — and asked whether Authentik belongs there. That question
drives the second half of this document.

## §1 — What Authentik is, compactly

> Thread summary; the protocol list and the flow/stage model are consistent with the product. **The stack
> description is stale — see §8.**

- **Protocols**: OIDC/OAuth2, SAML 2.0, LDAP (LDAP outpost), and **proxy / forward auth** for applications
  with no auth of their own (Traefik, nginx, Caddy, Envoy).
- **Flows and stages**: the login journey is assembled from stages (password, MFA, consent, e-mail
  verification, password change) so policies like "MFA only from outside the LAN" are configuration.
- **Policies**: UI rules or Python expression policies, matched on group, source IP, request headers, time.
- **MFA**: TOTP, **WebAuthn/passkeys** (YubiKey, Windows Hello, Touch ID), static backup codes, SMS/e-mail.
- **Outposts**: Go sidecars — proxy or LDAP — that can run next to the protected application without
  exposing the admin plane. The proxy outpost is embedded in the server by default.
- **Federation**: GitHub, Google, Microsoft/Entra ID, Discord, Telegram (2025.10) as upstream sources.

What matters for this fleet: the **proxy outpost** is the hook the planned LAN Caddy needs, and
**passkeys** are only usable over HTTPS with a real FQDN — which the `.internal` + `step-ca` stack
([ADR 37](../decisions/37-lan-name-space-internal.md), [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md))
now provides.

## §2 — Caddy integration

> Caddy syntax **verified upstream**; the authentik endpoints are the thread's and are **unverified**
> against a running instance.

**Method 1 — standard `forward_auth` (recommended).** In authentik: *Applications → Providers →* new
**Proxy Provider** with the external host set to the protected FQDN; *Applications → Applications →* new
application bound to that provider; confirm it is assigned to the outpost (embedded by default). The outpost
listens on **9000** (HTTP) / **9443** (HTTPS).

```caddyfile
app.internal {
    # the outpost answers the login flow on the protected hostname itself
    handle /outpost.goauthentik.io/* {
        reverse_proxy http://authentik-server:9000
    }
    handle {
        forward_auth http://authentik-server:9000 {
            uri /outpost.goauthentik.io/auth/caddy
            copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
        }
        reverse_proxy http://my-internal-app:8080
    }
}
```

Routing that path is part of the mechanism, not an optional extra: the check itself would pass, but the
redirect issued after it would land on the protected site instead of authentik, so the login flow cannot
complete (`/outpost.goauthentik.io/*` on the protected hostname must reach the outpost —
[verified upstream](https://docs.goauthentik.io/add-secure-apps/providers/proxy/forward_auth)).

Caddy's `forward_auth` is a wrapper over `reverse_proxy`: it issues a **GET** to the auth upstream with the
`uri` rewritten, and on a `2xx` copies the listed response headers onto the original request
([verified upstream](https://caddyserver.com/docs/caddyfile/directives/forward_auth)). Any other status is
passed back to the client — typically the login redirect.

**Method 2 — OIDC through `caddy-security`.** Compile Caddy with `greenpau/caddy-security` (or use a
prebuilt image), create an **OAuth2/OpenID Provider** in authentik, and configure the realm against
authentik's `/application/o/authorize/` and `/application/o/token/` endpoints. The thread's recommendation
is Method 1: all access logic (policies, MFA, groups) stays in the authentik UI instead of splitting between
two configuration surfaces.

The header that reaches the application is the payoff — `Remote-User`, `Remote-Groups`, `Remote-Name`,
`Remote-Email` (or `X-Authentik-Username`) let a service trust an upstream identity when it supports header
authentication.

## §3 — Audit trail into VictoriaLogs

> **Correction:** the thread's Vector recommendation ignores that this fleet already runs **Fluent Bit** on
> every node ([ADR 36](../decisions/36-log-collector-fluentbit.md)) shipping into
> [VictoriaLogs](../decisions/35-log-store-victorialogs.md). Reusing it means no second collector.

There is **no native authentik → VictoriaLogs integration**: authentik writes audit events and logs to
`stdout`/`stderr` (or files), and VictoriaLogs ingests over its HTTP API. A collector is therefore always
in the path.

The thread's step that *does* matter is the log **format** — structured JSON is far easier to query than
plain text:

```yaml
AUTHENTIK_LOG_LEVEL: info
AUTHENTIK_LOG__FORMAT: json
```

Vector variant (thread), if one were introduced:

```yaml
sources:
  authentik_logs:
    type: docker_logs
    include_containers: [authentik-server, authentik-worker]
sinks:
  victorialogs:
    type: http
    inputs: [authentik_logs]
    uri: "http://victorialogs:9428/insert/jsonline?_stream_fields=service,event,logger"
    encoding:
      codec: ndjson
```

Fluent Bit variant in the fleet's existing shape (`http` output, JSON lines, `_time` as RFC 3339) — the
ingest contract `/insert/jsonline` and the stream/msg/time fields are the ones already documented in
[research 34](34-log-collector-options.md).

What the trail buys, per the thread: successful and failed logins, password changes, MFA enrolment and
permission changes — queryable in LogsQL as `event:"failed_login"` or `user.username:"<name>"`. For this
lab it also supplies the "who logged in from where" answer that [idea 11](../ideas/11-authentik-idp.md)
names as missing today.

## §4 — Entra ID guest accounts

> Thread claim; the property-mapping API surface is **unverified** on a current release.

Authentik has **no guest user type**. Every user from an external IdP becomes a normal local user object,
so "guest" is a modelling choice:

| Scenario | Shape |
|---|---|
| Everyone arriving from Entra ID is external | A dedicated group (e.g. `EntraID-Guests`) set as the enrollment default for that source |
| Tenant has both `Member` and `Guest` | Add a `userType` claim in Entra ID, read it in a **property mapping**, assign the guest group from the value |

```python
user_type = ak_token.get("userType", "").lower()
if user_type == "guest":
    pm_add_user_to_group(user, "EntraID-Guests")
```

Then gate with a **group membership policy** on each application, so guests never inherit fleet-wide access.
Two operational notes from the thread: a disabled/deleted Entra account stops authenticating because no
token is issued, and a local MFA stage can be stacked on top of Entra's own verification.

**Fit for this lab**: [idea 11](../ideas/11-authentik-idp.md) already scoped federation out — the Entra
guest/B2B pattern is a feature the lab has no use for. Recorded here for completeness only.

## §5 — Local-only deployment (no WAN exposure)

Shape: a LAN client resolves `*.internal` to a reverse proxy, which terminates TLS and proxies to authentik
or to a protected service; nothing is published to the internet.

Steps as the thread gives them:

1. **`.env`** — `PG_PASS`, `AUTHENTIK_SECRET_KEY` (generate with `openssl rand -base64 36`), optionally
   `AUTHENTIK_DISABLE_UPDATE_CHECK=true` and `AUTHENTIK_ERROR_REPORTING__ENABLED=false` for a sealed LAN.
2. **Compose stack** — `server` + `worker` + PostgreSQL (+ Redis in the thread's version, see §8).
3. **First login** — `http://<host>:9000/if/flow/initial-setup/` sets the `akadmin` password.
4. **TLS** — the thread offers two paths: Caddy's own local CA (`tls internal`) or a **DNS-01** certificate
   for a public name that resolves to a LAN address. For this fleet a third, better path exists: a
   short-lived leaf from `step-ca` ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)).

```caddyfile
auth.internal {
    tls internal
    reverse_proxy http://authentik-server:9000
}
```

Programmatic requirements the thread correctly highlights:

- **Local DNS for every subdomain** — `auth.internal`, `grafana.internal`, … must all resolve to the proxy
  ([ADR 40](../decisions/40-internal-dns-proxy-edge.md), Technitium on `edge`).
- **WebAuthn needs HTTPS and a stable FQDN.** Browsers refuse passkeys on bare IPs and on plain HTTP
  (except `localhost`). This is the single hard dependency between idea 11 and the CA work.
- **Root distribution to clients** is a prerequisite for warning-free HTTPS — already tracked as
  [runbook 39](../runbooks/39-trust-private-ca.md).

## §6 — Placement in this fleet

The thread has two answers, in sequence.

**Answer 1 — before the Docker node existed.** Put authentik in an **LXC/VM on the Proxmox node**, not on
k3s and not on `edge`:

- Not k3s: the IdP must not depend on the platform whose workloads it protects — a cluster re-arrangement
  would lock the operator out of everything it gates.
- Not `edge`: 2 GB total beside the ingress role ([hardware](../hardware.md), [ADR 24](../decisions/24-edge-ingress-appliance.md)).
- Proxmox: always-on by design, independent lifecycle.

**Answer 2 — after the Docker node was introduced.** Authentik **on the Docker node is a good pragmatic
choice**, with a shorter auth hop and one deployment model for every always-on stack.

Traffic shape the thread draws:

```text
[ LAN client ] ──> [ edge: Caddy ] ──┬──> [ authentik ] (Docker node or LXC)
                                     └──> [ protected service ] (k3s or Docker node)
```

Two integration patterns, per service:

| Pattern | When | Caddy does |
|---|---|---|
| **Forward auth** | The service has no login of its own (dashboards, Dozzle, internal APIs) | `forward_auth` to the outpost, then `reverse_proxy` |
| **Native OIDC** | The service speaks OIDC (Grafana, Portainer, Immich, ArgoCD, Nextcloud) | plain `reverse_proxy` — the app redirects to authentik itself |

The second pattern is the one that is easy to over-engineer: do **not** stack `forward_auth` in front of an
application that already authenticates, or the user logs in twice.

**k3s later**: the same split holds — an authentik Kubernetes outpost from the Helm chart if the ingress
should gate traffic, plus optional OIDC on `kube-apiserver` for `kubectl` identity.

## §7 — Risks, and what the thread says to do about them

| Risk | Why it matters | Mitigation |
|---|---|---|
| **Chicken-and-egg** | If the management plane (Portainer/Dockge, Caddy admin, Proxmox UI) is itself behind authentik, an IdP outage removes the tools needed to fix it | Low-level management paths must **not** depend on SSO: SSH keys, local admin logins, a documented Caddy bypass |
| **Resource contention** | authentik server + worker + PostgreSQL is heavier than a typical Go service; an ML workload (e.g. Immich face recognition) on the same node slows every login in the lab | Container resource limits per stack; keep headroom for the IdP |
| **Database loss** | The PostgreSQL dump alone is not restorable without `AUTHENTIK_SECRET_KEY` — MFA secrets and encrypted fields depend on it | Back up the **dump and the key together**, off-node (NAS/restic plan) |
| **Docker socket** | The `worker` mounts `/var/run/docker.sock` to manage local outposts — effectively root on the host | Keep it local to the IdP node; never share the socket across hosts |

The thread's own verdict: moving authentik onto the Docker node is sound *provided* the backup and the
SSO-independent break-glass path are handled, and it reduces the number of moving parts (no dedicated LXC
just for auth).

## §8 — What did not survive the check

The thread's Compose file is `ghcr.io/goauthentik/server:2024.8.3` with **Redis** for caching, tasks, the
embedded outpost session store and WebSockets. That is two releases of drift:

- **Redis is gone.** authentik **2025.10** migrated caching, tasks, the embedded outpost and WebSockets to
  PostgreSQL and removed Redis entirely — the upgrade notes say to run compose with `--remove-orphans` so
  the Redis container is removed, and that authentik now needs roughly **50 % more Postgres connections**
  ([verified upstream](https://docs.goauthentik.io/releases/2025.10/)). The stack is therefore
  **server + worker + PostgreSQL**, and any Redis guidance — including [idea 11](../ideas/11-authentik-idp.md)'s
  "Redis removed in 2025.10" note, which this confirms — is otherwise obsolete.
- **`AUTHENTIK_INSECURE`** and the port mapping in the thread's file belong to a proxy-TLS-offload setup;
  the flag's current spelling and scope must be re-read against the release's configuration reference
  (**unverified**).
- **`tls internal`** is Caddy's *own* local CA, not `step-ca`. It works for a quick test and would add a
  **second** root to every client — contrary to the single-root model of
  [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md). The fleet's certificate source is `step-ca`.
- **Vector over Fluent Bit** — the collector decision is already made
  ([ADR 36](../decisions/36-log-collector-fluentbit.md)); a second shipper is not introduced for one app.
- **Entra guest/B2B** — out of scope per idea 11; recorded, not adopted.

## §9 — Open questions

- **Break-glass.** What exactly bypasses authentik: a Caddy site imported *without* `forward_auth`, a
  separate management port, or nothing at all (SSH only)? And what RTO is acceptable when the IdP is down?
- **Placement** — Docker node (`lab`) versus an LXC on `pve`. The thread's second answer favours the Docker
  node; idea 11's headroom argument also pointed at `lab`. This needs a decision, and it interacts with
  [ADR 22](../decisions/22-k3s-arc-homelab.md) (the Docker node becomes the k3s node).
- **Backup pair.** Where does the PostgreSQL dump + `AUTHENTIK_SECRET_KEY` live so both are restorable
  together — the NAS/restic target of [ADR 02](../decisions/02-backup-strategy-restic-blob.md)?
- **Outpost hop.** An embedded outpost on `lab` means `edge`'s Caddy calls it **across the LAN** for every
  request; that hop must be TLS or earn an exception in [ADR 34](../decisions/34-lan-tls-only.md), and
  an external proxy outpost on `edge` is the alternative shape. The outpost's HTTPS listener is
  **unverified**.
- **First protected services.** idea 11's shortlist stands: Netdata (no auth at all), then Proxmox/Grafana
  over native OIDC — but Proxmox's native OIDC realm still needs confirming on 9.2.2.
- **Version baseline.** Which release to pin — the image tag, not the thread's 2024.8.3 — and whether the
  Compose stack or the Helm chart is the long-term shape once k3s exists.
- **Audit retention.** authentik events are security-relevant; the VictoriaLogs retention in
  [ADR 35](../decisions/35-log-store-victorialogs.md) may need a carve-out for the `service:authentik` stream.

## References

- [Gemini thread — Authentik: overview, Caddy/VictoriaLogs integration, local-only deployment](https://gemini.google.com/share/df958018b379)
- [Idea 11 — Authentik as the Lab Identity Provider](../ideas/11-authentik-idp.md)
- [ADR 38 — Private CA hierarchy and custody](../decisions/38-private-ca-hierarchy-and-custody.md) · [ADR 37 — `.internal` name space](../decisions/37-lan-name-space-internal.md) · [ADR 40 — Internal DNS and reverse proxy on `edge`](../decisions/40-internal-dns-proxy-edge.md) · [ADR 34 — LAN services are TLS-only](../decisions/34-lan-tls-only.md)
- [ADR 36 — Fluent Bit collector](../decisions/36-log-collector-fluentbit.md) · [ADR 35 — VictoriaLogs store](../decisions/35-log-store-victorialogs.md) · [research 34 — Log collector options](34-log-collector-options.md)
- [ADR 22 — k3s + Arc platform](../decisions/22-k3s-arc-homelab.md) · [ADR 24 — Edge ingress appliance](../decisions/24-edge-ingress-appliance.md) · [runbook 39 — Trust the private CA](../runbooks/39-trust-private-ca.md)
- [Research 41 — Kerberos and machine identity](41-machine-identity-kerberos.md) · [research 36 — step-ca and machine identity](36-step-ca-machine-identity.md)
- Upstream: [authentik 2025.10 release notes](https://docs.goauthentik.io/releases/2025.10/) · [Caddy `forward_auth`](https://caddyserver.com/docs/caddyfile/directives/forward_auth)
