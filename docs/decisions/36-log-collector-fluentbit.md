# Log Collector — Fluent Bit, Fleet-Wide, into VictoriaLogs

**Date:** 2026-09-27
**Status:** Accepted

---

## Context

The log store is **deployed and inert**. VictoriaLogs answers on `https://192.168.2.214:9428` with TLS, HTTP
basic auth, 30-day retention and a LAN-only rule inside the LXC
([ADR 35](35-log-store-victorialogs.md) · [runbook 33](../runbooks/33-deploy-victorialogs.md)), and nothing
ships logs to it. The reason the store exists is unchanged: the **Edge's journald is volatile by design**
([ADR 24](24-edge-ingress-appliance.md), eMMC longevity), so its logs die with every reboot.

[ADR 27](27-monitoring-strategy.md) requires every Tier B component to be adopted through **its own ADR**; this
is that ADR for the **collector**, the counterpart to ADR 35's store, tracked as
[#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84).

Three constraints are inherited rather than decided here:

- **HTTPS only, self-signed** — [ADR 34](34-lan-tls-only.md) prohibits plaintext HTTP on the LAN, so the
  collector must speak TLS and skip verification (the residual ADR 27, ADR 34 and ADR 35 already accept).
- **Basic auth from day one** — ADR 35 gave the store `-httpAuth.*`, so a collector that cannot send
  credentials cannot write.
- **No persistent writes on `edge`** — [ADR 24](24-edge-ingress-appliance.md). This makes "how does the
  collector buffer when the store is unreachable?" a decision rather than a default.

The operator also asked whether adopting the **whole Victoria stack** (logs + metrics + traces) should change
the collector to Victoria's own agent. Research answered it with an upstream fact: **`vlagent` has no journald
source** — its only log *input* sources are Kubernetes pod logs and files, and its durability mechanism is an
**on-disk buffer**, which is the one thing this appliance cannot have
([research 34 §2–§3](../research/34-log-collector-options.md)). The collector options are analysed in
[research 34](../research/34-log-collector-options.md); the store's ingest contract is in research 33 §7.

## Decision

**Adopt Fluent Bit as the Tier B log collector, fleet-wide, as a shared Ansible role feeding VictoriaLogs.**

- **Collector: Fluent Bit over the alternatives** — the only candidate that is small, store-agnostic and has
  a **stable journald input**: `systemd` reads the journal natively (no `journalctl` shell-out, no root
  capability dance), exposes `_SYSTEMD_UNIT` / `MESSAGE` / `PRIORITY` / `__REALTIME_TIMESTAMP` verbatim, and
  filters by unit through `systemd_filter`. It is roughly **a quarter of the OTel Collector's memory** in the
  vendor's own benchmark ([research 34 §3](../research/34-log-collector-options.md#3-the-vendors-own-collector-benchmark--what-it-does-and-does-not-say)).
- **Inputs: one collector, four source shapes** — **journald** on every systemd node (the `systemd` input;
  fields arrive structured); **Docker's json-file** container logs on `lab` (`tail` + the built-in `docker`
  parser, because each line is a JSON wrapper); **containerd CRI** logs when
  [ADR 22](22-k3s-arc-homelab.md)'s k3s lands (`tail` + the built-in `cri` parser, with `kube-custom` to
  derive pod/namespace/container from the filename); and **native file logs** where a system keeps its own
  (Proxmox's `/var/log/pve/tasks/`, OMV's `/var/log/openmediavault`). The per-system inventory is
  [research 34 §9](../research/34-log-collector-options.md).
- **One transport per line — never journald *and* rsyslog files** — a host that keeps rsyslog-style files
  beside the journal (`pve`, `nas`) holds the same line twice and Fluent Bit ships both. Each node declares
  its single source per line, in `host_vars`; there is no deduplication to enable at ingest.
- **Deployed as a systemd service per node, not a container** — the fleet's `netdata` pattern
  ([ADR 27](27-monitoring-strategy.md)). `edge` runs no Docker by design
  ([runbook 24](../runbooks/24-edge-appliance.md)), and on `lab` a host-native service can read both the host
  journal and Docker's log files without bind mounts.
- **One shared role, per-node behaviour in `host_vars`** — the role carries the output contract, buffering
  policy and cursor placement; each node's `host_vars` carries its **source list** and stream-field mapping.
  Same shape as `netdata` ([ADR 10](10-ansible-host-config.md)).
- **Inputs: journald first, container logs where they exist** — the `systemd` input on every node; a `tail` on
  Docker's json-file logs on `lab` (and containerd's files once [ADR 22](22-k3s-arc-homelab.md)'s k3s lands).
- **Output: the store's HTTP JSON-lines API** — `https://192.168.2.214:9428/insert/jsonline` with
  `_stream_fields`, `_msg_field`, `_time_field` as query args, `tls On`, `tls.verify Off`, `http_user` +
  `http_passwd` from Azure Key Vault, and gzip. **This supersedes the `es` output assumed in
  [#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84)**: the Elasticsearch-compatible
  `/insert/elasticsearch/_bulk` endpoint works, but the JSON-lines route is the one VictoriaMetrics
  **documents** for Fluent Bit and it takes the same parameters
  ([research 34 §5](../research/34-log-collector-options.md)).
- **Stream fields: host and unit** — `_HOSTNAME` + `_SYSTEMD_UNIT` for journald, mirroring the store's own
  journald defaults, so a stream is "this unit on this node"; hostname + container name for container logs.
- **An explicit inclusion list, never all of journald** — a named unit set plus a priority floor, per node.
  Shipping an entire journal drowns the store in noise, costs ingest for nothing, and queries worse than
  `journalctl` on the node itself.
- **Buffering rule: memory only everywhere** — `storage.type memory` with a bounded
  `mem_buf_limit` / `storage.total_limit_size`; on **`edge`** it is additionally pause-on-overlimit, so an
  unreachable store **drops** logs rather than spooling them to the eMMC. The cursor database is on disk on
  `pve`/`lab`/`nas` and on **tmpfs** (`/run`) on `edge`, where the journal is volatile anyway — so a reboot
  loses nothing that journald did not already lose.
- **Rollout order `pve` → `edge` → `lab`**, then `nas` and finally `vtstack` (so the store's own container
  logs are searchable in the store). Each node is validated before the next. **`cloudlab` is never a target**
  — outside the LAN and already covered by Tier A ([ADR 27](27-monitoring-strategy.md)).- **The OPNsense router is deliberately out of scope** — it is a FreeBSD appliance with **no journald** and no
  Docker, which [ADR 27](27-monitoring-strategy.md) already treats as a **per-OS exception**. Fluent Bit does
  build on FreeBSD (`sysutils/fluent-bit`), but OPNsense has **no plugin for it**, making it an out-of-band
  package outside the configuration backup; the router's own path — syslog-ng into the store's syslog
  listener, the Telegraf plugin, or the port — is decided with the router, in its own runbook/ADR
  ([research 34 §8](../research/34-log-collector-options.md)).- **The agent stays store-agnostic, and OTLP stays open** — Fluent Bit's output is configuration, not a fork:
  the fleet keeps a working collector even if the store is ever replaced, and its `opentelemetry` output
  already speaks **OTLP logs, metrics and traces**, so it can feed VictoriaLogs' OTLP endpoint or
  VictoriaTraces later without replacing the agent ([research 34 §5](../research/34-log-collector-options.md)).
- **Metrics and traces are separate decisions** — VictoriaMetrics and VictoriaTraces remain **future ADRs** on
  the same `vtstack` guest ([ADR 35](35-log-store-victorialogs.md)). Neither needs a fleet collector: metrics
  come from Netdata ([ADR 27](27-monitoring-strategy.md)), and traces go **directly** from instrumented
  workloads to VictoriaTraces over OTLP. Adopting the whole Victoria stack therefore costs this decision
  nothing ([research 34 §7](../research/34-log-collector-options.md)).

## Consequences

- **The store stops being inert, and the Edge's logs survive reboots** — the two reasons the store exists are
  realised by the first node deployed, not by the whole rollout.
- **One agent, one config model, five nodes** — Fluent Bit's footprint is small enough for the 2 GB Edge and
  its configuration is a per-node `host_vars` file, so adding a node is data, not code.
- **The input side is more work than "install a shipper".** Four source shapes, two of them needing a parser,
  plus one prerequisite that is not the collector's to fix: Docker's `json-file` driver rotates **nothing** by
  default on `lab`, so a runaway container log can fill the host before the collector is involved. Filed as
  validation work in [research 34 §9](../research/34-log-collector-options.md).
- **A silent failure mode is now possible in the pipeline** — a collector that stops or drops looks like a
  quiet fleet rather than an error. Monitoring the pipeline is not covered here: the store's own health stays
  [#132](https://github.com/jaroslaw-bagnicki/Homelab/issues/132), and the collector's metrics are a follow-up.
- **`edge` trades completeness for the eMMC** — with the store unreachable its logs are dropped by design.
  Accepted: the alternative is writing log buffers to the same flash ADR 24 protects.
- **Logs are lossy at the collector, deliberately.** Memory-only buffering means a store outage longer than
  the buffer drops logs, and a reboot loses whatever was buffered. This is the same trade the store made when
  it declined HA (ADR 35); it is a choice, not an oversight.
- **Filtering is coarse-grained.** An inclusion list plus a priority floor means genuine detail outside the
  named units is not stored — the cost of keeping a five-node journal searchable and the store small. The list
  is a `host_vars` edit, so it can grow without a new decision.
- **One more service to update on every node.** Fluent Bit joins Netdata as fleet-wide software with an
  upgrade path to manage ([ADR 27](27-monitoring-strategy.md)'s `netdata_upgrade` precedent).
- **Cardinality is now something to watch.** `_SYSTEMD_UNIT` is safe for static units but explodes on
  templated ones (`systemd-coredump@.service`, `.socket` units with `Accept=yes`) — the store's documented
  high-cardinality warning. The per-node inclusion list is the mitigation, and the store's metrics will show it
  if it is not enough.
- **The collector does not lock in the store.** Because the choice is store-agnostic and OTLP-capable, a future
  change of backend, or the addition of VictoriaTraces, is an output section rather than a re-platforming.

### Alternatives Considered

- **`vlagent` — the Victoria stack's own agent** — the operator's preferred option if it cost nothing.
  Rejected on a gap in the product, not a preference: it has **no journald source** (pod logs and files only),
  so shipping this fleet's journals would need `systemd-journal-upload` in front of it — two daemons for one
  job — and its durability model is an **on-disk buffer**, which [ADR 24](24-edge-ingress-appliance.md) forbids
  on `edge`. Upstream's own guidance is decisive for the shape this fleet has: *"Send logs directly to
  VictoriaLogs when you have a single instance and a stable network connection."* Revisit if the fleet ever
  grows a Kubernetes log workload or a second store needing replication.
- **OpenTelemetry Collector** — the genuine tradeoff, and the one the operator asked to have compared. It is
  the only candidate that is a single agent for logs, metrics and traces, but the parts don't line up with this
  fleet: its `journald` receiver is **alpha**, it **shells out to the `journalctl` binary** (needing root, or
  `systemd-journal` group membership — and in a container, a host-rootfs chroot with
  `CAP_DAC_READ_SEARCH` + `CAP_SYS_PTRACE`), it needs a `file_storage` extension or a restart silently skips
  everything logged while it was down, and it is the **heaviest** collector in the vendor's own benchmark.
  Its multi-signal advantage has no buyer today: traces go direct to VictoriaTraces and metrics come from
  Netdata. **Revisit if the fleet ever collects traces at the node or adopts a full OTLP pipeline.**
- **Vector** — capable, well-documented, journald and Docker sources, and the near-miss. Rejected as heavier
  than Fluent Bit in both memory and configuration surface for a five-node fleet whose entire job is
  "journald → one HTTP endpoint".
- **Grafana Alloy (with Promtail / Grafana Agent)** — rejected because it is Loki-shaped: it pulls the fleet
  toward the backend [ADR 35](35-log-store-victorialogs.md) rejected, and the vendor's own benchmark lists
  Promtail and Grafana Agent as Alloy's predecessors — two generations of churn inside one option.
- **Filebeat / Fluentd** — rejected: the lowest throughput of the benchmarked set (losing logs before 10k
  logs/s), and Filebeat couples the collector to the Elasticsearch ecosystem.
- **`systemd-journal-upload` → `/insert/journald`** — the zero-extra-software path, and the closest call on
  cost. Rejected as *the* collector because it cannot authenticate to a basic-auth store (no documented
  credential option beyond client certificates; header support arrives only in systemd v258, above the fleet's
  255/257), ships journald only — so it cannot cover `lab`'s Docker logs — and offers no unit or priority
  filtering. **Kept as the documented fallback for a future journald-only appliance.**
- **No collector at all** — rejected: the store stays inert and the Edge keeps losing its logs every reboot.
- **A collector on `lab` only, forwarding on behalf of the fleet** — rejected: the Edge's logs would still die
  locally, and every node's logs would gain a hard dependency on `lab`
  ([ADR 22](22-k3s-arc-homelab.md) makes it a k3s node).
- **Shipping all of journald** — rejected: unbounded ingest into a 16 GiB volume, worse signal-to-noise, and a
  query experience worse than the `journalctl` already on the node.

---

## References

- [ADR 10](10-ansible-host-config.md) — Ansible host config (the shared-role pattern this follows)
- [ADR 22](22-k3s-arc-homelab.md) — k3s migration (containerd logs later; `lab` as a node)
- [ADR 24](24-edge-ingress-appliance.md) — Edge appliance (volatile journald, eMMC, no Docker)
- [ADR 26](26-zigbee-energy-monitoring.md) — Zigbee power path (to reconcile if VictoriaMetrics is adopted)
- [ADR 27](27-monitoring-strategy.md) — Tier B strategy; components adopted via their own ADRs
- [ADR 34](34-lan-tls-only.md) — LAN services are TLS-only
- [ADR 35](35-log-store-victorialogs.md) — the log store, its endpoint, auth and retention
- [Research 34](../research/34-log-collector-options.md) — the analysis behind this decision (§8 the router); [research 33](../research/33-centralized-logging-victorialogs.md) — the store
- [Research 31](../research/31-futro-s930-hardware-diagnostic.md) — Futro S930 (the router; the per-OS exception)
- [Runbook 24](../runbooks/24-edge-appliance.md) — Edge services are systemd-native; [runbook 33](../runbooks/33-deploy-victorialogs.md) — the deployed store
- [Issue #84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84) · [#75](https://github.com/jaroslaw-bagnicki/Homelab/issues/75) (umbrella) · [#123](https://github.com/jaroslaw-bagnicki/Homelab/issues/123) (store) · [#132](https://github.com/jaroslaw-bagnicki/Homelab/issues/132) (store monitoring)
