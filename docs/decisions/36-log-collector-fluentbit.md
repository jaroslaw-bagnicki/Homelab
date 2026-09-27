# Log Collector — Fluent Bit, Fleet-Wide, into VictoriaLogs

**Date:** 2026-09-27
**Status:** Accepted

> **This ADR records the decision and why.** Flags, parsers, per-node paths, tuning and the full
> comparison live in [research 34](../research/34-log-collector-options.md); how to deploy it will live in
> the role and its runbook. Nothing is repeated here.

---

## In short

| | |
|---|---|
| **Adopted** | **Fluent Bit** — one systemd service per node, shipping logs to VictoriaLogs |
| **Why** | It is the only small, store-agnostic collector with a **stable journald input** — and every node in this fleet logs through journald |
| **Not adopted** | `vlagent` (no journald source, buffers to disk), OTel Collector (alpha journald, heaviest), Vector, Alloy/Promtail, Filebeat, Fluentd, Telegraf (no journald input), `systemd-journal-upload` alone |
| **Next** | Build the `fluentbit` role → deploy to `pve` → confirm entries in the store's UI → `edge` → `lab` |

---

## Context

The store is **deployed and inert**: VictoriaLogs answers on `https://192.168.2.214:9428` with TLS, basic
auth and 30-day retention ([ADR 35](35-log-store-victorialogs.md) · [runbook 33](../runbooks/33-deploy-victorialogs.md)),
and nothing ships logs to it. The reason the store exists has not changed — the **Edge's journald is volatile
by design** ([ADR 24](24-edge-ingress-appliance.md)), so its logs die with every reboot.
[ADR 27](27-monitoring-strategy.md) requires each Tier B component to have its own ADR; this is the
**collector**, the counterpart to ADR 35's store ([#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84)).

Three constraints are inherited, not decided here:

- **HTTPS only, self-signed** — [ADR 34](34-lan-tls-only.md). The collector must speak TLS and skip
  verification, a residual ADR 27/34/35 already accept.
- **The store requires basic auth** ([ADR 35](35-log-store-victorialogs.md)) — a collector that cannot send
  credentials cannot write.
- **No persistent writes on `edge`** ([ADR 24](24-edge-ingress-appliance.md)) — so buffering is a decision,
  not a default.

The operator also asked whether adopting the **whole Victoria stack** (logs + metrics + traces) should mean
Victoria's own agent. It should not: **`vlagent` has no journald source** and buffers to disk
([research 34 §2](../research/34-log-collector-options.md)), and neither metrics nor traces need a fleet agent
at all (§7).

## Decision

**Adopt Fluent Bit as the Tier B log collector, fleet-wide, as a shared Ansible role feeding VictoriaLogs.**

- **Fluent Bit, not the alternatives** — small, store-agnostic, and the only candidate with a stable journald
  input. The `systemd` input reads the journal natively: no `journalctl` shell-out, no root capabilities.
- **A systemd service per node, not a container** — the `netdata` pattern ([ADR 27](27-monitoring-strategy.md)).
  `edge` runs no Docker by design ([runbook 24](../runbooks/24-edge-appliance.md)), and on `lab` a host-native
  service reads both the host journal and Docker's log files without bind mounts.
- **One shared role (`fluentbit`), per-node behaviour in `host_vars`** — the role owns the output contract,
  buffering and cursor placement; each node declares its own source list and stream fields. Same shape as
  `netdata` ([ADR 10](10-ansible-host-config.md)).
- **Four source shapes** — journald everywhere; Docker's json-file logs on `lab` with the built-in `docker`
  parser; containerd CRI logs when [ADR 22](22-k3s-arc-homelab.md)'s k3s lands, with `cri` + `kube-custom`;
  and native file logs where a system keeps its own (Proxmox task logs, OMV's log directory)
  ([research 34 §9](../research/34-log-collector-options.md)).
- **One transport per line** — `pve` and `nas` keep rsyslog files *and* a journal, so collecting both would
  store every line twice. Each node picks one, in `host_vars`; there is no dedup to enable at ingest.
- **Output: the store's JSON-lines API over TLS with basic auth** — `https://192.168.2.214:9428/insert/jsonline`
  with `_stream_fields` / `_msg_field` / `_time_field`; `_HOSTNAME` + `_SYSTEMD_UNIT` as streams for journald
  (hostname + container for Docker); gzip; password from Key Vault. This is the route VictoriaMetrics
  **documents** for Fluent Bit and it **supersedes the `es` output assumed in
  [#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84)** ([research 34 §5](../research/34-log-collector-options.md)).
- **Buffering: memory only, everywhere** — bounded, and on `edge` pause-on-overlimit, so an unreachable store
  **drops** logs instead of spooling them to the eMMC. The cursor file sits on disk on `pve`/`lab`/`nas` and on
  **tmpfs** on `edge`, where a reboot loses nothing journald had not already lost ([research 34 §6](../research/34-log-collector-options.md)).
- **An explicit inclusion list per node** — named units plus a priority floor, never a whole journal.
- **Rollout `pve` → `edge` → `lab`**, then `nas` and `vtstack`, validating each before the next.
  **`cloudlab` is never a target** — off-LAN, and Tier A already covers it ([ADR 27](27-monitoring-strategy.md)).
- **The OPNsense router is out of scope** — a FreeBSD appliance with no journald and no Docker, which
  [ADR 27](27-monitoring-strategy.md) already treats as a per-OS exception. Fluent Bit does build on FreeBSD,
  but OPNsense has **no plugin for it**, so it would sit outside the configuration backup. The router's own
  path is decided when it joins ([research 34 §8](../research/34-log-collector-options.md)).
- **The agent stays store-agnostic** — its output is configuration, so a future store change is an output
  section, not a re-platforming. Its `opentelemetry` output already speaks OTLP logs, metrics and traces.
- **Metrics and traces remain separate future ADRs** on the same `vtstack` guest ([ADR 35](35-log-store-victorialogs.md)).
  Netdata supplies metrics ([ADR 27](27-monitoring-strategy.md)) and traces go straight from instrumented
  workloads to VictoriaTraces over OTLP, so adopting the whole stack costs this decision nothing.

## Consequences

**Gains**

- The store stops being inert, and the **Edge's logs survive reboots** — the reasons it exists, delivered by
  the first node deployed.
- One agent and one config model across the fleet: adding a node is a `host_vars` file, not code.
- The collector does not lock in the store.

**Costs accepted**

- **Logs are lossy at the collector, deliberately.** Memory-only buffering means a store outage longer than
  the buffer — or a reboot — drops logs. The same trade ADR 35 made when it declined HA.
- **`edge` trades completeness for the eMMC**: with the store down its logs are dropped by design.
- **Filtering is coarse.** An inclusion list plus a priority floor means detail outside the named units is not
  stored. The list is a `host_vars` edit, so it can grow without a new decision.
- **The input side is more than "install a shipper"** — four source shapes, two of them needing a parser, plus
  a prerequisite that is the host's to fix: Docker rotates **nothing** by default on `lab`
  ([research 34 §9](../research/34-log-collector-options.md)).
- **One more fleet-wide service to update**, alongside Netdata ([ADR 27](27-monitoring-strategy.md)).

**To watch**

- **A silent failure mode.** A collector that stops or drops looks like a quiet fleet, not an error. The
  store's health stays [#132](https://github.com/jaroslaw-bagnicki/Homelab/issues/132); the collector's own
  metrics are a follow-up.
- **Stream cardinality.** `_SYSTEMD_UNIT` is safe for static units but explodes on templated ones — the
  store's documented high-cardinality warning.
- **k3s collection shape.** Host-level `tail` (no metadata) versus a DaemonSet with the `kubernetes` filter is
  decided with [ADR 22](22-k3s-arc-homelab.md)'s migration.

### Alternatives Considered

- **`vlagent` — the Victoria stack's own agent** — the operator's first preference, rejected on a product gap:
  **no journald source** (pod logs and files only), and durability by **on-disk buffer**, which ADR 24 forbids
  on `edge`. Upstream's own guidance fits this fleet: *"send logs directly to VictoriaLogs when you have a
  single instance and a stable network connection."*
- **OpenTelemetry Collector** — the closest call, and the one the operator asked to compare. Rejected: its
  `journald` receiver is **alpha**, it **shells out to `journalctl`** (root, or `systemd-journal` group; in a
  container, a chroot plus capabilities), a restart without a `file_storage` extension silently skips the
  downtime window, and it is the heaviest collector benchmarked. Revisit if the fleet ever collects traces at
  the node.
- **Vector** — the near-miss, and a real, actively maintained project (Datadog-maintained). Rejected as heavier
  than Fluent Bit in memory and configuration for a job that is "journald → one HTTP endpoint"; its journald
  source also **pipes `journalctl`** rather than reading the journal.
- **Grafana Alloy (with Promtail / Grafana Agent)** — Loki-shaped, pulling the fleet toward the backend ADR 35
  rejected; the vendor's own benchmark lists both predecessors, i.e. two generations of churn in one option.
- **Filebeat / Fluentd** — the lowest throughput benchmarked, and Filebeat couples the collector to Elastic's
  ecosystem.
- **Telegraf** — popular, and VictoriaMetrics documents it for VictoriaLogs, but it has **no journald input**
  (`tail`, `syslog` and `docker_log` only), so it is disqualified on every journald host for the same reason as
  `vlagent`. It stays the router's candidate ([research 34 §8](../research/34-log-collector-options.md)).
- **`systemd-journal-upload` alone** — the zero-extra-software path. Rejected: it cannot authenticate to a
  basic-auth store (no credential option before systemd v258), ships journald only, and offers no unit or
  priority filtering. **Kept as the fallback for a future journald-only appliance.**
- **No collector** — the store stays inert and the Edge keeps losing its logs.
- **A collector on `lab` forwarding for the fleet** — the Edge's logs would still die locally, and every
  node's logs would depend on `lab`.
- **Shipping all of journald** — unbounded ingest into a 16 GiB volume, worse signal-to-noise, and queries
  worse than the `journalctl` already on the node.

---

## References

- [ADR 10](10-ansible-host-config.md) — the shared-role pattern this follows
- [ADR 22](22-k3s-arc-homelab.md) — k3s (containerd logs later; `lab` as a node)
- [ADR 24](24-edge-ingress-appliance.md) — Edge appliance (volatile journald, eMMC, no Docker)
- [ADR 27](27-monitoring-strategy.md) — Tier B strategy; components adopted via their own ADRs
- [ADR 34](34-lan-tls-only.md) — LAN services are TLS-only
- [ADR 35](35-log-store-victorialogs.md) — the log store, its endpoint, auth and retention
- [Research 34](../research/34-log-collector-options.md) — the analysis (§8 the router, §9 source shapes); [research 33](../research/33-centralized-logging-victorialogs.md) — the store
- [Runbook 33](../runbooks/33-deploy-victorialogs.md) — the deployed store
- [Issue #84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84) · [#75](https://github.com/jaroslaw-bagnicki/Homelab/issues/75) umbrella · [#132](https://github.com/jaroslaw-bagnicki/Homelab/issues/132) store monitoring
