# 33 — Centralised Logging — VictoriaLogs Store and Its `pve` Host

**Source**: Gemini chats (3.6 Flash), Sep 26 2026 ·
[Gemini chat 19](https://share.gemini.google/Z8QXKHmDHOFe) (deciding the store) ·
[Gemini chat 20](https://share.gemini.google/orS2jFh9H1IU) (running containers on the `pve` node)

**Official docs**: [docs.victoriametrics.com/victorialogs](https://docs.victoriametrics.com/victorialogs/) —
read 2026-09-27; the store's mechanics in [§7](#7-official-documentation--verified-facts-2026-09-27) are
**verified upstream**, not taken from the thread

**Further reading**: [How do open source solutions for logs work — Elasticsearch, Loki and VictoriaLogs](https://itnext.io/how-do-open-source-solutions-for-logs-work-elasticsearch-loki-and-victorialogs-9f7097ecbc2f)
(ITNEXT, Aliaksandr Valialkin) — the engine-level mechanism summarised in
[§8](#8-how-the-three-engines-store-and-query-logs--the-mechanism-behind-the-store-choice)

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

> ⚠️ **Verification status**: the store's **mechanics are now verified** against the official
> VictoriaLogs documentation (§7) — flags, ingest endpoints, retention and disk-space caps, the
> security posture and the backup mechanism. What remains unverified is (a) every **performance
> comparison** (the thread's "4–5× less RAM", "30–40% less disk than Loki", and the VictoriaTraces
> "3.7× less RAM / 2.7× less CPU than Tempo" figures are vendor benchmarks, not measurements on this
> hardware), and (b) the **Proxmox VE 9.1 native-OCI** behaviour, which is a Proxmox Tech Preview and
> not covered by VictoriaMetrics docs at all. The docs' own headline "up to 30× less RAM / 15× less disk
> than Elasticsearch" traces to the same author's analysis as §8, so that number is vendor-authored too —
> treat every performance figure here as a claim to validate on this hardware, not as a fact.

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
| Resource caps | **Memory** (`-memory.allowed*` inside an LXC ceiling) and **disk** (`-retention.maxDiskUsagePercent` + `-storage.minFreeDiskSpaceBytes`) — uncapped, a full disk puts the store into read-only mode |

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
| Indexing model | Only defined labels | No inverted index — bloom filters over tokens used to **skip data blocks**, plus columnar per-field storage ([§8](#8-how-the-three-engines-store-and-query-logs--the-mechanism-behind-the-store-choice)) |
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
useful for debugging are exactly the ones that cannot be indexed. Engines that don't derive their index
from the values avoid the blow-up — VictoriaLogs keeps no inverted index over field values at all,
ClickHouse is columnar, and Elasticsearch tolerates unique values by paying in storage and RAM
([§8](#8-how-the-three-engines-store-and-query-logs--the-mechanism-behind-the-store-choice)).

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

### 7. Official documentation — verified facts (2026-09-27)

Taken from the official VictoriaLogs docs, read 2026-09-27 —
[overview](https://docs.victoriametrics.com/victorialogs/) ·
[quickstart](https://docs.victoriametrics.com/victorialogs/quickstart/) ·
[data ingestion](https://docs.victoriametrics.com/victorialogs/data-ingestion/) ·
[querying](https://docs.victoriametrics.com/victorialogs/querying/) ·
[security and load balancing](https://docs.victoriametrics.com/victorialogs/security-and-lb/) ·
[env-flag rules](https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/#environment-variables).
These supersede the thread's vendor-summary where the two differ.

**7.1 Retention, and the disk-space safety valve.** Default retention is **7 d**; `-retentionPeriod`
accepts **1d … 100y**. Data lives in **per-day partition directories** and partitions outside the
window are dropped automatically. Entries timestamped outside retention are dropped at ingest and
counted by `vl_rows_dropped_total` (the docs suggest alerting on `rate(vl_rows_dropped_total[5m]) > 0`);
timestamps beyond `now+2d` are rejected unless `-futureRetention` is raised. Retention can also be
capped **by disk space**:

| Flag | Behaviour |
|---|---|
| `-retention.maxDiskSpaceUsageBytes=100GiB` | Drops the oldest per-day partitions once `-storageDataPath` exceeds a fixed size |
| `-retention.maxDiskUsagePercent=80` | Drops partitions once the **filesystem** holding `-storageDataPath` passes a usage percentage |

The two are **mutually exclusive** — VictoriaLogs refuses to start if both are set. `-retentionPeriod`
applies **independently** of them, so both bounds take effect (the docs pair a huge byte cap with
`-retentionPeriod=100y` to get disk-only behaviour). It always keeps the **last two days** regardless
of the cap, and usage is only checked **periodically** — so it can overshoot between checks. If the
disk does fill, VictoriaLogs **switches to read-only mode** and can then no longer drop partitions,
which is why the docs warn against a small disk with fast ingest and why
`-storage.minFreeDiskSpaceBytes` exists as the free-space floor.

**7.2 Capacity planning.** The docs recommend leaving **50% of RAM**, **50% of CPU** and **at least
20% of free storage space** at `-storageDataPath` — too little free space prevents part merges and
slows both ingest and query. `-memory.allowedBytes` / `-memory.allowedPercent` bound the process's
cache memory. Compression is described as **10× or more**.

**7.3 Ingest endpoints (verified).** All on port **9428**:

| Endpoint | Purpose |
|---|---|
| `/insert/elasticsearch/_bulk` | Elasticsearch / OpenSearch **bulk API** — where Fluent Bit's `es` output lands |
| `/insert/jsonline` | JSON-lines / ndjson, with `_stream_fields`, `_time_field`, `_msg_field` |
| `/insert/loki/api/v1/push` | **Loki JSON API** — Promtail / Grafana Alloy push directly |
| `/insert/opentelemetry/v1/logs` | OpenTelemetry log records (OTLP) |
| `-syslog.listenAddr.{tcp,udp,unix}` | VictoriaLogs can **listen for syslog itself**, with per-listener TLS (`-syslog.tls*`) |

Documented collectors: syslog/rsyslog/syslog-ng, **Fluent Bit**, **Vector**, Promtail/Grafana Alloy and
the OpenTelemetry Collector. The `-journald.*` flags mean journald can be read **directly**, without a
separate shipper. Request tuning (`_stream_fields`, `_msg_field`, `_time_field`, …) is shared across
the HTTP APIs as query args or headers, with query args winning.

**7.4 Security posture (official).** The docs state all VictoriaLogs components **must run inside a
protected trusted network**, that Internet requests must be authorized **before** being proxied, and
that **vmauth** is the recommended authorization and load-balancing front end. In-product protection
is `-tls` + `-tlsCertFile` + `-tlsKeyFile` (with `-tlsMinVersion` / `-tlsCipherSuites`) for transport
and `-httpAuth.username` / `-httpAuth.password` for authentication, with per-endpoint `*AuthKey`
overrides for `/delete/*`, `/metrics`, `/flags` and `/internal/force_merge`. There is **no built-in IP
allowlist** — the docs delegate that to the network, which is why the LAN-only rule has to be a
firewall rule rather than a VictoriaLogs flag.

**7.5 Secret handling.** Flags can be fed from the environment: either by referencing `%{ENV_VAR}`
inside a flag value, or by setting flags through env vars with **`-envflag.enable`** — each `.` in the
flag name becomes `_` (`-insert.maxQueueDuration` → `insert_maxQueueDuration`), optionally with an
`-envflag.prefix`. The basic-auth password can therefore be injected as an env var from Key Vault
rather than appearing in the container's argument list.

**7.6 Backup, multitenancy and HA — what is deliberately not adopted.** Per-day partitions make
selective backup straightforward if it is ever wanted: snapshot with
`/internal/partition/snapshot/create?partition_prefix=YYYYMMDD`, copy with `rsync`, restore via
`detach`/`attach` — so "logs are not backed up" is a choice, not a limitation. Multitenancy is an
`(AccountID, ProjectID)` pair with **no per-tenant authorization** (vmauth provides that); a
single-tenant lab stays on the default tenant `0`. HA expects collector-side replication plus several
instances behind vmauth, which is **not adopted** — a store outage drops or queues logs depending on
the collector, acceptable at 30-day retention.

**7.7 Quickstart facts (verified).** The built-in Web UI is at
**`http://localhost:9428/select/vmui`**; data lands in `victoria-logs-data`, relative to
`-storageDataPath`; the documented container invocation is
`docker run -p 9428:9428 -v ./victoria-logs-data:/victoria-logs-data victoriametrics/victoria-logs:<tag>`,
with the image pinned by tag (the docs' example is `v1.52.0`). VictoriaLogs "automatically adapts to
the available CPU and RAM resources", and the journald recipe maps
`_msg_field=MESSAGE&_time_field=__REALTIME_TIMESTAMP&_stream_fields=_SYSTEMD_UNIT` — one stream per
systemd unit.

### 8. How the three engines store and query logs — the mechanism behind the store choice

The article the operator supplied
([ITNEXT](https://itnext.io/how-do-open-source-solutions-for-logs-work-elasticsearch-loki-and-victorialogs-9f7097ecbc2f))
is by **Aliaksandr Valialkin, VictoriaLogs' core developer**, and carries a full-disclosure note to that
effect. It is therefore **vendor-authored — but it is the clearest explanation of *why* the comparison in
§1–§2 comes out the way it does**, and it is the origin of the official docs' "up to 30× less RAM / 15×
less disk than Elasticsearch" headline. Its worked example: **1 billion entries of 1 KiB each** (a typical
Fluent Bit entry — `@timestamp`, `message` and ~20 source-identifying fields).

| | Elasticsearch | Grafana Loki | VictoriaLogs |
|---|---|---|---|
| Unit of indexing | Every **token** in every field | The **labelset** (stream identity) | **Bloom filters** over tokens, per data block |
| Index structure | Inverted index `(field; token) → log ID` | Inverted index over labelsets | **No inverted index** — filters skip data blocks |
| Index size, 1 B entries | ~125 tokens per 1 KiB entry ⇒ **~1 TB** of 64-bit postings, +1 TiB of logs ⇒ **~2 TiB** | Labelset stored once per stream; index negligible against the data | **2 bytes per unique token**; ~5 unique tokens per entry ⇒ **~10 GB** — 10×–100× smaller than an inverted index |
| Log storage | Logs + index; compression helps "a few times" | Grouped by stream, time-sorted, compressed — **5×–10×** ⇒ ~100 GiB | Columnar and per-field, so only requested fields are read |
| Full-text search | **Outstanding** — binary search over sorted postings | **~1000× slower** — unpacks and scans every message in the stream | Slower than Elasticsearch for **simple, selective** queries; usually **faster** for heavy multi-field ones |
| High cardinality | Tolerated, paid for in storage and RAM | **Poor** — unique values in labelsets blow up the index and eat RAM | **Safe** — streams are nominated by the shipper, not derived from every field |
| Documented weakness | Storage/RAM at scale; random reads for large result sets | "Needle in the haystack" queries; structured high-cardinality fields | Simple queries returning few entries read more than Elasticsearch would |

Three things this article corrects or sharpens in the thread's framing:

1. **VictoriaLogs does not "index all fields"** — it creates **no inverted index over field values at
   all**. It tokenises like Elasticsearch, but stores bloom filters and uses them to skip blocks that
   cannot contain the query's words; columnar per-field storage then reads only the requested fields.
2. **Streams still exist, and they are opt-in.** Loki's stream model is kept, but a stream is defined by
   whatever the shipper nominates via `_stream_fields` (or the `VL-Stream-Fields` header) rather than by
   every field. That is the mechanism that makes `trace_id`/`user_id` safe, and it is the same knob the
   collector work in [#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84) will set.
3. **The honest downside.** The author states plainly that simple full-text queries returning few entries
   are **slower than Elasticsearch**, because VictoriaLogs reads more bloom-filter bytes than
   Elasticsearch reads of inverted-index postings; it wins once a query carries several filters over
   different fields. He also declines to cover operational complexity, cost, query-language usability and
   documentation quality — which is precisely the ground ADR 35's decision rests on.

For this fleet the trade lands the same way: the planned queries are stream- and field-filtered sweeps
across a handful of nodes, and the `pve` node's binding constraint is RAM and disk rather than full-text
search latency. The store's weak case is still worth **measuring** during deploy validation rather than
assumed away (see [Open Questions](#open-questions)).

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
- **The store's weak case needs measuring, not assuming.** VictoriaLogs is documented as *slower than
  Elasticsearch* for simple full-text queries returning few entries
  ([§8](#8-how-the-three-engines-store-and-query-logs--the-mechanism-behind-the-store-choice)). The plan
  assumes stream- and field-filtered sweeps, which suits it — deploy validation should include a selective
  "needle in the haystack" search, not only broad scans.
- **Where the LAN-only rule is enforced.** [ADR 34](../decisions/34-lan-tls-only.md) established that
  host UFW does not filter container traffic, so the rule must live inside the LXC or at the Proxmox
  firewall — and be verified from off-LAN, not asserted.
- **Collectors** ([#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84)) — Fluent Bit's `es`
  output is the assumed path, but the store also accepts the Loki push API, JSON-lines and OTLP, and can
  **listen for syslog and read journald itself** ([§7.3](#7-official-documentation--verified-facts-2026-09-27)),
  so some nodes may need no shipper at all — the Edge's RAM-only budget is the constraint on the ones
  that do. Which nodes run a collector is undecided; the store is inert until at least one ships.
- **Certificate trust** — clients skip verification initially (ADR 27/34's residual). Pinning depends
  on the private CA tracked as [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126).
- **Monitoring the store** — how we watch what VictoriaLogs costs the `pve` node, plus the automatic
  check that its HTTPS address and certificate stay healthy (ADR 34's `httpcheck`/`x509check`). Three
  parts, and the first costs nothing:
  - **The node already shows most of it.** Netdata runs on the `pve` host itself
    ([ADR 27](../decisions/27-monitoring-strategy.md)), so the new container appears as a Proxmox guest
    with its CPU, memory and disk — no new software, and no agent inside the container. Netdata keeps
    1-second history for 14 days, 1-minute for 30 and 1-hour for a year, which is enough to watch growth
    against the limits ADR 35 sets.
  - **The store's own numbers.** Netdata can also read VictoriaLogs' `/metrics` page, which reports what
    cannot be seen from outside the container: logs arriving per second, logs dropped for old timestamps
    (`vl_rows_dropped_total`), disk used, and whether the store has gone read-only. That would be added to
    the `netdata` role the same way the UPS job is added today — one optional job file, switched on by a
    variable, with an alarm file beside it. It needs the basic-auth password from Key Vault and must skip
    the self-signed certificate, the same exception already accepted elsewhere. One choice to make:
    `/metrics` is protected by `-httpAuth.*` unless it gets its own `-metricsAuthKey`.
  - **Alarms, not just charts** — on disk growth, on container memory approaching its limit, on dropped
    logs (the VictoriaLogs docs suggest that alarm themselves), and on read-only/disk-full. The existing
    `upsd` alarm file is the model. This is how the risk ADR 35 accepts — a Celeron and 8 GB shared with
    Home Assistant — gets noticed early instead of being discovered as an outage.
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
- [How open source solutions for logs work — Elasticsearch, Loki and VictoriaLogs](https://itnext.io/how-do-open-source-solutions-for-logs-work-elasticsearch-loki-and-victorialogs-9f7097ecbc2f) — vendor-authored engine-level comparison (ITNEXT)
- [Issue #123](https://github.com/jaroslaw-bagnicki/Homelab/issues/123) · [#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84) (collector) · [#75](https://github.com/jaroslaw-bagnicki/Homelab/issues/75) (umbrella) · [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) (private CA)
- [Gemini chat 19](https://share.gemini.google/Z8QXKHmDHOFe) · [Gemini chat 20](https://share.gemini.google/orS2jFh9H1IU)
