# 34 — Log Collector for the Fleet — Fluent Bit, and Why the Victoria Stack Does Not Supply One

**Source**: Official documentation, all read **2026-09-27** —
[VictoriaLogs data ingestion](https://docs.victoriametrics.com/victorialogs/data-ingestion/) ·
[vlagent](https://docs.victoriametrics.com/vlagent/) ·
[VictoriaLogs journald ingestion](https://docs.victoriametrics.com/victorialogs/data-ingestion/journald/) ·
[Fluent Bit → VictoriaLogs](https://docs.victoriametrics.com/victorialogs/data-ingestion/fluentbit/) ·
[Fluent Bit `systemd` input](https://docs.fluentbit.io/manual/data-pipeline/inputs/systemd.md) ·
[Fluent Bit `opentelemetry` output](https://docs.fluentbit.io/manual/data-pipeline/outputs/opentelemetry.md) ·
[OTel Collector `journald` receiver](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/journaldreceiver/README.md) ·
[VictoriaTraces](https://docs.victoriametrics.com/victoriatraces/).
No Gemini thread was used for this document.

**Benchmark source (vendor-authored)**: [Benchmarking Kubernetes Log Collectors: vlagent, Vector, Fluent Bit, OpenTelemetry Collector, and more](https://victoriametrics.com/blog/log-collectors-benchmark-2026/)
(VictoriaMetrics, Mar 2026). Every figure taken from it carries the caveats in [§3](#3-the-vendors-own-collector-benchmark--what-it-does-and-does-not-say).

**Scope**: Pre-ADR research for [#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84) — settle the
**collector** that ships the fleet's logs into the store that is **already deployed**
([ADR 35](../decisions/35-log-store-victorialogs.md) · [runbook 33](../runbooks/33-deploy-victorialogs.md)),
and answer the operator's question directly: **does adopting the whole Victoria stack (logs + metrics +
traces) change the collector choice?** The store, its host and its ingest contract are fixed inputs here,
not re-opened.

**Status**: 📝 Analysis — the collector and the ingestion design are **decided** (decision summary below).
No measurements were taken: the collector's RSS on each node, its behaviour with the store unreachable, and
Fluent Bit packaging on Debian 13 are **unverified** and remain validation work for the role phase. The
decision is recorded authoritatively in [ADR 36](../decisions/36-log-collector-fluentbit.md).

> ⚠️ **Verification status**: the collector comparison rests on **fetched upstream documentation** (§2, §4, §5,
> §6) and on **one vendor-authored benchmark** (§3). The docs are the authority for how each component behaves;
> the benchmark is a claim about relative resource use, on Kubernetes, on hardware unlike this fleet — treat its
> numbers as directional, not as facts about a Wyse 3040 or an M910q. Nothing in this document was run on the
> fleet.

---

## Decision Summary

> **Decision authority:** [ADR 36](../decisions/36-log-collector-fluentbit.md) — Fluent Bit, fleet-wide, one
> shared Ansible role, shipping journald (and Docker's json-file logs on `lab`) into VictoriaLogs. This
> research doc is the analysis that fed that decision; it is not the authority for it.

| Decision | Outcome |
|---|---|
| Collector | **Fluent Bit** — `systemd` (journald) input + `tail` for container log files, HTTP JSON-lines output to the store |
| Collector — rejected | **vlagent** (the Victoria stack's own agent — **no journald source**, disk-buffered by default), **OTel Collector** (alpha journald receiver, `journalctl` shell-out, heaviest), Vector, Grafana Alloy/Promtail, Filebeat, Fluentd, `systemd-journal-upload` |
| Deployment | **systemd-native service per node**, not a container — the `netdata` pattern; one shared role (`fluentbit`), per-node behaviour in `host_vars` |
| Output contract | `https://192.168.2.214:9428/insert/jsonline` — HTTP JSON-lines with `_stream_fields`, `_msg_field`, `_time_field`; TLS on, verification off; HTTP basic auth; gzip |
| Stream fields | journald: `_HOSTNAME` + `_SYSTEMD_UNIT` (mirroring the store's own journald defaults); Docker logs: hostname + container name |
| Buffering | **Memory only** on every node, bounded; the store being unreachable **drops** logs rather than writing them to disk — non-negotiable on `edge` ([ADR 24](../decisions/24-edge-ingress-appliance.md)) |
| Cursor store | On disk (`pve`, `lab`, `nas`); on **tmpfs** (`/run`) on `edge` — no eMMC writes |
| Scope of logs | **Explicit inclusion list** (named units + a priority floor), never all of journald |
| Metrics & traces | **Separate future ADRs** on the same `vtstack` guest — the collector decision is unaffected either way (§7) |
| `cloudlab` | **Never a target** — outside the LAN, Tier A already covers it ([ADR 27](../decisions/27-monitoring-strategy.md)) |

---

## Context

The store is live and **inert**: VictoriaLogs answers on `https://192.168.2.214:9428` with TLS and basic auth,
30-day retention, and a LAN-only rule inside the LXC ([ADR 35](../decisions/35-log-store-victorialogs.md)).
Nothing ships logs to it yet. The driver is unchanged from ADR 35: the **Edge's journald is volatile by
design** ([ADR 24](../decisions/24-edge-ingress-appliance.md), eMMC longevity), so its logs die with every
reboot, and cross-node correlation is impossible while each node's history is local.

Two constraints are inherited from the store and shape every collector option below:

- **Transport is HTTPS-only** ([ADR 34](../decisions/34-lan-tls-only.md)) with a **self-signed** certificate
  — so the collector must support TLS and skip-verification.
- **The store requires HTTP basic auth from day one** ([ADR 35](../decisions/35-log-store-victorialogs.md)) —
  a collector that cannot send credentials cannot write.

And one constraint comes from the Edge appliance: **no persistent writes to the eMMC**
([ADR 24](../decisions/24-edge-ingress-appliance.md)) — which turns "how does this collector buffer when the
store is down?" into a decision, not a default.

[#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84) assumed Fluent Bit and its Elasticsearch
(`es`) output. The operator then raised the wider question: if the **whole Victoria stack** (logs + metrics +
traces) is the destination, should the collector be Victoria's own? That is the question §2 and §7 answer.

---

## Key Findings

### 1. Where this fleet's logs actually live

The collector's input list is dictated by the nodes, not by preference:

| Node | OS | Log sources |
|---|---|---|
| `pve` (Proxmox VE host) | Debian 13 | **journald** — `pveproxy`, `pvedaemon`, `pvestatd`, `pve-firewall`, `ssh`, kernel, systemd; LXC guest console output lands in the host journal |
| `edge` | Debian 13, bare-metal systemd, **no Docker** | **journald** — `cloudflared`, `caddy`, `netdata`, `upsmon`, `fail2ban`, `ssh` |
| `lab` | Ubuntu 24.04 | **journald** (host) + **Docker json-file logs** under `/var/lib/docker/containers/*/*-json.log` (Portainer, Caddy, cloudflared); containerd files once [ADR 22](../decisions/22-k3s-arc-homelab.md)'s k3s lands |
| `nas` (Beetle, OMV 8.5) | Debian | **journald** + OMV's own file logs |
| `vtstack` (LXC 214) | Debian 13 | Docker container output — useful later so the **store's own logs** are searchable in the store |
| `cloudlab` | Ubuntu 24.04 | **out of scope** — not a Tier B target ([ADR 27](../decisions/27-monitoring-strategy.md)) |

**journald is the load-bearing input.** Four of five LAN nodes keep their logs there, and `edge` keeps them
*only* there. Any collector whose journald support is weak or absent is disqualified regardless of how well it
does everything else — which is exactly what §2 shows about the Victoria stack's own agent.

### 2. The Victoria stack has no journald collector — its own agent does not fit its own fleet

`vlagent` is VictoriaMetrics' log collection agent, shipped from the **VictoriaLogs** repository and released
alongside the store. Its documentation lists two log **sources**:

- **Kubernetes pod logs** (`-kubernetesCollector`, the `victoria-logs-collector` Helm chart), and
- **files** on disk (`-fileCollector.glob`).

**There is no journald source.** `vlagent` carries `-journald.*` flags, but they configure the *ingest
protocol* it accepts at `:9429` — the same journald export format VictoriaLogs parses — not a reader that can
open a local systemd journal. To ship journald with the Victoria agent you must put another shipper
(`systemd-journal-upload`) in front of it, which is **two daemons where one would do**.

Two further mismatches:

- **Durability is an on-disk buffer.** When the store is unreachable, `vlagent` buffers at
  `-remoteWrite.tmpDataPath`; without `-remoteWrite.maxDiskUsagePerURL` that buffer is bounded only by free
  disk, and its documented remedy for a growing buffer is more queues or a lower cap. On `edge` this is
  precisely the write pattern [ADR 24](../decisions/24-edge-ingress-appliance.md) exists to prevent.
- **Format parsing is still incomplete, by the vendor's own admission**: "vlagent does not yet support
  multiline log joining (e.g., Java stack traces) or custom format parsing (e.g., nginx access logs)."

And upstream's guidance is not ambiguous about when to use it:

> "Use `vlagent` when: you need to replicate logs to multiple VictoriaLogs instances for high availability;
> you have unstable connectivity to VictoriaLogs and need on-disk buffering; you run Kubernetes and want
> automatic Pod log collection with metadata enrichment. **Send logs directly to VictoriaLogs when you have a
> single instance and a stable network connection — this reduces operational complexity.**"

This fleet is the second case: **one** store, on the LAN, reachable from every node. The Victoria agent is
built for a shape this homelab does not have.

**A correction to carry forward:** research 33 §7.3/§7.7 summarised the store's `-journald.*` flags as meaning
"journald can be read directly, without a separate shipper". The ingested documentation is clearer — the
journald path is an **ingest protocol** (`/insert/journald`, the journald export format) whose documented
client is `systemd-journal-upload` running **on the node**. VictoriaLogs has no way to read a remote node's
journal by itself. ADR 36 records this so the store doc is not read as offering a collector-free fleet.

### 3. The vendor's own collector benchmark — what it does and does not say

VictoriaMetrics benchmarked nine collectors "under identical resource constraints (1 CPU, 1 GiB RAM) and
without any tuning", tailing Kubernetes container logs on a 32-vCPU GCP VM. The headline table:

| Collector | Peak logs/sec (100 pods) | CPU @10k logs/s | Memory @10k logs/s |
|---|---|---|---|
| **vlagent** | 143 000 | 0.062 core | 27.9 MiB |
| Fluent Bit | 31 300 | 0.260 core | 78.1 MiB |
| Vector | 25 000 | 0.412 core | 153.5 MiB |
| OpenTelemetry Collector | 20 500 | 0.491 core | 106.8 MiB |
| Grafana Alloy | 15 700 | 0.578 core | 66.4 MiB |
| Grafana Agent | 14 800 | 0.552 core | 72.5 MiB |
| Promtail | 13 400 | 0.655 core | 63.0 MiB |
| Filebeat | 5 250 | — | — |
| Fluentd | 5 100 | — | — |

**Read it as directional only.** The publishers are the authors of `vlagent`, the workload is Kubernetes
container tails (this fleet has none), the hardware is nothing like a Wyse 3040, and Fluent Bit's and
Filebeat's peaks exceeded the 1 GiB container limit at maximum load (they were OOM-killed) — at roughly
three to four orders of magnitude more logs per second than this fleet will ever produce. Two details from
it remain useful regardless of the numbers: **Fluent Bit and Vector produced split records during container
log rotation** (reported upstream by the benchmark's authors), and **`vlagent` is the lowest-footprint
collector of the set** — a real advantage that does not compensate for having no journald input.

What the table does **not** answer is the only question that matters here: which collector can read this
fleet's logs, on this hardware, with no eMMC writes. §4–§6 answer that.

### 4. `systemd-journal-upload` — the zero-extra-software path, and why it is blocked

VictoriaLogs accepts the **journald export format** at `/insert/journald`, and the documented client is
`systemd-journal-upload`, already present on every node (`/etc/systemd/journal-upload.conf`, one `URL=` line).
That is genuinely attractive for a journald-only node: nothing new to install, one config line, cursors kept
in `/var/lib/systemd/journal-upload/`.

It is nevertheless rejected as *the* collector:

- **It cannot authenticate.** VictoriaLogs' basic auth (`-httpAuth.*`) is global, and
  `systemd-journal-upload` has no documented credential option other than **client certificates** — the
  documentation's own example uses plain `http://`. Credentials via HTTP headers (`Header=`) exist only from
  **systemd v258**, and compression likewise; the fleet runs systemd **255** (Ubuntu 24.04 on `lab`) and
  **257** (Debian 13 on `pve`/`edge`/`nas`). *(systemd versions to be confirmed on the nodes during the role
  work; the decision does not depend on it, because the collector must in any case also ship container logs.)*
- **It ships journald and nothing else** — no container log files, no `lab` Docker logs, no `vtstack`
  container output.
- **It has no filtering worth the name** — no unit selection by list, no priority floor, no field mapping;
  everything journald has goes to the store.

It remains the best candidate for a *second* node type (a future appliance where nothing else fits) and is
recorded as such in ADR 36, not as the fleet collector.

### 5. Fluent Bit ↔ VictoriaLogs — the ingest contract, verified

VictoriaMetrics documents Fluent Bit explicitly, and the documented route is the **HTTP output with JSON
lines** — not the `es` output assumed in [#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84):

```
[Output]
     Name http
     Match *
     Host 192.168.2.214
     Port 9428
     URI /insert/jsonline?_stream_fields=stream&_msg_field=log&_time_field=date
     Format json_lines
     json_date_format iso8601
     Compress gzip
     tls On
     tls.verify Off
     http_user vlogs
     http_passwd <from Key Vault>
```

The `es` output still works — VictoriaLogs serves the Elasticsearch/OpenSearch bulk API at
`/insert/elasticsearch/_bulk` and accepts the same `_stream_fields` / `_msg_field` / `_time_field` query args
— but the JSON-lines route is the one upstream documents for Fluent Bit, and it carries the same HTTP
parameters with less format overhead. **ADR 36 corrects the issue's assumption.**

The store's shared HTTP parameters are what make this a small config rather than a pipeline:

| Parameter | Purpose here |
|---|---|
| `_msg_field` | Which field holds the message — `MESSAGE` for journald records |
| `_time_field` | Which field holds the timestamp — `__REALTIME_TIMESTAMP` (microseconds) for journald |
| `_stream_fields` | Which fields identify a stream — `_HOSTNAME` + `_SYSTEMD_UNIT` |
| `ignore_fields` | Drop noisy fields before they ever reach the store |

Fluent Bit's **`systemd` input** exposes the journal verbatim: `_SYSTEMD_UNIT`, `_HOSTNAME`, `MESSAGE`,
`PRIORITY`, `__REALTIME_TIMESTAMP`. Its documented options that matter here:

| Option | Why it matters |
|---|---|
| `db` | SQLite file tracking the journald **cursor**. Default is *none* — a path must be set or every restart re-reads the journal. On `edge` it goes to **tmpfs**, not the eMMC |
| `systemd_filter` (+ `systemd_filter_type`) | Selects records by journald key/value, e.g. `_SYSTEMD_UNIT=pveproxy.service` — the mechanism behind the explicit inclusion list |
| `tag` with a wildcard | Expands per unit (`host.*` → `host.pveproxy.service`), which is how per-unit routing stays config-driven |
| `strip_underscores` / `lowercase` | Field-name hygiene before the JSON output |
| `max_entries` | Bounds a burst at startup — relevant on nodes with a long journal |

**Two implementation caveats to verify in the role:** a numeric **priority floor** cannot be expressed as a
single journald match (`systemd_filter` is key/value, not a range), so it needs a filter stage on `PRIORITY`;
and the exact field names must be confirmed against the store with the documented `debug=1` parameter before
the first node is trusted.

Fluent Bit's **`opentelemetry` output** supports OTLP/HTTP *and* gRPC for **logs, metrics, traces and
profiles** — so the same agent can later feed VictoriaLogs' `/insert/opentelemetry/v1/logs`, or
VictoriaTraces, without being replaced. That is what makes Fluent Bit a safe long-term choice rather than a
step that has to be undone (§7).

### 6. Buffering and durability — the decision that differs per node

| Node | Buffer | Cursor | Consequence when the store is unreachable |
|---|---|---|---|
| `pve` | Memory, bounded | Disk (`/var/lib/fluent-bit`) | Logs dropped past the memory cap; the cursor means nothing is re-sent on restart |
| `lab` | Memory, bounded | Disk | As above; Docker logs left unread are still on disk and read on recovery |
| `nas` | Memory, bounded | Disk | As above |
| **`edge`** | Memory, bounded, **pause-on-overlimit** | **tmpfs (`/run`)** | Logs are **dropped** — never spooled to the eMMC. A reboot loses the cursor *and* the journal alike, because journald there is volatile by design, so nothing is lost that was not already lost |

The Edge row is the whole point: memory-only buffering plus a tmpfs cursor is the configuration that makes a
log shipper compatible with an 8 GB eMMC. It is also why `vlagent` (§2) and a disk-queue OTel pipeline (§4)
are the wrong shape for this appliance specifically.

### 7. Does the whole-Victoria-stack ambition change the collector? No

The three Victoria backends each have their own ingest path, and **only logs need a node-side agent**:

| Signal | What ships it | Needs a fleet agent? |
|---|---|---|
| **Logs** | Fluent Bit → `/insert/jsonline` | **Yes** — this ADR |
| **Metrics** | Already covered by **Netdata** ([ADR 27](../decisions/27-monitoring-strategy.md)); VictoriaMetrics would be fed by scraping Netdata's Prometheus endpoint (`vmagent`), or by Netdata's remote-write | **No** — a scraper, not a log shipper |
| **Traces** | Instrumented apps send **OTLP** straight to VictoriaTraces (OTLP over HTTP + gRPC, Jaeger Query API for Grafana, built on the VictoriaLogs engine, no object storage) | **No** — there is nothing to install until something is instrumented |

So the "one agent for logs + metrics + traces" argument for a heavier collector has no buyer in this fleet
*today*: traces are direct-to-store, metrics come from Netdata, and the only signal that needs a fleet-wide
agent is logs — the one input where the Victoria-native agent has a gap (§2).

The stack decision still costs the collector nothing, and the collector does not constrain the stack:
`vtstack` is already framed to carry VictoriaMetrics and VictoriaTraces as later services on the same guest
and Compose project ([ADR 35](../decisions/35-log-store-victorialogs.md) · research 33 §4), each as its own
future ADR. One friction to hand those ADRs: [ADR 26](../decisions/26-zigbee-energy-monitoring.md) commits
**Prometheus** for the Zigbee power path, so adopting VictoriaMetrics means substituting a PromQL-compatible
TSDB behind the same Grafana datasource — a reconciliation for that ADR, not a blocker for this one.

---

## Alternatives Considered

| Option | Verdict | Reason |
|---|---|---|
| **Fluent Bit** | ✅ chosen | Stable `systemd` (journald) input + `tail` for container files; memory-only buffering; TLS + basic auth; ~1/4 the memory of OTel Collector; `opentelemetry` output keeps OTLP open for later |
| `vlagent` (Victoria stack's own agent) | ❌ rejected | **No journald source** — needs `systemd-journal-upload` in front of it, two daemons for one job; on-disk buffer by default conflicts with [ADR 24](../decisions/24-edge-ingress-appliance.md); no multiline/format parsing yet; upstream's own guidance is to send directly for a single store on a stable network |
| OpenTelemetry Collector (contrib) | ❌ rejected | `journald` receiver is **alpha**, **shells out to the `journalctl` binary**, and needs root / `systemd-journal` group (in a container: host-rootfs chroot + `CAP_DAC_READ_SEARCH` + `CAP_SYS_PTRACE`); cursors need a `file_storage` extension or restarts silently skip the downtime window; heaviest of the tested collectors; its multi-signal advantage buys nothing here (§7) |
| Vector | ❌ rejected | Capable and well-documented (journald + Docker sources), but heavier than Fluent Bit with more config surface than a five-node fleet needs; recorded as the near-miss |
| Grafana Alloy (and its predecessors Promtail / Grafana Agent) | ❌ rejected | Loki-shaped: it pulls the fleet toward the backend [ADR 35](../decisions/35-log-store-victorialogs.md) rejected, and the vendor's own benchmark lists Promtail and Grafana Agent as Alloy's predecessors — i.e. two generations of churn inside the option |
| Filebeat / Fluentd | ❌ rejected | Both lose logs below 10k logs/s in the vendor benchmark (the lowest throughput of the set), and Filebeat couples the collector to Elasticsearch's ecosystem |
| `systemd-journal-upload` alone | ❌ rejected | No credential path to a basic-auth store before systemd v258 (and none documented beyond client certs); journald only, so it cannot ship `lab`'s Docker logs; no unit/priority filtering |
| **No collector** | ❌ rejected | The store stays inert and the Edge keeps losing its logs on every reboot — the reason the store exists |
| Collector on `lab` only, forwarding for the fleet | ❌ rejected | The Edge's logs would still die locally, and it introduces a `lab` dependency for every node's logs |
| **Whole-Victoria-stack collector** | ⚪ not available | There is no single Victoria agent for logs + metrics + traces; the stack's components each take their own protocol (§7) |

---

## Open Questions

- **No measurements.** RSS per node, the volume of log lines a five-node fleet actually produces against the
  store's 16 GiB volume and 30-day retention, and the store's ingest rate are all unmeasured. Runbook 33 sized
  the store **without** these numbers; the first node's data should be used to re-check both.
- **Fluent Bit packaging on Debian 13.** Upstream APT repository coverage for trixie is unverified, as is the
  choice between the repo package, the static binary and the container image. `edge` has no Docker by design
  ([runbook 24](../runbooks/24-edge-appliance.md)), so at minimum that node takes a package or a binary — a
  role-phase decision.
- **Priority filtering.** `systemd_filter` is a key/value match, not a range, so the "named units plus a
  priority floor" rule in ADR 36 needs a filter stage — and confirmation that `PRIORITY` survives the input
  as expected.
- **Field mapping end to end.** Which Fluent Bit keys land as `_msg` / `_time` / stream fields must be
  verified against the store with `debug=1` before the first node is trusted; the journald protocol's own
  defaults (`_MACHINE_ID`, `_HOSTNAME`, `_SYSTEMD_UNIT`; `MESSAGE`; `__REALTIME_TIMESTAMP`) are the precedent
  to mirror.
- **Store-down behaviour on `edge`.** The in-memory buffer must be observed dropping — not spooling — with
  the store stopped, and the eMMC write counters checked before and after ([ADR 24](../decisions/24-edge-ingress-appliance.md)'s
  acceptance test).
- **Stream-field cardinality.** `_SYSTEMD_UNIT` is high-cardinality for templated units
  (`systemd-coredump@.service`, `.socket` units with `Accept=yes`) — the store's docs warn about exactly this.
  The per-node inclusion list is the mitigation; whether it is needed here is unmeasured.
- **The store's own logs** — shipping `vtstack`'s container output into the store is desirable but ordered
  after the three LAN nodes; the collector's own logs must not be collected recursively by itself.

---

## References

- [ADR 24](../decisions/24-edge-ingress-appliance.md) — Edge appliance (volatile journald, eMMC, no Docker)
- [ADR 26](../decisions/26-zigbee-energy-monitoring.md) — Zigbee power path (committed Prometheus usage)
- [ADR 27](../decisions/27-monitoring-strategy.md) — Tier B strategy; components adopted via their own ADRs; `cloudlab` excluded
- [ADR 34](../decisions/34-lan-tls-only.md) — LAN services are TLS-only; host UFW does not filter LXC traffic
- [ADR 35](../decisions/35-log-store-victorialogs.md) — the store, its host and its ingest contract
- [Research 33](33-centralized-logging-victorialogs.md) — the store analysis; §7 the store's verified mechanics
- [Runbook 33](../runbooks/33-deploy-victorialogs.md) — the deployed store (`vlogs` basic auth, `:9428`, in-LXC UFW)
- [Runbook 24](../runbooks/24-edge-appliance.md) — Edge: cloudflared + Caddy + Netdata as systemd services, no Docker
- [Issue #84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84) — the collector · [#75](https://github.com/jaroslaw-bagnicki/Homelab/issues/75) umbrella · [#132](https://github.com/jaroslaw-bagnicki/Homelab/issues/132) store monitoring
- [Log collector benchmark (vendor-authored)](https://victoriametrics.com/blog/log-collectors-benchmark-2026/) — VictoriaMetrics, Mar 2026
