# 33 — Centralised Logging — VictoriaLogs Store and Its `pve` Host

**Source**: Gemini chats (3.6 Flash), Sep 26 2026 ·
[Gemini chat 19](https://share.gemini.google/Z8QXKHmDHOFe) (deciding the store) ·
[Gemini chat 20](https://share.gemini.google/orS2jFh9H1IU) (running containers on the `pve` node)

**Scope**: Pre-ADR research for [#123](https://github.com/jaroslaw-bagnicki/Homelab/issues/123) — settle
the **Tier B log store's** engine and **host placement**, and confirm the deployment mechanics for a
container host on the `pve` node (Proxmox VE, Wyse 5070). The collector that feeds the store is
[#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84) and stays out of scope; the store is the
parent because its ingest API, auth model and retention drive every collector's configuration.

**Status**: 📝 Analysis — the store and its host are **decided** (see the decision summary below).
No measurements were taken: RAM/disk-per-day against the 30-day budget, and the CPU cost of
compression and LogsQL scans on the `pve` node's Celeron, are **unverified** and remain validation
work for the deploy phase. Decision authoritatively recorded in
[ADR 35](../decisions/35-log-store-victorialogs.md).

> ⚠️ **Verification needed**: this thread is advisory and its numbers are unverified. The
> "up to 4–5× less RAM" and "30–40% less disk than Loki" comparisons, the VictoriaTraces
> "3.7× less RAM / 2.7× less CPU than Tempo" claim, and the Proxmox VE 9.1 **native OCI image**
> behaviour are vendor/community claims from the thread, not measurements on this hardware.
> VictoriaLogs flag names and the Proxmox 9.1 feature state must be re-checked against upstream
> docs before execution.

---

## Decision Summary

> **Decision authority:** [ADR 35](../decisions/35-log-store-victorialogs.md) — VictoriaLogs is the
> Tier B log store, running as a Docker Compose workload in an unprivileged LXC on the `pve` node.
> This research doc is the analysis that fed that decision; it is not the authority for it.

| Decision | Outcome |
|---|---|
| Store engine | **VictoriaLogs** — single static Go binary, columnar engine, LogsQL, built-in web UI at `/select/vmui` |
| Documented alternative | **Loki** (ADR 27's original candidate) — kept as the rejected option, with reasons below |
| Host | **`pve` node (Wyse 5070)** — LXC in the `21x` guest block ([ADR 31](../decisions/31-static-address-scheme.md)) |
| Host — rejected | **`lab` (M910q)** — *the placement the Gemini thread recommended*; **the NAS (Beetle M-III)** — live candidate, rejected |
| Packaging | **Docker Compose in an unprivileged LXC** with Nesting + FUSE enabled |
| Retention | **30 days** (`-retentionPeriod`) |
| Transport | **HTTPS only**, native TLS with a self-signed certificate ([ADR 34](../decisions/34-lan-tls-only.md)) |
| Auth | **HTTP basic auth from day one** — `-httpAuth.username` / `-httpAuth.password`, password from Key Vault |
| LAN scope | Listener restricted to `192.168.2.0/24` **inside the LXC**, not by host UFW ([ADR 34](../decisions/34-lan-tls-only.md)) |
| Ingest | Elasticsearch-compatible `_bulk` (Fluent Bit `es` output needs no bespoke plugin); JSON-lines also available |
| Backup | **No** — a rolling 30-day window stays outside [ADR 02](../decisions/02-backup-strategy-restic-blob.md)'s scope |

---

## Context

Tier B has no log destination. Netdata covers per-node metrics, but nothing stores logs, and the
**Edge's journald is volatile by design** ([ADR 24](../decisions/24-edge-ingress-appliance.md), eMMC
longevity) — its logs are destroyed on every reboot. A central store is the only way to keep them.

[ADR 27](../decisions/27-monitoring-strategy.md) lists the log components (Fluent Bit, Loki) as
**not adopted — no ADR yet**, and requires each Tier B component to be adopted through its own ADR.
The store comes first because it is the dependency.

Two questions were open when the threads were run: **which engine**, and — the contested one —
**which host**. A third, practical one followed: how a service is actually deployed on the `pve`
node, whose Proxmox host runs nothing but the host-native Netdata Parent
([ADR 27](../decisions/27-monitoring-strategy.md)) while its guests carry Home Assistant, Mosquitto,
Zigbee2MQTT and the NUT server.

---

## Key Findings

### 1. Store engine — Loki first, VictoriaLogs after the second question

The thread opened by recommending **Loki + Grafana** (the LGTM shape): Loki indexes **labels only**,
so it uses a fraction of Elasticsearch's memory, and LogQL is Grafana-native. The collector would be
Grafana Alloy or Vector; Tempo would take traces; VictoriaMetrics would take metrics, fed later by
Netdata's Prometheus remote-write. ELK/OpenSearch was dismissed outright — 4–8 GB of JVM heap before
it indexes anything.

The follow-up question ("what about the VictoriaMetrics + VictoriaLogs ecosystem?") flipped the
recommendation, and the comparison table the thread produced is the crux of the store decision:

| Feature | Grafana Loki | VictoriaLogs |
|---|---|---|
| Indexing model | Only defined labels | Fully columnar, indexes all fields |
| High cardinality | Vulnerable to unique labels (`trace_id`, `container_id`) | Handles it without throughput loss |
| RAM | Higher, especially when searching | Claimed 4–5× lower than Loki |
| Compression | Very good | Claimed 30–40% less disk |
| Query language | LogQL | LogsQL (closer to grep / piped SQL) |
| Maturity / ecosystem | Mature, native to Grafana | Younger, actively developed |
| Deployment | Chunk store + Grafana pairing in practice | Single binary, no external dependencies |

VictoriaLogs' stated resource envelope for a five-node fleet is **~100–300 MB RAM**, and it needs no
config file at all — everything is a start flag. It also ships its own lightweight UI at
`/select/vmui`, which makes **Grafana optional** rather than a prerequisite.

### 2. Why high cardinality is the deciding property

The thread spent a full turn on cardinality, and it is the reason the recommendation moved. In
label-indexed systems (Prometheus, Loki) every unique label combination creates a separate stream or
series whose index is held in memory:

| Cardinality | Example fields | Distinct values |
|---|---|---|
| Low | `environment`, `status_code`, `region` | a handful to a few dozen |
| Medium | `service_name`, `host_name`, `endpoint_path` | dozens to a few thousand |
| **High** | `user_id`, `session_id`, `trace_id`, `ip_address` | hundreds of thousands to unbounded |

Adding `environment` (2 values) to a metric creates 2 streams; adding `user_id` (100,000 values)
creates 200,000 — the index explodes in RAM and queries slow down or OOM. Loki's own first rule is
therefore *never* to use `user_id`, `ip` or `trace_id` as a label, which means the identifiers most
useful for debugging are exactly the ones that cannot be indexed. Columnar stores
(VictoriaLogs, ClickHouse, Elasticsearch) compress and index columns on disk instead, so unique IDs
do not destroy throughput.

For a fleet whose logs will carry container IDs, unit names and eventually trace IDs, that property
matters more than Loki's maturity.

### 3. VictoriaLogs vs ClickHouse — log engine vs data warehouse

| Feature | VictoriaLogs | ClickHouse |
|---|---|---|
| Purpose | Log management engine, native text + JSON | General-purpose OLAP / telemetry store |
| Data model | Schemaless, semi-structured | Rigid schema — columns and types defined up front |
| Setup | Single binary, ready immediately | `MergeTree` engine, partition and sort keys to design |
| Resources | Extremely low | Low to medium, more RAM for complex aggregations |
| Full-text search | Native and fast | Needs inverted/BF indexes or extra configuration |
| Logs + metrics + traces | Logs only (metrics → VictoriaMetrics) | All three in dedicated tables |

Verdict: **VictoriaLogs for the store**. ClickHouse is the better tool only if the goal were a single
OpenTelemetry backend (SigNoz/Uptrace-style) or a data warehouse joining logs with external tables —
schema design that is real operational work for a single-operator lab whose immediate goal is log
search.

### 4. The wider Victoria ecosystem

- **VictoriaMetrics** — PromQL/MetricsQL-compatible, a fraction of Prometheus' memory. Relevant later:
  Netdata's Prometheus remote-write is the sanctioned bridge, and ADR 26's `mqtt2prometheus` path
  already commits Prometheus/Grafana usage.
- **VictoriaTraces exists** — VictoriaMetrics' own tracing component, built on the VictoriaLogs
  engine: OTLP over HTTP and gRPC, Grafana integration through the Jaeger Query API, LogsQL for
  filtering spans, no object storage or cluster requirement, and a claimed ~3.7× less RAM / 2.7× less
  CPU than Tempo. Not decided here — it is the natural extension point **if** the Victoria ecosystem
  is kept for metrics and traces.
- **Grafana** stays the only sensible single pane if logs and metrics must share one dashboard; the
  store's own UI makes that optional, not required.

### 5. Host placement — the contested decision

The thread was asked to compare the two candidates directly:

| Aspect | `pve` — Wyse 5070, Proxmox | `lab` — M910q, k3s |
|---|---|---|
| CPU | Celeron J4105, 4C/4T, limited IPC | i5-7th gen, far higher clocks and IPC |
| Role today | Always-on: Home Assistant, NUT, Netdata Parent | Main workload host; k3s node per [ADR 22](../decisions/22-k3s-arc-homelab.md) |
| I/O | Low | Good — matters for compression and searches |
| Memory | 8 GB, already shared with Proxmox + HA | More headroom |
| Ops model | Firewall managed here; `vzdump` is the intended guest backup route to the NAS | Declarative limits, Helm, PVs |

**The thread recommended `lab`, not `pve`** — the argument being that the store's block compression
and LogsQL scans are CPU- and I/O-bound, the M910q handles them without latency, and a large log
burst on the Celeron could throttle and threaten Home Assistant. It also flagged that `pve`'s 8 GB is
already tight, and that a monitoring workload's memory spikes during wide queries create an **OOM
blast radius around the smart-home services**. On the follow-up it recommended keeping the Netdata
Parent where it is (light, always-on, and an independent alarm path when `lab` is down for
maintenance), with logs and traces on `lab`, stitched together in Grafana.

**The operator chose `pve` instead.** The reasoning recorded for the ADR: the store belongs with the
pane it serves, `pve` is the node that is always on regardless of maintenance on `lab`, the firewall
policy for the fleet is managed there, and `vzdump` is the natural guest backup route once the NAS
share lands. The counter-argument above stands as an **accepted risk** in ADR 35 rather than a
dismissed one — the Celeron and the 8 GB are real constraints, and ADR 22's k3s node is the
documented fallback if the store proves disruptive.

One correction to the issue body's framing: **`vzdump` → NAS backups are not running yet.** The
Beetle's share is still to be created and ADR 02's backup path is dormant, so this is a planned
route, not an existing one ([overview](../overview.md) · [report](../reports/260913-quality-assessment.md)).

The **NAS (Beetle M-III, `nas`)** was the third candidate. It has since joined the fleet
([ADR 29](../decisions/29-nas-backup-target-beetle-m3-omv.md)), so it is a live option rather than a
future one — logs are bulky and it is the storage host. It was rejected as a **storage appliance**
whose RAID1 array and backup shares are precisely what a log store's write and compaction load would
compete with; it is not the always-on service host the pane already lives on.

### 6. Running containers on the `pve` node

Second thread. Three mechanisms were compared, all of which keep the store off the Proxmox host
itself — unlike Netdata, which **had** to be host-native to read VM/CT cgroups
([ADR 27](../decisions/27-monitoring-strategy.md)) and is a log store's opposite in that respect.

| Mechanism | Shape | Notable points |
|---|---|---|
| **Dedicated VM** | Full guest OS + Docker | Kernel isolation, native `overlay2`, predictable across upgrades; costs a full OS's RAM |
| **LXC + Docker** | Unprivileged container, Docker inside | Negligible RAM overhead; needs **Nesting** and **FUSE** enabled in Options → Features; Docker shares the Proxmox kernel |
| **OCI image as LXC** | Proxmox pulls the OCI image directly | VE 9.1 **Technology Preview**; no `docker pull` or in-place update, layers squash-merged at creation, **no `docker-compose`**, no shell in the Proxmox console (`pct enter <ID>`) |

The "native Docker in Proxmox" article the thread summarised is worth de-mystifying: Proxmox does
**not** run a Docker daemon. It uses `skopeo` to pull the image and squash it into a standard LXC
rootfs, so a Docker image becomes an LXC application container. That removes the AppArmor friction of
Docker-in-LXC and needs no VM, but the Tech-Preview limits above make it a poor fit for a store that
must be updated and whose whole configuration is a set of start flags.

There is no official `pveam` Docker template; the community helper script
(`ct/docker.sh`) is the fast path, and building a container once and converting it to a template is
the reproducible one.

### 7. VictoriaLogs deployment facts confirmed

- Images: `victoriametrics/victoria-logs` (Docker Hub) and `quay.io/victoriametrics/victoria-logs`.
- Default HTTP port: **9428** — web UI, ingest endpoints (Syslog, JSON, Elasticsearch-compatible
  `_bulk`, Loki/Promtail protocol) and the Grafana datasource.
- Storage: `-storageDataPath=/victoria-logs-data` on a volume.
- Retention: `-retentionPeriod` (e.g. `30d`; months/years suffixes supported).
- Configuration is **flags only** — no YAML config file, which suits a Compose `command:` list.
- Auth: `-httpAuth.username` / `-httpAuth.password`. TLS: `-tls`, `-tlsCertFile`, `-tlsKeyFile`.

---

## Alternatives Considered

| Option | Verdict | Reason |
|---|---|---|
| **VictoriaLogs** | ✅ chosen | Columnar, cardinality-safe, single binary, own UI, low footprint |
| Loki + Promtail/Alloy | ❌ rejected | Label-only indexing forces discipline on exactly the searchable fields; chunk store + Grafana pairing for the same five-node job |
| ELK / OpenSearch | ❌ rejected | 4–8 GB of JVM heap before indexing anything |
| ClickHouse | ❌ rejected | Capable, but schema/partition/order-key design for a log-search goal; better only as a full OTel backend |
| Host: `lab` (M910q / k3s) | ❌ rejected | Gemini's recommendation — best CPU/IO, but reintroduces a `lab` dependency for fleet logs and ADR 22 makes it a k3s node, so the workload would need migrating later |
| Host: `nas` (Beetle M-III) | ❌ rejected | Storage appliance; a log store's writes would compete with the backup array, and it is not the always-on pane host |
| Host: `pve`, native binary + systemd | ❌ rejected | Smallest footprint, but diverges from the fleet's workload and image-update pattern |
| Host: `pve`, Proxmox 9.1 OCI-as-LXC | ❌ rejected | Tech Preview: no `compose`, no in-place update, squash-on-create |
| Plaintext HTTP ingest | ❌ not available | Prohibited by [ADR 34](../decisions/34-lan-tls-only.md); the store is a write-accepting service |
| Grafana as a prerequisite | ❌ rejected | Built-in `/select/vmui` UI over HTTPS is sufficient to query; dashboards remain a separate future ADR (ADR 27) |

---

## Open Questions

- **No measurements.** RAM and disk growth per day against the 30-day budget, and query latency on the
  Celeron, are unmeasured. The store's disk comes out of the `pve` node's single 128 GB M.2 SATA — the
  ~39 GiB `local` root LV, where the Netdata Parent's ≈7 GiB per-tier DB already lives, or the
  ~68 GiB `local-lvm` thin pool the guests use. Which storage the LXC's volume lands on is not decided
  here.
- **Where the LAN-only rule is enforced.** [ADR 34](../decisions/34-lan-tls-only.md) established that
  host UFW does not filter container traffic, so the rule must live inside the LXC or at the Proxmox
  firewall — and be verified from off-LAN, not asserted.
- **Collectors** ([#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84)) — Fluent Bit's `es`
  output is the assumed path; which nodes run a collector, and whether the Edge's RAM-only footprint
  tolerates one, is undecided. The store is inert until at least one ships.
- **Certificate trust** — clients skip verification initially (ADR 27/34's residual). Pinning depends
  on the private CA tracked as [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126).
- **Monitoring the store** — ADR 34's `httpcheck`/`x509check` control should be pointed at the store's
  HTTPS listener and certificate; not yet wired.
- **Whether Grafana, VictoriaMetrics or VictoriaTraces ever land** — all natural extensions, all
  separate future ADRs. Metrics/traces host placement was discussed in the thread but is **not**
  settled here.

---

## References

- [ADR 02](../decisions/02-backup-strategy-restic-blob.md) — Backup strategy (logs stay out of scope)
- [ADR 22](../decisions/22-k3s-arc-homelab.md) — k3s migration (`lab`; the store's documented fallback host)
- [ADR 24](../decisions/24-edge-ingress-appliance.md) — Edge appliance (volatile journald; eMMC)
- [ADR 26](../decisions/26-zigbee-energy-monitoring.md) — Zigbee monitoring (the committed Prometheus/Grafana path)
- [ADR 27](../decisions/27-monitoring-strategy.md) — Tier B monitoring strategy; components via their own ADRs
- [ADR 29](../decisions/29-nas-backup-target-beetle-m3-omv.md) — NAS backup target (the rejected `nas` host)
- [ADR 30](../decisions/30-ups-nut-graceful-shutdown.md) — NUT in LXC 213 (the neighbouring guest)
- [ADR 31](../decisions/31-static-address-scheme.md) — Static address scheme (`21x` guest block, ID = last octet)
- [ADR 34](../decisions/34-lan-tls-only.md) — LAN services are TLS-only; host UFW does not filter LXC traffic
- [ADR 35](../decisions/35-log-store-victorialogs.md) — **the decision this research fed**
- [Issue #123](https://github.com/jaroslaw-bagnicki/Homelab/issues/123) · [#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84) (collector) · [#75](https://github.com/jaroslaw-bagnicki/Homelab/issues/75) (umbrella) · [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) (private CA)
- [Gemini chat 19](https://share.gemini.google/Z8QXKHmDHOFe) · [Gemini chat 20](https://share.gemini.google/orS2jFh9H1IU)
