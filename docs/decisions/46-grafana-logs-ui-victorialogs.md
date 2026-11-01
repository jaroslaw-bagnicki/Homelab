# Grafana as the Log Pane — VictoriaLogs Retained, Grafana on the `monitor` Guest

**Date:** 2026-10-31
**Status:** Proposed

---

## Context

VictoriaLogs is the Tier B log store — a single binary on LXC 214 (currently `vtstack`) with 30-day
retention, native TLS, HTTP basic auth, an in-LXC LAN rule and a TLS syslog listener
([ADR 35](35-log-store-victorialogs.md)). It works, but its built-in `/select/vmui` UI is too thin for
the exploration the operator actually wants: field/value discovery, patterns, dashboards and saved
views. The complaint is the **pane**, not the engine.

Grafana was considered and deferred when the store was chosen — [ADR 35](35-log-store-victorialogs.md)
records "Grafana is not a prerequisite", and [ADR 27](27-monitoring-strategy.md) leaves the dashboard
component to a future ADR. The operator now wants Grafana, running as a Docker Compose service **inside
LXC 214**.

The guest is scheduled to change before Grafana lands: it moves to the new **`pve2`** (OptiPlex 7040,
8 GB, 256 GB) and is renamed **`monitor`**, keeping `192.168.2.214` ([Idea 15](../ideas/15-second-proxmox-node.md)).
The operator also intends the guest to become the central **metrics** store by moving the Netdata Parent
into it; that is a separate, deferred decision (research 50).

Three pane paths exist, analysed in [research 49](../research/49-grafana-logs-ui-victorialogs-vs-loki.md):
the official VictoriaLogs Grafana plugin; a community Loki-API proxy that enables Grafana's Logs
Drilldown without Loki; and migrating the store to Loki. Fixed constraints: TLS-only on the LAN
([ADR 34](34-lan-tls-only.md)), no host-firewall coverage for container traffic, an 8 GB Proxmox host,
and a collector contract that already works ([ADR 36](36-log-collector-fluentbit.md)).

## Decision

**Keep VictoriaLogs. Adopt Grafana as the log pane on the `monitor` guest, with the official
`victoriametrics-logs-datasource` plugin.**

- **Store unchanged** — no migration to Loki, no change to the Fluent Bit output contract, no change
  to the `:6514` syslog listener. Loki is rejected: it would reverse [ADR 35](35-log-store-victorialogs.md),
  replace a cardinality-safe engine with label discipline, require an authentication proxy, lose the
  router's syslog path or add a relay, and weaken the disk safety valve — all for a UI preference.
- **Host: LXC 214, `monitor`** — rename `vtstack` → `monitor` before deployment and move the guest to
  `pve2`, keeping `.214` so the collector and datasource need no change. The on-disk path stays
  `/opt/vtstack` — the runbook made it stable so the store can be reorganised without moving data.
- **Resources: 4 GiB RAM / 64 GiB rootfs** on `pve2` (256 GB), up from 2 GiB / 16 GiB. Four GiB is
  the initial envelope for VictoriaLogs + Grafana: the store keeps `-memory.allowedPercent=60`
  (~2.4 GiB), leaving ~1.6 GiB for Grafana, Docker and the OS. The 16 GiB volume cannot carry the
  store, Grafana and the future Netdata Parent's ~10 GiB dbengine; 64 GiB does, with room for
  VictoriaMetrics/Traces later. **The guest rises to 6 GiB only when the Netdata Parent lands**
  (ADR 47), not before. Measure `pve2` headroom and Grafana RSS before build.
- **Grafana OSS** (`grafana/grafana`, explicit tag) in `/opt/vtstack/grafana`, `restart:
  unless-stopped`, `network_mode: host` on `:3000` so the **in-LXC UFW** filters it; allow `3000/tcp`
  from `192.168.2.0/24` only.
- **Native TLS** (`GF_SERVER_PROTOCOL=https`), a self-signed certificate initially — the same residual
  the store accepts — moving to a `step-ca` leaf once root distribution
  ([#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144)) is complete.
- **`grafana.internal`** resolves to `192.168.2.214` as a **static A record** and is served directly.
  Routing it through the edge Caddy remains an option, not a requirement — the store and Netdata
  already serve native TLS directly ([ADR 40](40-internal-dns-proxy-edge.md)).
- **Plugin pinned** — `GF_PLUGINS_PREINSTALL=victoriametrics-logs-datasource@0.33.1`; the plugin
  requires Grafana ≥ 10.4.0, and the store's `v1.52.0` satisfies the plugin Drilldown's ≥ 1.21 / ≥ 1.33
  requirements. Image and plugin are upgraded together.
- **Datasource over loopback** — `https://127.0.0.1:9428`, basic auth `vlogs`, verification skipped or
  pinned to the store's certificate. The query travels inside the LXC; the store's TLS and auth remain.
- **Secrets from Azure Key Vault** — the existing `victorialogs-basic-auth-password`, plus
  `grafana-admin-password` and `grafana-secret-key`, written to root-only files and read via
  `GF_*__FILE`. Grafana encrypts datasource credentials with `secret_key`, so it must be stable.
- **Datasource and dashboards provisioned from the repo** — reproducible; the embedded SQLite database
  holds only users and preferences. Local `admin` is break-glass; Authentik OIDC is the planned normal
  path ([ADR 44](44-authentik-identity-provider.md)), not a day-one dependency.
- **`vmui` stays** as the break-glass UI. Grafana is the preferred pane, not a prerequisite — the store
  remains independently queryable.

### Deferred — the Netdata Parent on `monitor`

The operator intends `monitor` to also host the **Netdata Parent** as a container, making it the central
metrics store beside VictoriaLogs and Grafana. **This is an intent, not a decision in this ADR.** It
requires a separate ADR (47) and one structural condition: **`pve1` and `pve2` must each run a
host-native Netdata child** that streams to the containerised Parent, because a Parent in an LXC cannot
read the Proxmox hosts' VM/CT cgroups or `/etc/pve` names ([research 50](../research/50-netdata-cloud-costs-and-stream-identity.md) §3).

- Research 50 sizes a Parent aggregating 5–15 children at **1–2 GiB RAM**; when it lands, the guest
  rises from 4 GiB to **6 GiB** and VictoriaLogs drops to `-memory.allowedPercent=50` (3 GiB), leaving
  room for the Parent, Grafana and the OS.
- Research 50 §7 is the dbengine/registry migration procedure; **do not copy the old Parent's
  `machine_guid`** if `pve1` becomes a child — copy `dbengine` for the children's history and mint a
  fresh GUID for the new Parent, or accept a fresh start.
- The move is gated on the 6 GiB guest (raised from the initial 4 GiB), the 64 GiB disk, the host-native
  children, and a scratch migration test. Until ADR 47, the Parent stays host-native on `pve1` and
  [ADR 27](27-monitoring-strategy.md) stands.

**Amendments.** [ADR 35](35-log-store-victorialogs.md): the store's guest is renamed `monitor` and moved
to `pve2`, and its resource envelope grows — the store choice itself is unchanged. [ADR 27](27-monitoring-strategy.md):
Grafana is adopted for **logs only**; the Netdata Parent move is recorded as intent, to be decided by
ADR 47.

**Not adopted now:** the community LogQL→LogsQL proxy that would enable Grafana's Loki-only Logs
Drilldown app ([research 49](../research/49-grafana-logs-ui-victorialogs-vs-loki.md) §4) — v0.1.0, a
partial translator, and known defects. It is the documented fallback if the plugin's Drilldown drawer
proves insufficient; it is not the fleet's log pane today.

## Consequences

- **The pane improves without touching the pipeline.** Every node's Fluent Bit output, the store's
  retention and the router's syslog path stay exactly as deployed.
- **The guest moves to the stronger node with 4 GiB, not 6.** `pve2`'s 256 GB disk takes the 64 GiB
  volume, and 4 GiB is enough for VictoriaLogs + Grafana today; `pve1` and the rest of `pve2` keep the
  remaining RAM. The guest rises to 6 GiB only when the Netdata Parent lands (ADR 47).
- **4 GiB is the initial ceiling, not the final one** — VictoriaLogs at 60 % (~2.4 GiB) plus Grafana,
  Docker and the OS fits with ~0.5 GiB of burst margin. When the Parent arrives, the 6 GiB envelope and
  VictoriaLogs' 50 % cap replaces it; the Parent's RSS decides whether 6 GiB is enough (the 7040
  supports 32 GB if not).
- **Not the literal Loki experience.** The official plugin gives Explore, histogram, live tail, levels,
  patterns, dashboards, alerting, correlations and its own Drilldown drawer — but **not** Grafana's
  Logs Drilldown app and **not** LogQL. Dashboards are new LogsQL work; Loki dashboards do not port.
- **Plugin/image coupling** — a Grafana upgrade can outrun the plugin; both are pinned, and plugin
  installation needs egress to grafana.com at container start.
- **A second authenticated LAN web app** — two new Key Vault secrets, UFW `:3000` LAN-only, no public
  route; local admin until Authentik OIDC lands.
- **Reversible** — stopping and removing the Grafana Compose project restores the previous state; the
  store is unaffected.
- **Two deferred dependencies remain visible** — the Netdata Parent move needs ADR 47, and the guest's
  Proxmox view stays with host-native children rather than the Parent.

### Alternatives Considered

- **Migrate VictoriaLogs → Loki** — buys Grafana's Loki datasource, Logs Drilldown and LogQL, but
  reverses [ADR 35](35-log-store-victorialogs.md), rewrites every collector, removes the router's
  syslog listener or adds a relay, needs an auth proxy, loses the disk-usage safety valve, and needs
  more memory on the weakest host. Rejected: the requirement is a UI, not the engine.
- **Community Loki-API proxy in front of VictoriaLogs** — the only way to keep the store and get
  Grafana's Logs Drilldown app, but a v0.1.0 partial translator with known defects. Rejected for now;
  revisit as an experiment if the plugin drawer proves insufficient.
- **Keep `vmui` only** — zero new services, but the original complaint stands.
- **Grafana on `lab` (k3s)** — more CPU and memory headroom, but breaks the operator's placement
  constraint, adds a dependency on `lab` for the pane, and contradicts the "store and pane together"
  rationale of [ADR 35](35-log-store-victorialogs.md).
- **Grafana's built-in Loki datasource pointed at VictoriaLogs** — impossible: the Loki datasource
  calls `/loki/api/v1/query*`, and VictoriaLogs serves only `/select/logsql/*` (it accepts Loki
  **push** ingest, not Loki queries).
- **Move the Netdata Parent in this ADR** — rejected as scope creep: the Parent move reverses ADR 27's
  host-native placement and needs host-native children, a dbengine migration test and its own ADR.

---

## References

- [Research 49 — Grafana as the Log Pane: VictoriaLogs with the Plugin, or a Loki Migration](../research/49-grafana-logs-ui-victorialogs-vs-loki.md) — the pane analysis
- [Research 50 — Netdata Cloud costs, stream identity and Parent migration](../research/50-netdata-cloud-costs-and-stream-identity.md) — the deferred metrics-store intent
- [Idea 15 — a second Proxmox node (`pve2`)](../ideas/15-second-proxmox-node.md) — the move and rename
- [ADR 35](35-log-store-victorialogs.md) — the store, its host, retention, TLS/auth and LAN rule
- [ADR 36](36-log-collector-fluentbit.md) — the collector contract that stays unchanged
- [ADR 34](34-lan-tls-only.md) — TLS-only LAN; host UFW does not filter container traffic
- [ADR 27](27-monitoring-strategy.md) — Tier B monitoring, host-native Parent, future dashboard component
- [ADR 40](40-internal-dns-proxy-edge.md) — `.internal` DNS and the edge reverse proxy
- [ADR 44](44-authentik-identity-provider.md) — Authentik as the future OIDC path for Grafana
- [Runbook 33](../runbooks/33-deploy-victorialogs.md) — the deployed store
- Upstream: [VictoriaLogs Grafana integration](https://docs.victoriametrics.com/victorialogs/integrations/grafana/) · [plugin catalog](https://grafana.com/grafana/plugins/victoriametrics-logs-datasource/) · [Grafana Docker](https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/) · [Grafana sizing](https://grafana.com/docs/grafana/latest/setup-grafana/installation/) · [Loki retention](https://grafana.com/docs/loki/latest/operations/storage/retention/) · [Loki authentication](https://grafana.com/docs/loki/latest/operations/authentication/)
