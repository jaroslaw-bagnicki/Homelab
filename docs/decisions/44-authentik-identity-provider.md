# Authentik as the Fleet Identity Provider — an LXC on `pve`, FreeIPA Source, SSO-Exempt Management Planes

**Date:** 2026-10-27
**Status:** Accepted

---

## Context

Authentication in the lab is per service and mostly absent: Netdata has no login at all, VictoriaLogs has
basic auth, Proxmox uses a local PAM realm, OMV its own users. MFA exists nowhere, and no one can answer
"who logged in from where" across the fleet.

Two ADRs already place Authentik in the stack without deciding how it runs: [ADR 41](41-ssh-certificates-step-ca.md)
names it the human identity source for SSH certificates, and [ADR 43](43-freeipa-domain-realm.md) makes it
the people-facing front door over FreeIPA. What neither settles is placement, reachability, what it may
gate, and how its state is recovered. [Research 42](../research/42-authentik-hosting.md) works that half
through, and [idea 11](../ideas/11-authentik-idp.md) carries the product comparison.

## Decision

**Adopt Authentik as the fleet's identity provider — a guest on `pve`, reached at `auth.internal` over a
`step-ca` leaf, with FreeIPA as its only user source and management planes permanently outside SSO.**

1. **Host `pve`**, as an unprivileged LXC running the Compose stack (server, worker and PostgreSQL inside
   the guest). The always-on tier already lives there — the domain ([ADR 43](43-freeipa-domain-realm.md)),
   the CA ([ADR 38](38-private-ca-hierarchy-and-custody.md)) and VictoriaLogs
   ([ADR 35](35-log-store-victorialogs.md)) — so the IdP shares one lifecycle with the things it
   authenticates. It stays deliberately **outside the k3s cluster** ([ADR 22](22-k3s-arc-homelab.md)) that
   will consume it: the cluster authenticates *against* the IdP, and the IdP must not ride the migration
   that reshapes the platform. `edge` has 2 GB and cannot carry it
   ([ADR 24](24-edge-ingress-appliance.md)); a small VM on `pve` is the documented fallback if
   Docker-in-LXC proves unstable. The memory cost is accepted because the **second Proxmox node**
   ([idea 15](../ideas/15-second-proxmox-node.md)) is being built now — until it lands, `pve` is the binding
   constraint and the stack ships with explicit container memory limits.
2. **Server + worker + PostgreSQL.** Redis is not part of the stack — 2025.10 removed it — and the release
   is pinned to a current tag, not the older Compose shape recorded in the research thread.
3. **`auth.internal`, proxied by the `edge` Caddy ([ADR 40](40-internal-dns-proxy-edge.md)) with a
   short-lived `step-ca` leaf ([ADR 38](38-private-ca-hierarchy-and-custody.md)).** Caddy's `tls internal`
   is rejected — it would add a second root to every client. WebAuthn/passkeys need exactly this shape:
   HTTPS on a stable FQDN.
4. **FreeIPA over LDAPS is the only user source** ([ADR 43](43-freeipa-domain-realm.md)). No local accounts
   beyond the bootstrap `akadmin`. People are directory objects; Authentik authenticates them and holds
   their MFA enrolment.
5. **Two integration patterns, never both for one service.** `forward_auth` to the proxy outpost for
   services with no login of their own; plain proxying for services that speak OIDC and redirect
   themselves. Stacking `forward_auth` in front of an app that already authenticates buys a double login.
6. **Management planes never sit behind SSO** — the Proxmox UI, Caddy admin, Portainer and SSH stay on
   their own credentials. The IdP must not be the thing that locks the operator out of fixing the IdP.
7. **State is recovered as a pair.** The PostgreSQL dump and `AUTHENTIK_SECRET_KEY` are backed up and
   restored **together** to the NAS target ([ADR 29](29-nas-backup-target-beetle-m3-omv.md)) — MFA secrets
   and encrypted fields are unreadable without the key. The restore is rehearsed before the first service
   is gated.
8. **Audit and application logs leave as JSON on stdout** through the existing Fluent Bit
   ([ADR 36](36-log-collector-fluentbit.md)) into VictoriaLogs ([ADR 35](35-log-store-victorialogs.md)).
   No second collector.
9. **The embedded proxy outpost is the shape that runs.** The `edge` → `pve` hop is TLS
   ([ADR 34](34-lan-tls-only.md)); if the outpost's HTTPS listener proves unusable, an external proxy
   outpost on `edge` is the fallback and earns an ADR 34 exception row — never a plaintext path.
10. **Scope: LAN-only.** Nothing is published to the WAN, no cloud IdP is federated (an Entra ID guest
    pattern is a B2B feature this lab has no use for), and no local-account tree grows in parallel with
    the directory.

## Consequences

- One login, one MFA prompt and one audit stream for every service behind it — the gap idea 11 opened
  with is closed for the services that are gated, not for the fleet by decree.
- **The IdP becomes an availability dependency for every gated service.** That is what item 6 and the
  break-glass path bound: existing sessions and existing SSH certificates survive an outage, and new
  logins do not. The domain and the IdP now share one node, so a `pve` failure costs **both** kinds of new
  login at once — and these two guests are the first candidates for the second node's ZFS replication
  ([idea 15](../ideas/15-second-proxmox-node.md)).
- **`pve` inherits a stack that must not be starved.** Container resource limits are part of the decision,
  not tuning — every login in the lab queues behind it. The node now carries the domain, the CA, the log
  store and the IdP on 8 GB, which is what makes the second node load-bearing rather than optional.
- **The k3s migration loses a passenger but gains a dependency.** Authentik no longer moves with `lab`; in
  exchange the cluster's identity comes from a guest on `pve`, so that node's availability now gates
  cluster logins as well as LAN ones.
- **The worker mounts a Docker socket** to manage local outposts — root-equivalent **inside that guest**.
  The socket is the LXC's own and is never mounted from the host or shared across hosts.
- [ADR 41](41-ssh-certificates-step-ca.md)'s OIDC provisioner and [ADR 43](43-freeipa-domain-realm.md)'s
  LDAPS bind now have a concrete target, and claim/group gating lives in the Authentik UI — which is what
  makes `step-ca`'s lack of per-provisioner policy acceptable.
- Two secrets to protect instead of one (database password and `AUTHENTIK_SECRET_KEY`), both in Key Vault
  until the secret-store workstream changes that.
- **Carried as implementation gates, unverified upstream:** the Proxmox OIDC realm on the running version,
  the outpost's HTTPS listener, and the current spelling and scope of `AUTHENTIK_INSECURE`.

### Alternatives Considered

- **Docker on `lab`** — the earlier leaning: 16 GB of headroom and the always-on Compose stacks already
  there. Rejected because `lab` is the node in motion (Docker today, k3s next) and the IdP would ride the
  migration that reshapes the platform it protects; headroom does not buy a stable lifecycle.
- **A VM on `pve` instead of an LXC** — heavier: an extra kernel and a fixed RAM reservation on the fleet's
  tightest node. Kept as the fallback if Docker-in-LXC misbehaves, not as the default.
- **Inside the k3s cluster** — rejected: the IdP must not be reconciled by the platform whose access it
  governs, and a cluster re-arrangement would remove every login needed to fix it
  ([research 42 §6](../research/42-authentik-hosting.md) calls this self-dependency the risk that matters).
- **Waiting for the second Proxmox node before deploying** — rejected: it would gate SSO, and behind it the
  human certificate path, on cluster build-out. The guest is small, and it can be replicated once the pool
  exists.
- **Authelia** — lighter, and enough if forward auth were the only need, but OIDC-first with no directory
  for Proxmox/OMV, file-driven, and no admin UI.
- **Keycloak** — the full enterprise surface, a JVM and an operational model out of proportion to five
  nodes.
- **Caddy `tls internal`** — rejected: a second root to distribute, contrary to the single-anchor model of
  [ADR 38](38-private-ca-hierarchy-and-custody.md).
- **A second log shipper (Vector)** — rejected: Fluent Bit already runs on every node.
- **Federating a cloud IdP (Entra ID, GitHub)** — out of scope, the same stance as
  [ADR 41](41-ssh-certificates-step-ca.md): no cloud IdP in the lab's login path.
- **Waiting for k3s before deploying** — rejected: it would gate SSO, and behind it the human
  certificate path, on the largest item in the backlog.

## References

- [Idea 11 — Authentik as the lab identity provider](../ideas/11-authentik-idp.md) · [research 42 — Authentik hosting](../research/42-authentik-hosting.md)
- [ADR 41 — SSH certificates](41-ssh-certificates-step-ca.md) · [ADR 43 — FreeIPA domain](43-freeipa-domain-realm.md) · [ADR 42 — PKI topology](42-pki-topology-sibling-cas.md)
- [ADR 38 — private CA](38-private-ca-hierarchy-and-custody.md) · [ADR 40 — DNS and proxy on `edge`](40-internal-dns-proxy-edge.md) · [ADR 34 — LAN TLS only](34-lan-tls-only.md) · [ADR 36 — Fluent Bit](36-log-collector-fluentbit.md) · [ADR 35 — VictoriaLogs](35-log-store-victorialogs.md) · [ADR 29 — NAS backup target](29-nas-backup-target-beetle-m3-omv.md) · [ADR 22 — k3s](22-k3s-arc-homelab.md)
- Implementation: [#165](https://github.com/jaroslaw-bagnicki/Homelab/issues/165) · [plan 01](../plans/01-identity-and-access-stack.md) · [idea 15 — second Proxmox node](../ideas/15-second-proxmox-node.md)
