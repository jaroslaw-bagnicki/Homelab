# Grafana as the Log Pane — VictoriaLogs Retained, Grafana Added on the `vtstack` Guest

**Date:** 2026-10-31
**Status:** Proposed

---

## Context

VictoriaLogs is the Tier B log store — a single binary on the `vtstack` guest (LXC 214) with 30-day
retention, native TLS, HTTP basic auth, an in-LXC LAN rule and a TLS syslog listener
([ADR 35](35-log-store-victorialogs.md)). It works, but its built-in `/select/vmui` UI is too thin for
the exploration the operator actually wants: field/value discovery, patterns, dashboards and saved
views. The complaint is the **pane**, not the engine.

Grafana was considered and deferred when the store was chosen — [ADR 35](35-log-store-victorialogs.md)
records "Grafana is not a prerequisite", and [ADR 27](27-monitoring-strategy.md) leaves the dashboard
component to a future ADR. The operator now wants Grafana, running as a Docker Compose service **inside
the `vtstack` LXC**, beside the store.

Three paths exist, analysed in [research 49](../research/49-grafana-logs-ui-victorialogs-vs-loki.md):
the official VictoriaLogs Grafana plugin; a community Loki-API proxy that enables Grafana's Logs
Drilldown without Loki; and migrating the store to Loki. Fixed constraints: TLS-only on the LAN
([ADR 34](34-lan-tls-only.md)), no host-firewall coverage for container traffic, an 8 GB Celeron host,
and a collector contract that already works ([ADR 36](36-log-collector-fluentbit.md)).

## Decision

**Keep VictoriaLogs. Adopt Grafana as the log pane, running as a Docker Compose service on the
`vtstack` guest, with the official `victoriametrics-logs-datasource` plugin.**

- **Store unchanged** — no migration to Loki, no change to the Fluent Bit output contract, no change
  to the `:6514` syslog listener. Loki is rejected: it would reverse [ADR 35](35-log-store-victorialogs.md),
  replace a cardinality-safe engine with label discipline, require an authentication proxy, lose the
  router's syslog path or add a relay, and weaken the disk safety valve — all for a UI preference.
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
- **Memory: raise LXC 214 from 2 GiB to 3 GiB**, subject to `pve` headroom. Grafana's documented floor
  is 512 MB, and VictoriaLogs already reserves 60 % of a 2 GiB ceiling; 3 GiB keeps the store at
  `-memory.allowedPercent=60` (~1.8 GiB) with Grafana and the OS bounded above it. **This is a
  `pve`-level trade-off against the planned Home Assistant VM and must be measured before deployment.**
- **Datasource and dashboards provisioned from the repo** — reproducible; the embedded SQLite database
  holds only users and preferences. Local `admin` is break-glass; Authentik OIDC is the planned normal
  path ([ADR 44](44-authentik-identity-provider.md)), not a day-one dependency.
- **`vmui` stays** as the break-glass UI. Grafana is the preferred pane, not a prerequisite — the store
  remains independently queryable.

**Amendments.** [ADR 35](35-log-store-victorialogs.md): Grafana is no longer merely optional — it is
the preferred pane, while the store's independence from it stands. [ADR 27](27-monitoring-strategy.md):
Grafana is adopted for **logs only**; metrics dashboards remain a future decision.

**Not adopted now:** the community LogQL→LogsQL proxy that would enable Grafana's Loki-only Logs
Drilldown app ([research 49](../research/49-grafana-logs-ui-victorialogs-vs-loki.md) §4) — v0.1.0, a
partial translator, and known defects. It is the documented fallback if the plugin's Drilldown drawer
proves insufficient; it is not the fleet's log pane today.

## Consequences

- **The pane improves without touching the pipeline.** Every node's Fluent Bit output, the store's
  retention and the router's syslog path stay exactly as deployed.
- **One more always-on service on an 8 GB Celeron** — Grafana plus a +1 GiB LXC competes with Home
  Assistant, Netdata and the CA. The memory ceiling bounds it; it does not remove the contention.
- **Not the literal Loki experience.** The official plugin gives Explore, histogram, live tail, levels,
  patterns, dashboards, alerting, correlations and its own Drilldown drawer — but **not** Grafana's
  Logs Drilldown app and **not** LogQL. Dashboards are new LogsQL work; Loki dashboards do not port.
- **Plugin/image coupling** — a Grafana upgrade can outrun the plugin; both are pinned, and plugin
  installation needs egress to grafana.com at container start.
- **A second authenticated LAN web app** — two new Key Vault secrets, UFW `:3000` LAN-only, no public
  route; local admin until Authentik OIDC lands.
- **Reversible** — stopping and removing the Grafana Compose project restores the previous state; the
  store is unaffected.
- **Disk is still shared** — Grafana's image and database are small, but the 16 GiB rootfs and the
  store's 80 % cap must be checked before the LXC size is left unchanged.

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

---

## References

- [Research 49 — Grafana as the Log Pane: VictoriaLogs with the Plugin, or a Loki Migration](../research/49-grafana-logs-ui-victorialogs-vs-loki.md) — the analysis behind this decision
- [ADR 35](35-log-store-victorialogs.md) — the store, its host, retention, TLS/auth and LAN rule
- [ADR 36](36-log-collector-fluentbit.md) — the collector contract that stays unchanged
- [ADR 34](34-lan-tls-only.md) — TLS-only LAN; host UFW does not filter container traffic
- [ADR 27](27-monitoring-strategy.md) — Tier B monitoring, future dashboard component
- [ADR 40](40-internal-dns-proxy-edge.md) — `.internal` DNS and the edge reverse proxy
- [ADR 44](44-authentik-identity-provider.md) — Authentik as the future OIDC path for Grafana
- [Research 33](../research/33-centralized-logging-victorialogs.md) · [runbook 33](../runbooks/33-deploy-victorialogs.md)
- Upstream: [VictoriaLogs Grafana integration](https://docs.victoriametrics.com/victorialogs/integrations/grafana/) · [plugin catalog](https://grafana.com/grafana/plugins/victoriametrics-logs-datasource/) · [Grafana Docker](https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/) · [Grafana sizing](https://grafana.com/docs/grafana/latest/setup-grafana/installation/) · [Loki retention](https://grafana.com/docs/loki/latest/operations/storage/retention/) · [Loki authentication](https://grafana.com/docs/loki/latest/operations/authentication/)
