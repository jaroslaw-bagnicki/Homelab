# 34 — Log Collector for the Fleet — Fluent Bit, and Why the Victoria Stack Does Not Supply One

**Source**: Official documentation, all read **2026-09-27** —
[VictoriaLogs data ingestion](https://docs.victoriametrics.com/victorialogs/data-ingestion/) ·
[vlagent](https://docs.victoriametrics.com/vlagent/) ·
[VictoriaLogs journald ingestion](https://docs.victoriametrics.com/victorialogs/data-ingestion/journald/) ·
[Fluent Bit → VictoriaLogs](https://docs.victoriametrics.com/victorialogs/data-ingestion/fluentbit/) ·
[Fluent Bit `systemd` input](https://docs.fluentbit.io/manual/data-pipeline/inputs/systemd.md) ·
[Fluent Bit `opentelemetry` output](https://docs.fluentbit.io/manual/data-pipeline/outputs/opentelemetry.md) ·
[Fluent Bit built-in parsers](https://github.com/fluent/fluent-bit/blob/master/conf/parsers.conf) ·
[OTel Collector `journald` receiver](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/journaldreceiver/README.md) ·
[Telegraf → VictoriaLogs](https://docs.victoriametrics.com/victorialogs/data-ingestion/telegraf/) ·
[VictoriaTraces](https://docs.victoriametrics.com/victoriatraces/).
The router analysis in [§8](#8-opnsense-futro-s930--the-per-os-exception-and-why-the-fleet-rule-does-not-transfer)
additionally rests on the [FreeBSD port `sysutils/fluent-bit`](https://github.com/freebsd/freebsd-ports/tree/main/sysutils/fluent-bit),
the [OPNsense plugin collection](https://github.com/opnsense/plugins) and the [OPNsense syslog-ng templates](https://github.com/opnsense/core/tree/master/src/opnsense/service/templates/OPNsense/Syslog),
read the same day. No Gemini thread was used for this document.

**Benchmark source (vendor-authored)**: [Benchmarking Kubernetes Log Collectors: vlagent, Vector, Fluent Bit, OpenTelemetry Collector, and more](https://victoriametrics.com/blog/log-collectors-benchmark-2026/)
(VictoriaMetrics, Mar 2026). Every figure taken from it carries the caveats in [§3](#3-the-vendors-own-collector-benchmark--what-it-does-and-does-not-say).

**Scope**: Pre-ADR research for [#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84) — settle the
**collector** that ships the fleet's logs into the store that is **already deployed**
([ADR 35](../decisions/35-log-store-victorialogs.md) · [runbook 33](../runbooks/33-deploy-victorialogs.md)),
and answer the operator's question directly: **does adopting the whole Victoria stack (logs + metrics +
traces) change the collector choice?** The store, its host and its ingest contract are fixed inputs here,
not re-opened. One node in the wider fleet is **analysed but deliberately deferred** rather than decided —
the **OPNsense router** (Futro S930), a FreeBSD appliance that joins later (§8).

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
| Collector | **Fluent Bit** — `systemd` (journald) plus `tail` with the built-in `docker` / `cri` parsers for container logs, HTTP JSON-lines output to the store |
| Collector — rejected | **vlagent** (the Victoria stack's own agent — **no journald source**, disk-buffered by default), **OTel Collector** (alpha journald receiver, `journalctl` shell-out, heaviest), Vector, Grafana Alloy/Promtail, Filebeat, Fluentd, **Telegraf** (no journald input), `systemd-journal-upload` |
| Deployment | **systemd-native service per node**, not a container — the `netdata` pattern; one shared role (`fluentbit`), per-node behaviour in `host_vars` |
| Output contract | `https://192.168.2.214:9428/insert/jsonline` — HTTP JSON-lines with `_stream_fields`, `_msg_field`, `_time_field`; TLS on, verification off; HTTP basic auth; gzip |
| Stream fields | journald: `_HOSTNAME` + `_SYSTEMD_UNIT` (mirroring the store's own journald defaults); Docker logs: hostname + container name |
| Buffering | **Memory only** on every node, bounded; the store being unreachable **drops** logs rather than writing them to disk — non-negotiable on `edge` ([ADR 24](../decisions/24-edge-ingress-appliance.md)) |
| Cursor store | On disk (`pve`, `lab`, `nas`); on **tmpfs** (`/run`) on `edge` — no eMMC writes |
| Scope of logs | **Explicit inclusion list** (named units + a priority floor), never all of journald |
| Metrics & traces | **Separate future ADRs** on the same `vtstack` guest — the collector decision is unaffected either way (§7) |
| `cloudlab` | **Never a target** — outside the LAN, Tier A already covers it ([ADR 27](../decisions/27-monitoring-strategy.md)) |
| OPNsense (Futro S930) | **Deferred** — a per-OS exception ([ADR 27](../decisions/27-monitoring-strategy.md)); Fluent Bit is installable from the FreeBSD port but has **no OPNsense plugin**, so the router's own path is decided when it joins (§8) |

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
| `pve` (Proxmox VE host) | Debian 13 | **journald** — `pveproxy`, `pvedaemon`, `pvestatd`, `pve-firewall`, `ssh`, kernel, systemd; LXC guest console output lands in the host journal. **Plus PVE's on-disk task logs** (`/var/log/pve/tasks/`) and the web-UI access log — see §9 |
| `edge` | Debian 13, bare-metal systemd, **no Docker** | **journald** — `cloudflared`, `caddy`, `netdata`, `upsmon`, `fail2ban`, `ssh` |
| `lab` | Ubuntu 24.04 | **journald** (host) + **Docker json-file logs** under `/var/lib/docker/containers/*/*-json.log` (Portainer, Caddy, cloudflared) — JSON-wrapped and **unbounded by default**, both of which §9 turns into work; **containerd CRI** logs under `/var/log/pods/` once [ADR 22](../decisions/22-k3s-arc-homelab.md)'s k3s lands |
| `nas` (Beetle, OMV 8.5) | Debian | **journald** + OMV's own log directory (`OMV_LOG_DIR`, default `/var/log/openmediavault`) — see §9 |
| `vtstack` (LXC 214) | Debian 13 | Docker container output — useful later so the **store's own logs** are searchable in the store |
| **OPNsense** (Futro S930) — *joins later* | FreeBSD (OPNsense) | **No journald and no Docker** — syslog-ng writing `/var/log/*.log` (`filter.log`, `system.log`, …). Analysed and deferred in §8 |
| `cloudlab` | Ubuntu 24.04 | **out of scope** — not a Tier B target ([ADR 27](../decisions/27-monitoring-strategy.md)) |

**journald is the load-bearing input.** Four of the five nodes in today's fleet keep their logs there, and
`edge` keeps them *only* there. Any collector whose journald support is weak or absent is disqualified regardless of how well it
does everything else — which is exactly what §2 shows about the Victoria stack's own agent. It is not the
*only* shape the collector must handle: §9 inventories all four the fleet presents today or plans for.

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

### 4. `systemd-journal-upload` — no third-party agent, and why it is blocked

VictoriaLogs accepts the **journald export format** at `/insert/journald`, and the documented client is
`systemd-journal-upload` (`/etc/systemd/journal-upload.conf`, one `URL=` line). That is attractive for a
journald-only node: no third-party agent to introduce, one config line, cursors kept in
`/var/lib/systemd/journal-upload/`. **It is not zero-extra-software, though** — `systemd-journal-upload`
ships in the optional **`systemd-journal-remote`** package rather than the base system, so every node using
it needs that package installed. Whether it is present anywhere in this fleet is **unverified** and is
role-phase work.

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

### 5. Fluent Bit ↔ VictoriaLogs — the verified route, and the mapping it still needs

VictoriaMetrics documents Fluent Bit explicitly, and the documented route is the **HTTP output with JSON
lines** — not the `es` output assumed in [#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84). Its
example is deliberately generic (`_stream_fields=stream&_msg_field=log&_time_field=date`); **the field names
are ours to choose, and a single output cannot serve more than one schema.**

| Source shape | Message field | Time field | Stream fields |
|---|---|---|---|
| **journald** (`systemd` input) | `MESSAGE` | `__REALTIME_TIMESTAMP` (µs) | `_HOSTNAME`, `_SYSTEMD_UNIT` |
| **Docker json-file** (`tail` + `docker` parser) | `log` | `time` | hostname, container name |
| **containerd CRI** (`tail` + `cri` parser) | `message` | `time` | hostname, pod/container from the filename |
| **Native files** (`tail`) | the raw line, or a source-specific parsed key | read time | hostname, file/source |

So the role carries **one output block per source shape, matched by tag** (or an equivalent normalising
filter). That is not a stylistic choice: `lab` collects the host journal *and* Docker's container logs, and a
single `_msg_field` / `_time_field` pair cannot resolve both — journald records would reach the store with no
message field and no usable timestamp.

Verified from upstream:

- The endpoint and the shared HTTP parameters (`_msg_field`, `_time_field`, `_stream_fields`,
  `ignore_fields`), passed as query args — query args win over headers.
- TLS (`tls On`, `tls.verify Off` for the self-signed certificate), basic auth (`http_user` / `http_passwd`)
  and `compress gzip`.
- The `es` output still works — VictoriaLogs serves the Elasticsearch/OpenSearch bulk API at
  `/insert/elasticsearch/_bulk` and accepts the same parameters — but JSON-lines is the route upstream
  documents for Fluent Bit, and **ADR 36 corrects the issue's assumption** accordingly.

**Not verified: our own field mapping.** The table above is the design, not a measurement — it must be
confirmed against the store with `debug=1` on the first node before the rollout trusts it
([Open Questions](#open-questions)).

**Two of the rejected collectors also read the journal — but by spawning `journalctl`.** The OTel receiver and
Vector's `journald` source both require the binary to be present and the reader to have suitable permissions;
Fluent Bit links `libsystemd` and reads the journal natively, which is what makes it fit a 2 GB appliance.

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

### 8. OPNsense (Futro S930) — the per-OS exception, and why the fleet rule does not transfer

The router joins the fleet later — it is **held** pending the OPNsense install, now that its
undersized mSATA has been **replaced with a 24 GB module** (2026-10-09,
[research 31](31-futro-s930-hardware-diagnostic.md) · [overview](../overview.md)) — and
[ADR 27](../decisions/27-monitoring-strategy.md) already names FreeBSD "a per-OS exception" for the Netdata
role. It is the same exception here, for a stronger reason: **none of §1's assumptions hold on it.**

| Assumption on the Linux nodes | Reality on OPNsense |
|---|---|
| systemd's journal is the log source | **No journald** — the appliance is FreeBSD and runs **syslog-ng**, writing `/var/log/*.log` (`filter.log`, `system.log`, …) |
| Docker's json-file logs exist on some nodes | **No Docker** — it runs packages and plugins |
| A small cursor file or package on disk is cheap | The **24 GB mSATA is still the scarcest resource** (the fitted 8 GB was replaced 2026-10-09, [research 31](31-futro-s930-hardware-diagnostic.md)) — anything installed or written there spends it |

**Verified: Fluent Bit builds on FreeBSD, but OPNsense has no plugin for it.** FreeBSD's ports tree carries a
maintained `sysutils/fluent-bit` (**v5.1.2**) with an rc.d script, so `pkg install fluent-bit` works in
principle. But `opnsense/plugins` contains **no Fluent Bit plugin** — its net-management entries are
`telegraf`, `netdata`, `zabbix-agent`, `nrpe` and `net-snmp`. On OPNsense that makes Fluent Bit an
**out-of-band package**: no GUI, **absent from the OPNsense configuration backup**, and outside the plugin
dependency handling that spans firmware upgrades. That is a materially weaker position than the same
collector holds on the Debian/Ubuntu nodes, where it is a managed service.

**Two better-integrated paths exist on the router itself:**

| Path | Shape | Caveats to resolve |
|---|---|---|
| **syslog-ng remote logging → the store's syslog listener** | Nothing installed. OPNsense's logging is GUI-managed and its destination template is **TLS-capable** (`ca-dir`, per-destination `cert-file`/`key-file`, certificates generated into `/usr/local/etc/syslog-ng/cert.d`); VictoriaLogs can listen for syslog itself (`-syslog.listenAddr.tcp` + `-syslog.tls*`, TLS 1.3 floor). Config lives in `config.xml`, so it is **backed up and upgrade-safe** | **No authentication** — client certificates (`-syslog.mtls`) are VictoriaLogs **Enterprise-only**, so the listener is encrypted but anonymous, and the LAN rule becomes the entire boundary on a write-accepting port; **no parsing** — `filterlog`'s CSV arrives as one raw message, leaving field extraction to LogsQL at query time; and enabling the listener changes the **deployed store** (flags + the in-LXC UFW rule), not just the router |
| **Telegraf plugin** | OPNsense ships `net-mgmt/telegraf`, and VictoriaMetrics documents Telegraf for VictoriaLogs (`inputs.tail` + `outputs.http` / `outputs.elasticsearch`, with `VL-Msg-Field` / `VL-Time-Field` / `VL-Stream-Fields` headers) | The plugin's GUI exposes a fixed input/output set, so `tail` + `http` would have to live in a drop-in under `/usr/local/etc/telegraf.d/` — **whether the generated config includes that directory is unverified** |
| **Fluent Bit from the FreeBSD port** | One collector, one output contract and one role across the whole fleet — `tail` on `/var/log/*.log` with the same TLS + basic-auth JSON-lines output | The out-of-band package problem above; `newsyslog` rotation semantics to verify (OPNsense manages `/etc/newsyslog.conf`, and Fluent Bit's docs admit it does not fully support `copytruncate` and cannot read `.gz`); cursor placement must avoid the flash |

**Verdict: deferred to the router's own decision.** ADR 36's rule is about journald-bearing Linux nodes; the
router is a FreeBSD appliance with different sources, a different package framework and the tightest storage
in the fleet. Which path wins depends on facts not yet on the table — whether the GUI exposes TCP+TLS for a
destination, whether Telegraf picks up drop-ins, and whether an unauthenticated syslog listener is acceptable
— so it is recorded for **the router's own runbook/ADR when it joins**, with Fluent Bit documented as the
fleet-consistency option rather than the default.

> **Resolved 2026-10-09 — syslog-ng → the VictoriaLogs syslog listener.** The router's path is the **first
> option above**: nothing installed on the router (syslog-ng is OPNsense's own logging daemon), configured
> in-band through the GUI/API (`oxlorg.opnsense.syslog`), and upgrade-safe in `config.xml`. It confirms the
> GUI exposes **TCP + TLS** for a destination. The two accepted caveats are the same ones named above —
> **no authentication** (mTLS is VictoriaLogs *Enterprise*) and **no parsing** (`filterlog` CSV raw). This
> supersedes the "decided when it joins" line; the store's syslog listener (flags + TLS + in-LXC UFW) lands
> as a separate change to [runbook 33](../runbooks/33-deploy-victorialogs.md). See
> [ADR 36's amendment](../decisions/36-log-collector-fluentbit.md) and
> [runbook 35 §13](../runbooks/35-deploy-opnsense.md).

### 9. Source shapes — what each of the fleet's systems actually demands

§1 lists nodes; this is the same ground by **system**, because the collector's work is set by the *shape* of
the source rather than by the distribution's name. The parser names are taken from Fluent Bit's shipped
[`conf/parsers.conf`](https://github.com/fluent/fluent-bit/blob/master/conf/parsers.conf), and the Proxmox and
OMV paths from their own source repositories (`proxmox/pve-manager`, `openmediavault/openmediavault`).

| System | Where its logs are | Fluent Bit input (+ parser) | What it demands |
|---|---|---|---|
| **Debian** (`pve`, `edge`, `nas`, `vtstack`) | systemd journal; `pve` and `nas` *also* keep rsyslog-style files under `/var/log` | `systemd` — no parser needed | If **both** transports are collected, every line is stored twice (rule 1 below) |
| **Ubuntu** (`lab`) | systemd journal (host) | `systemd` | Same rule |
| **Proxmox VE** (on `pve`) | journald (`pveproxy`, `pvedaemon`, `pvestatd`, `pve-firewall`, kernel) **plus PVE's own on-disk task logs** (`/var/log/pve/tasks/`, with an `index`) and the web-UI access log | `systemd` + `tail` on the PVE paths | The task logs are the audit trail of every backup, migration and `vzdump` and exist **only** on disk — a real source, not a duplicate. The access log is high-volume and a candidate for exclusion |
| **OMV** (`nas`) | Debian journald **plus OMV's own log directory** (`OMV_LOG_DIR`, default `/var/log/openmediavault`) | `systemd` + `tail` | The exact file set is to be enumerated on the node; OMV's GUI log viewer serves a different audience from the store |
| **Docker** (`lab` now, `vtstack` later) | `/var/lib/docker/containers/*/*-json.log` (driver `json-file`) | `tail` + the built-in **`docker`** parser (`Format json`, `Time_Key time`) | Each line is **wrapped in JSON** (`log`, `stream`, `time`) — unparsed, every record reaches the store as one opaque blob. **Rotation is unbounded by default** (no `max-size`/`max-file`), a host prerequisite rather than a collector setting. The `docker-events` input is the route to container metadata if it is wanted |
| **k3s / containerd** (`lab`, once [ADR 22](../decisions/22-k3s-arc-homelab.md) lands) | `/var/log/pods/<ns>_<pod>_<uid>/<container>/N.log`, symlinked under `/var/log/containers/` | `tail` + the built-in **`cri`** parser (`time stream logtag message`), with **`kube-custom`** to derive pod/namespace/container from the filename | Staging path and format differ from Docker's; pod **labels and annotations are not in the file**, so metadata enrichment needs the Kubernetes API — a host-level `tail` accepts metadata-free logs, a DaemonSet with the `kubernetes` filter does not |
| **OPNsense / FreeBSD** (planned) | syslog-ng → `/var/log/*.log` — **no journald, no Docker** | `tail`, or no agent at all | §8 |

**Two rules fall out of this.**

1. **One transport per line.** A host that keeps rsyslog-style files beside the journal (`pve`, `nas`) holds
   each line twice, and Fluent Bit will happily ship both. Each node declares the single transport it uses per
   line — almost always the journal — in its `host_vars`. There is no deduplication to switch on at ingest;
   the fix is to not collect the duplicate in the first place.
2. **Two shapes need a parser, and one is a prerequisite.** Docker and CRI logs both need their built-in
   parser or the store receives JSON wrappers instead of messages; and Docker's unbounded default rotation on
   `lab` must be addressed before the collector is trusted not to fall behind a runaway container log.

---

## Alternatives Considered

| Option | Verdict | Reason |
|---|---|---|
| **Fluent Bit** | ✅ chosen | Stable `systemd` (journald) input + `tail` for container files; memory-only buffering; TLS + basic auth; ~1/4 the memory of OTel Collector; `opentelemetry` output keeps OTLP open for later |
| `vlagent` (Victoria stack's own agent) | ❌ rejected | **No journald source** — needs `systemd-journal-upload` in front of it, two daemons for one job; on-disk buffer by default conflicts with [ADR 24](../decisions/24-edge-ingress-appliance.md); no multiline/format parsing yet; upstream's own guidance is to send directly for a single store on a stable network |
| OpenTelemetry Collector (contrib) | ❌ rejected | `journald` receiver is **alpha**, **shells out to the `journalctl` binary**, and needs root / `systemd-journal` group (in a container: host-rootfs chroot + `CAP_DAC_READ_SEARCH` + `CAP_SYS_PTRACE`); cursors need a `file_storage` extension or restarts silently skip the downtime window; heaviest of the tested collectors; its multi-signal advantage buys nothing here (§7) |
| Vector | ❌ rejected | A real, actively maintained project (Datadog-maintained; `sources-journald` + Docker sources), but heavier than Fluent Bit with more config surface than a five-node fleet needs — and its journald source **pipes `journalctl`** rather than reading the journal; recorded as the near-miss |
| Grafana Alloy (and its predecessors Promtail / Grafana Agent) | ❌ rejected | Loki-shaped: it pulls the fleet toward the backend [ADR 35](../decisions/35-log-store-victorialogs.md) rejected, and the vendor's own benchmark lists Promtail and Grafana Agent as Alloy's predecessors — i.e. two generations of churn inside the option |
| Filebeat / Fluentd | ❌ rejected | Both lose logs below 10k logs/s in the vendor benchmark (the lowest throughput of the set), and Filebeat couples the collector to Elasticsearch's ecosystem |
| **Telegraf** | ❌ rejected | Popular, and VictoriaMetrics **documents** it for VictoriaLogs — but it has **no journald input**: its log sources are `tail` (files), `syslog` (listen) and `docker_log` (the Docker API), so it is disqualified on every journald host for the same reason as `vlagent`. Its log path also wraps each line in Telegraf's metric envelope (the documented `VL-Msg-Field` is `tail.value`). Viable on a file/syslog-only appliance, which is why it is the **router's** candidate ([§8](#8-opnsense-futro-s930--the-per-os-exception-and-why-the-fleet-rule-does-not-transfer)) |
| `systemd-journal-upload` alone | ❌ rejected | No credential path to a basic-auth store before systemd v258 (and none documented beyond client certs); journald only, so it cannot ship `lab`'s Docker logs; no unit/priority filtering |
| **No collector** | ❌ rejected | The store stays inert and the Edge keeps losing its logs on every reboot — the reason the store exists |
| Collector on `lab` only, forwarding for the fleet | ❌ rejected | The Edge's logs would still die locally, and it introduces a `lab` dependency for every node's logs |
| **Whole-Victoria-stack collector** | ⚪ not available | There is no single Victoria agent for logs + metrics + traces; the stack's components each take their own protocol (§7) |
| **OPNsense (Futro S930)** | ⚪ deferred | A per-OS exception with no journald and no Docker; Fluent Bit works from the FreeBSD port but has no OPNsense plugin, and two better-integrated paths (syslog-ng, Telegraf) exist on the router itself (§8) |

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
- **Field mapping end to end.** §5's per-source table is the design, and the role implements it as one output
  block per source shape; which Fluent Bit keys actually land as `_msg` / `_time` / stream fields must be
  verified against the store with `debug=1` before the first node is trusted. The journald protocol's own
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
- **Docker's log rotation on `lab`.** The `json-file` driver rotates nothing by default, so `docker info` and
  any `max-size`/`max-file` daemon settings must be checked — an unbounded container log is a host problem the
  collector cannot fix (§9).
- **How k3s logs are collected.** Host-level `tail` over `/var/log/pods/` (metadata-free) versus a DaemonSet
  with the `kubernetes` filter (pod labels and annotations, the standard k3s shape) is decided with
  [ADR 22](../decisions/22-k3s-arc-homelab.md)'s migration, not here (§9).
- **The router's path (OPNsense, §8).** Three options and none decided: syslog-ng → the store's syslog
  listener (nothing installed, but unauthenticated and unparsed), the Telegraf plugin (drop-in support
  unverified), or Fluent Bit from the FreeBSD port (an out-of-band package). Choosing the syslog listener
  also changes the **deployed store** — its flags and the in-LXC UFW rule — not just the router.

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
- [Research 31](31-futro-s930-hardware-diagnostic.md) — Futro S930 (the router; its 24 GB mSATA is the flagged constraint)
- [FreeBSD port `sysutils/fluent-bit`](https://github.com/freebsd/freebsd-ports/tree/main/sysutils/fluent-bit) · [OPNsense plugins](https://github.com/opnsense/plugins) · [OPNsense syslog-ng templates](https://github.com/opnsense/core/tree/master/src/opnsense/service/templates/OPNsense/Syslog) — verified against the repos (§8)
- [Issue #84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84) — the collector · [#75](https://github.com/jaroslaw-bagnicki/Homelab/issues/75) umbrella · [#132](https://github.com/jaroslaw-bagnicki/Homelab/issues/132) store monitoring
- [Log collector benchmark (vendor-authored)](https://victoriametrics.com/blog/log-collectors-benchmark-2026/) — VictoriaMetrics, Mar 2026
