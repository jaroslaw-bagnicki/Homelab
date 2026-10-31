# 49 — Grafana as the Log Pane — VictoriaLogs with the Plugin, or a Loki Migration

**Sources**: official documentation read 2026‑10‑31 —

- [VictoriaLogs Grafana integration](https://docs.victoriametrics.com/victorialogs/integrations/grafana/) · [plugin catalog entry](https://grafana.com/grafana/plugins/victoriametrics-logs-datasource/) (v0.33.1) · [VictoriaLogs querying API](https://docs.victoriametrics.com/victorialogs/querying/)
- [Grafana Docker image](https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/) · [Docker configuration and secrets](https://grafana.com/docs/grafana/latest/setup-grafana/configure-docker/) · [hardware and sizing](https://grafana.com/docs/grafana/latest/setup-grafana/installation/)
- [Grafana Logs Drilldown](https://grafana.com/docs/grafana/latest/explore/simplified-exploration/logs/)
- [Loki deployment modes](https://grafana.com/docs/loki/latest/get-started/deployment-modes/) · [filesystem storage](https://grafana.com/docs/loki/latest/operations/storage/filesystem/) · [retention](https://grafana.com/docs/loki/latest/operations/storage/retention/) · [authentication](https://grafana.com/docs/loki/latest/operations/authentication/) · [HTTP API](https://grafana.com/docs/loki/latest/reference/loki-http-api/)
- [Fluent Bit Loki output](https://docs.fluentbit.io/manual/pipeline/outputs/loki)
- [`Netcracker/qubership-logql-to-logsql-proxy`](https://github.com/Netcracker/qubership-logql-to-logsql-proxy) — the community Loki-API-to-VictoriaLogs proxy (v0.1.0, Apache‑2.0)
- Repo: [ADR 27](../decisions/27-monitoring-strategy.md), [ADR 34](../decisions/34-lan-tls-only.md), [ADR 35](../decisions/35-log-store-victorialogs.md), [ADR 36](../decisions/36-log-collector-fluentbit.md), [ADR 40](../decisions/40-internal-dns-proxy-edge.md), [research 33](33-centralized-logging-victorialogs.md), [research 34](34-log-collector-options.md), [runbook 33](../runbooks/33-deploy-victorialogs.md)

**Scope**: choose the log pane and store, with **Grafana in a Docker container on the `monitor` guest (LXC 214, currently `vtstack`)** as a fixed constraint:

1. **A1** — keep VictoriaLogs, add Grafana with the official `victoriametrics-logs-datasource` plugin.
2. **A2** — keep VictoriaLogs, add Grafana with the **community Loki-API proxy** in front of it, so Grafana's Loki datasource and **Logs Drilldown** work (the literal "Loki UI" path).
3. **B** — migrate the store to Loki and use Grafana's native Loki datasource.

Implementation, dashboards, and the Ansible recipe are **out of scope** here.

**Status**: 📝 Analysis — **proposed** in [ADR 46](../decisions/46-grafana-logs-ui-victorialogs.md), which is still **Proposed**. Decision authority defers to that ADR; this document keeps the analysis and the rejected paths.

> **Verification status.** Product behaviour and limits are sourced from the official docs above. Repo facts are treated as established by reference. **Live measurements are missing**: this dev container has no SSH client, so the Grafana/Loki footprint and the current VictoriaLogs data volume were not measured. Those items are listed in §8 and must be measured before build.

---

## Decision summary

| Question | Recommendation | Status |
|---|---|---|
| Keep VictoriaLogs as the store? | **Yes** — the store choice in [ADR 35](../decisions/35-log-store-victorialogs.md) is not the problem; `vmui` is the problem | **leaning** — §5 |
| Which pane? | **Grafana + the official VictoriaLogs plugin (A1)** — Explore, histogram, live tail, field/stream/pattern breakdown, dashboards, alerting, and a plugin Drilldown drawer, all over LogsQL | **leaning** — §3 |
| Is the literal Loki UI available without Loki? | **Only via A2**, the community proxy — it enables Grafana Logs Drilldown, but it is a **v0.1.0** project with a deliberately partial LogQL translator and known defects | **not adopted** — §4 |
| Migrate to Loki? | **No** — it reverses [ADR 35](../decisions/35-log-store-victorialogs.md) and forces collector, syslog, auth-proxy and retention rework for a UI-only goal | **rejected** — §5 |
| Where does Grafana run? | **Docker Compose on `monitor`**, `network_mode: host`, UFW‑filtered `:3000`, native TLS | **leaning** — §2 |
| Memory / disk | **Raise LXC 214 from 2 GiB to 6 GiB and 16 GiB to 64 GiB** on `pve2` — Grafana's floor is 512 MB, VictoriaLogs reserves a share, and the intended Netdata Parent adds 1–2 GiB | **leaning** — §2.2 |
| Netdata Parent | **Deferred** — the `monitor` guest is the intended home, but the move needs host-native Proxmox children and its own ADR | **intent only** — §2.6 |
| Secrets | Grafana admin password and `secret_key` from Azure Key Vault; reuse the existing `victorialogs-basic-auth-password` for the datasource | **leaning** — §2.4 |
| Decision record | [ADR 46](../decisions/46-grafana-logs-ui-victorialogs.md) | Proposed |

---

## §1 — Fixed context

**The store is live and healthy.** VictoriaLogs `v1.52.0` runs in LXC 214 (currently `vtstack`, intended `monitor`, `192.168.2.214`) on the `pve` node — 2 vCPU, **2048 MiB**, 16 GiB rootfs — with 30-day retention, an 80 % disk cap, a 2 GiB free-space floor, `-memory.allowedPercent=60`, native TLS, HTTP basic auth and an in-LXC UFW allow for `:9428` plus the unauthenticated TLS syslog listener on `:6514` ([ADR 35](../decisions/35-log-store-victorialogs.md) · [runbook 33](../runbooks/33-deploy-victorialogs.md)). The guest is planned to move to the new **`pve2`** (OptiPlex 7040, 256 GB) and be renamed `monitor` before Grafana lands ([Idea 15](../ideas/15-second-proxmox-node.md)).

**The collector contract is simple.** Fluent Bit on every LAN node ships journald and Docker records to `/insert/jsonline` with `_stream_fields=_HOSTNAME,_SYSTEMD_UNIT`, `_msg_field=MESSAGE`, `_time_field=date`, a 5 s flush, gzip and a filesystem buffer ([ADR 36](../decisions/36-log-collector-fluentbit.md) · [role defaults](../../ansible/roles/fluentbit/defaults/main.yml)). No collector change is needed for either A1 or A2.

**The constraints that shape the pane:**

- **TLS-only on the LAN** — a new listener must serve HTTPS, and a container's published port bypasses the host UFW, so the service must bind inside the LXC's namespace and be filtered by the in-LXC UFW ([ADR 34](../decisions/34-lan-tls-only.md)).
- **The edge node owns LAN DNS and the reverse proxy** — `.internal` names resolve through Technitium; Caddy is the single proxy, but services may also serve native TLS directly, as VictoriaLogs and Netdata already do ([ADR 40](../decisions/40-internal-dns-proxy-edge.md)).
- **The 8 GB Celeron host is the constraint** — on `pve1` every added megabyte competes with Home Assistant, Netdata, the CA and the future smart-home guests ([ADR 35](../decisions/35-log-store-victorialogs.md) §Consequences). Moving `monitor` to `pve2` (8 GB, 256 GB) is what makes 6 GiB and 64 GiB credible.
- **Grafana was explicitly optional** — [ADR 35](../decisions/35-log-store-victorialogs.md) rejected it as a prerequisite, and [ADR 27](../decisions/27-monitoring-strategy.md) left the dashboard component to a future ADR. Adopting Grafana now is an amendment, not a new greenfield choice.

**The actual complaint is the pane, not the engine.** `vmui` queries LogsQL correctly; it is the exploration experience — field/value discovery, patterns, saved views, dashboards, correlations — that feels thin. That distinction keeps the scope on the UI layer.

---

## §2 — Common design: Grafana in the `monitor` LXC

Both options share the Grafana deployment; only the datasource and its translator differ.

| Concern | Design | Why |
|---|---|---|
| **Packaging** | Separate Compose project under `/opt/vtstack/grafana` (`grafana/grafana`, explicit tag), `restart: unless-stopped` | Keeps Grafana independent of the store's lifecycle. The **path stays `/opt/vtstack`** through the rename and move — the runbook made it stable so the store can be reorganised without moving data; `monitor` names the host, not the directory |
| **Networking** | `network_mode: host`, Grafana on `:3000`, UFW allows `3000/tcp` from `192.168.2.0/24` | A Docker-published port traverses Docker's iptables path and **bypasses UFW** — the trap already recorded for VictoriaLogs ([ADR 35](../decisions/35-log-store-victorialogs.md)) |
| **TLS** | Native TLS (`GF_SERVER_PROTOCOL=https`, `GF_SERVER_CERT_FILE`, `GF_SERVER_CERT_KEY`) | [ADR 34](../decisions/34-lan-tls-only.md); the first certificate can be self-signed like VictoriaLogs', then a `step-ca` leaf once the root distribution ([#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144)) is complete |
| **Name** | `grafana.internal` as a **static A record → `192.168.2.214`**, served directly; the edge Caddy remains an optional second front | Matches how VictoriaLogs and Netdata are reached; avoids making a UI depend on the edge proxy. Routing it through Caddy is also valid but adds a hop and a second TLS leg |
| **Auth** | Local `admin` from Azure Key Vault; sign-up disabled; anonymous disabled. Authentik generic OAuth comes later ([ADR 44](../decisions/44-authentik-identity-provider.md)) | One operator, no SSO dependency on day one; the Authentik path is already decided fleet-wide |
| **Secrets** | `GF_SECURITY_ADMIN_PASSWORD__FILE` and `GF_SECURITY_SECRET_KEY__FILE` from root-only files, populated from Key Vault | Grafana encrypts datasource credentials with `secret_key`; a stable secret is required or stored datasource passwords become unreadable across recreations. `__FILE` keeps values out of the Compose environment |
| **Persistence** | Bind `/var/lib/grafana`; datasource and dashboards **provisioned from the repo** | Dashboards are reproducible; the SQLite database holds only users/preferences. Grafana documents SQLite as unsuitable for production, but this is a single-user lab and the dashboards are code |
| **Plugin install** | `GF_PLUGINS_PREINSTALL=victoriametrics-logs-datasource@0.33.1` | Pins the plugin with the image tag; installation happens at container start and needs egress to grafana.com |
| **Datasource** | A1: `victoriametrics-logs-datasource` → `https://127.0.0.1:9428`, basic auth `vlogs`, TLS verification skipped or pinned to the store's CA. A2: built-in `loki` datasource → the proxy | Loopback avoids a second LAN hop and the self-signed trust problem; the store still speaks TLS |
| **Resources** | Grafana is a **512 MB / 1 core floor** and a "Small" deployment baseline of **2 cores / 2–4 GB** (Grafana sizing docs); plan **512–768 MB** for this single-user instance | Grafana's floor is not zero; the 6 GiB guest ceiling covers Grafana, VictoriaLogs and the deferred Netdata Parent |
| **Monitoring** | Later: Netdata `httpcheck` / `x509check` against `https://grafana.internal:3000` | [ADR 34](../decisions/34-lan-tls-only.md)'s enforcement pattern; not part of this decision |

### 2.1 Direct TLS versus the edge Caddy

Both are compliant. **Direct** (`grafana.internal` → `.214`, native TLS on `:3000`) matches the store and Netdata, keeps the pane available when `edge` is being maintained, and avoids a second TLS termination. **Through Caddy** (`grafana.internal` → `.240` → `https://192.168.2.214:3000`) centralises certificates and matches [ADR 40](../decisions/40-internal-dns-proxy-edge.md)'s "single proxy" framing, but adds a hop and makes the UI depend on `edge`. This research recommends **direct**, with a Caddy route as a later option if the fleet standardises browser-facing UIs behind it.

### 2.2 Memory: 2 GiB is no longer the right ceiling

VictoriaLogs is started with `-memory.allowedPercent=60`, which is **~1.2 GiB of the 2 GiB ceiling**. Grafana's documented minimum is **512 MB**, and its small-deployment guidance starts at **2–4 GB for the Grafana process alone**; even a lean single-user instance plus the OS, Docker and the plugin leaves no headroom at 2 GiB.

The target is **6 GiB on `pve2`**, with VictoriaLogs' cap dropped to **50 % (3 GiB)** once the Netdata Parent is added:

| Component | Budget |
|---|---:|
| VictoriaLogs (`-memory.allowedPercent=50`) | ~3.0 GiB |
| Netdata Parent (intended, 1–2 GiB for 5–15 children) | ~1.5 GiB |
| Grafana + plugin | 0.5–0.75 GiB |
| OS, Docker, Fluent Bit | ~0.3 GiB |
| **Total** | **~5.3–5.6 GiB** |

That leaves ~0.4–0.7 GiB of burst margin. If the Parent measures at the top of its band, lower VictoriaLogs to 40 % (2.4 GiB) or add RAM to the 7040 (32 GB ceiling); the 8 GB host cannot give the guest more than 6 GiB without starving `pve2` itself. This is a **measure-before-build** item (§8), not a guaranteed fit.

### 2.3 Disk

Grafana adds an image (~0.5–1 GiB) and a SQLite database plus plugins (well under 1 GiB). The current 16 GiB rootfs was sized for the store alone; it cannot carry VictoriaLogs, Grafana **and** the Netdata Parent's ~10 GiB dbengine. The target is **64 GiB on `pve2`** (256 GB), which leaves the store's 80 % cap and the 2 GiB free-space floor intact and room for future VictoriaMetrics/Traces. Keep it thin-provisioned; a full disk still puts VictoriaLogs into read-only mode ([ADR 35](../decisions/35-log-store-victorialogs.md)).

### 2.4 What Grafana adds to the security surface

- A second LAN-facing authenticated web app — UFW `:3000` from the LAN only, no public route.
- Two new secrets (admin password, `secret_key`) beside the existing store password.
- The plugin proxies LogsQL queries to the store over loopback, so the store's own basic auth remains the second line.
- Grafana's local admin is a break-glass account; Authentik OIDC is the planned normal path ([ADR 44](../decisions/44-authentik-identity-provider.md)), not a day-one dependency.

### 2.5 Upgrades

Image tag and plugin version move together. Grafana requires `>=10.4.0` for plugin v0.33.1; the plugin is updated frequently (18 releases in the past year, last 2026‑10‑16). Pin both and update deliberately — an unpinned `latest` plus `GF_PLUGINS_PREINSTALL` without a version would silently move both at container restart.

### 2.6 Deferred — the Netdata Parent on the same guest

The operator's intent is that `monitor` also becomes the **central metrics store**: the Netdata Parent moves from host-native `pve` into a container in this guest, beside VictoriaLogs and Grafana. That is **not decided here** — it needs its own ADR and the checks below.

The condition is structural, not optional: a Parent in the LXC cannot read the Proxmox host's VM/CT cgroups or `/etc/pve` names, so **`pve1` and `pve2` must each run a host-native Netdata child** that streams to the containerised Parent ([research 50](50-netdata-cloud-costs-and-stream-identity.md) §3). The children keep the Proxmox view; the Parent becomes a portable aggregator and pane. The Parent's own collector can be stripped to aggregation-only, or left collecting the `monitor` guest itself.

Sizing and migration notes:

- Research 50 §3 estimates **1–2 GiB RAM** for a Parent aggregating 5–15 children; §7 is the dbengine/registry copy procedure, and §6 confirms `machine_guid` preserves history across the hostname change.
- **Do not blindly copy the old Parent's `machine_guid`** if `pve1` is converted from Parent to child: both would then present the same identity. Copy `dbengine` for the children's history, **mint a new GUID for the new Parent**, or accept a fresh start; test on a scratch container first.
- The move is gated on the `monitor` guest reaching its 6 GiB ceiling, the 64 GiB disk, and the host-native children existing. A future **ADR 47** records the decision and amends [ADR 27](../decisions/27-monitoring-strategy.md)'s parent-placement clause.

---

## §3 — Option A1: VictoriaLogs + the official plugin

### What it provides

The plugin is a **datasource**, not a skin: Grafana's own Explore, panels and alerting run against LogsQL. Documented capabilities ([plugin docs](https://docs.victoriametrics.com/victorialogs/integrations/grafana/)):

- **Explore** with `Raw Logs`, `Range` and `Instant` query types.
- **Live streaming** logs and **incremental hits loading** — the log-volume histogram loads bar by bar instead of blocking the whole range.
- **Logs, Time series, Stats, Table and Heatmap panels**, with transformations.
- **Log level rules** — map any field/value to `critical`/`error`/`warning`/`info`/`debug`/`trace`.
- **Query builder** — typed pipes (filter, modify, aggregate, sort, limit, custom) with field/value suggestions; Builder → Code always, Code → Builder is one-way (no reverse translation yet).
- **Ad-hoc filters**, **template variables**, **derived fields**, and **correlations** (trace → logs since Grafana 12.2; logs → logs; logs → metrics via shared labels).
- **Alerting** on LogsQL queries.
- **Drilldown drawer** (v0.33.0) — breakdown by stream fields, fields and message patterns, filter chips, "Go to editor"; requires VictoriaLogs ≥ 1.21 (pattern filtering ≥ 1.33; the deployed v1.52 satisfies both).
- **Line limits** — default 1000 lines/query, configurable up to 10 000.

### Parity with the Loki experience

| Capability | A1 plugin | Notes |
|---|---|---|
| Explore + log volume histogram | ✅ | Incremental loading, group-by field |
| Live tail | ✅ | "Live streaming" |
| Field/value discovery | ✅ | Stream fields first, then regular fields |
| Patterns | ✅ | In the Drilldown drawer |
| Logs Drilldown **app** | ❌ | Grafana's app is Loki-specific; the plugin ships its own drawer, **Code mode only**, and it starts from `*` rather than the current query |
| LogQL | ❌ | LogsQL; Loki dashboards are not portable |
| Dashboards / alerting | ✅ | Grafana-native, LogsQL queries |
| Ad-hoc filters / variables | ✅ | Extra filters or root-query injection |
| Derived fields / correlations | ✅ | Trace, logs→logs, logs→metrics |
| Multi-tenancy | ⚠️ | `multitenancyHeaders` supported, but the lab is single-tenant |
| Install/adoption | ✅ | Official VictoriaMetrics plugin, 1.1 M queries served in Grafana Cloud, Apache‑2.0 source (catalog labels it "Commercial" as a vendor plugin) |

### Why it fits this fleet

- **No data movement.** The store, retention, collector and syslog path are untouched; `vmui` stays as a break-glass UI.
- **The right query model.** LogsQL's field/stream filters map directly to the collector contract; no label-cardinality discipline is introduced.
- **Additive and reversible.** Stop the Grafana container and the log pipeline is exactly as it was.
- **Resource-bounded.** One process, no extra datastore; the memory question is Grafana's floor, not a second store.

### Risks

- **Plugin/Grafana coupling** — a Grafana upgrade can outrun the plugin; pin both and test after upgrades.
- **Not the literal Loki app** — the missing piece is Grafana's Logs Drilldown app. The plugin's drawer is close but is not the same product surface.
- **LogsQL learning curve** — dashboards are new work; nothing from a Loki dashboard transfers.
- **Plugin installation needs egress** — at container start, `GF_PLUGINS_PREINSTALL` fetches from grafana.com. `monitor` already pulls Docker images and APT packages, so this is consistent, but an air-gapped future would need a baked image.

**Verdict: recommended.**

---

## §4 — Option A2: VictoriaLogs behind a Loki-API proxy (the literal Loki UI)

There *is* a way to keep VictoriaLogs and still use Grafana's Loki datasource and **Logs Drilldown**: put a Loki-compatible query API in front of VictoriaLogs.

[`Netcracker/qubership-logql-to-logsql-proxy`](https://github.com/Netcracker/qubership-logql-to-logsql-proxy) is exactly that — its stated purpose is "**to provide the ability to use Grafana Logs Drilldown with a VictoriaLogs data source**". It is Apache‑2.0, written in Go, and exposes the Loki endpoints Drilldown needs:

```
GET /loki/api/v1/query
GET /loki/api/v1/query_range
GET /loki/api/v1/labels
GET /loki/api/v1/label/{name}/values
GET /loki/api/v1/series
GET /loki/api/v1/detected_labels
GET /loki/api/v1/detected_fields
GET /loki/api/v1/index/stats
GET /loki/api/v1/index/volume
GET /loki/api/v1/index/volume_range
GET /loki/api/v1/drilldown-limits
GET /loki/api/v1/patterns
```

It translates a **deliberately partial** LogQL subset: stream selectors, `|=`/`!=`/`|~`/`!~`, `| json`, `| logfmt`, `count_over_time`, `rate`, and `sum`/`count`/`avg`/`min`/`max` by label. Unsupported constructs such as `line_format`, `label_format` and `topk` return HTTP 400.

**Why it is not the primary recommendation:**

- **Maturity.** The only release is **v0.1.0** (2026‑06‑10); the repository has **0 stars** and is maintained by one organisation. It is active (dependency updates through 2026‑10‑30), but it is not a settled dependency for the fleet's only log pane.
- **A partial translator is a feature, not a bug** — the README lists known issues: some drilldown graphs wrong, level colors missing, some fields/patterns failing, and a regex crash on certain label sets. The author explicitly did not aim for full LogQL coverage.
- **A new always-on component** in the query path, with its own config, concurrency limits, caches and metrics, to be monitored and upgraded.
- **It solves the wrong layer.** The official plugin already gives field/stream/pattern exploration; the proxy's unique value is the **Logs Drilldown app**, which is a UI surface, not a data capability.

**When to revisit:** if, after living with A1, the plugin's drawer proves insufficient *specifically because* it is not Grafana's Logs Drilldown, A2 is the cheaper experiment than B — it keeps the store and collector, adds one container, and is reversible. It should be re-evaluated only after the proxy reaches a stable release and its known issues close.

**Verdict: watch, not adopted.**

---

## §5 — Option B: migrate VictoriaLogs to Loki

### 5.1 What "Loki" means for this fleet

A single **monolithic** Loki (`-target=all`) is the only shape that fits one small guest; Loki documents monolithic mode as suitable for "small read/write volumes of up to approximately 20 GB per day". The alternative — simple-scalable or microservices — needs multiple components and a reverse proxy, and simple-scalable is being **deprecated for Loki 4.0**.

Storage would be **filesystem + TSDB** (the path with no object store), because adding MinIO/S3 on the same 64 GiB guest would defeat the purpose. But Loki's own docs are blunt: the filesystem store is **not supported for production**, has a **~5.5 million chunk-file** failure mode, cannot do HA, and **does not delete chunks based on disk usage or free space** — retention runs only through the compactor, on a 24 h index period, with a `delete_request_store` and a singleton compactor.

That is a materially weaker disk-safety posture than VictoriaLogs' `-retention.maxDiskUsagePercent` + `-storage.minFreeDiskSpaceBytes`, whose explicit purpose is to stop a full disk putting the store into read-only mode ([ADR 35](../decisions/35-log-store-victorialogs.md)).

### 5.2 What has to change

| Layer | Current | Loki migration |
|---|---|---|
| **Store** | VictoriaLogs, single binary, columnar, no object store | Loki monolith + TSDB + filesystem chunks + compactor; 30 d retention and `max_query_lookback`; monitor disk manually |
| **Collector** | Fluent Bit → `/insert/jsonline` with `_stream_fields`/`_msg_field`/`_time_field` | Fluent Bit `loki` output → `/loki/api/v1/push`; `Labels`/`Label_Keys` from `_HOSTNAME` and `_SYSTEMD_UNIT`; fields become **structured metadata** or a JSON line; every node's output block changes |
| **Label discipline** | Stream fields are cheap and cardinality-safe | Labels define streams; high-cardinality labels are the classic Loki failure mode. `_SYSTEMD_UNIT` is bounded per host but the fleet must keep the label set small |
| **Router syslog** | VictoriaLogs TLS listener `:6514` ([ADR 35 amendment](../decisions/35-log-store-victorialogs.md)) | Loki's ingest endpoints are only `POST /loki/api/v1/push` and `POST /otlp/v1/logs` — **no syslog listener**. Needs a relay (syslog-ng/Fluent Bit/Vector) or keeping VictoriaLogs for router logs |
| **Auth** | Native TLS + HTTP basic auth on the store | Loki has **no authentication layer**; a reverse proxy (nginx/Caddy/vmauth) must sit in front, and multi-tenant mode requires `X-Scope-OrgID` unless disabled |
| **TLS** | Native `-tls` | Native `server.http_tls_config`; the proxy must also be TLS |
| **Grafana** | VictoriaLogs plugin | Built-in Loki datasource; **Logs Drilldown app** now works natively |
| **Resources** | 6 GiB LXC, ~3 GiB VL ceiling | Loki + Grafana + a proxy + compactor in the same guest; 6 GiB is the floor and 8 GiB is safer, on an 8 GB host |
| **Backfill** | n/a | No official VictoriaLogs → Loki migration tool was found. The only export is `/select/logsql/query` (JSON lines, `start`/`end`/`limit`/`offset`); a script would map `_stream` fields to labels, `_msg` to the line and `_time` to nanoseconds, then push to Loki. Rate limits, duplicates and a 30-day volume make this real work |

### 5.3 Migration is a project, not a switchover

Three paths, all with costs:

1. **Cutover with a gap** — re-point Fluent Bit, accept that older logs stay only in VictoriaLogs until they age out. Cheapest, but the 30-day window is split across two stores and the old one must be kept alive for a month.
2. **Dual-write trial** — Fluent Bit writes both stores for a period, then cut over. Doubles disk and collector outputs; useful to compare UI/query behaviour, but not a migration by itself.
3. **Backfill** — export from VictoriaLogs and push into Loki. No official tool; a purpose-built script plus rate-limit and duplicate handling. The data volume is not measured (§8), so neither the time nor the disk need is known.

### 5.4 What B buys, and whether it is worth it

**Buys:** the native Loki datasource, Grafana's **Logs Drilldown app**, LogQL, the Loki ecosystem and any future Loki-native tooling. If the requirement were "our dashboards and workflow are Loki-shaped", B would be the honest answer.

**Costs:** reverses the store decision, reworks every collector, removes the router's syslog path or adds a relay, adds an auth proxy, replaces a cardinality-safe engine with a label-discipline one, weakens the disk safety valve, and consumes more of an 8 GB Celeron host. The trigger is a **UI preference**, not an engine requirement.

**Verdict: rejected for now.** Revisit only if the pane requirement becomes "native Loki/Logs Drilldown" *and* A1/A2 have been shown insufficient.

---

## §6 — Comparison

Weights reflect a single-operator lab whose primary complaint is the UI, not the engine.

| Criterion | Weight | A1 plugin | A2 proxy | B Loki |
|---|---:|---:|---:|---:|
| UI fit (Explore, patterns, drilldown) | 25 % | 4 | 5 | 5 |
| Implementation effort | 20 % | 5 | 3 | 1 |
| Resource fit on `pve2` / `monitor` | 15 % | 3 | 3 | 1 |
| Security/ops simplicity | 15 % | 4 | 3 | 2 |
| Reversibility | 10 % | 5 | 4 | 1 |
| Query/dashboard portability | 10 % | 2 | 2 | 5 |
| Fit with the future Victoria stack | 5 % | 4 | 3 | 2 |
| **Weighted score (1–5)** | | **3.95** | **3.50** | **2.60** |

Scoring notes: A1 loses on portability (LogsQL, not LogQL) and on the missing Logs Drilldown app; A2 gains the app but loses on maturity and adds a component; B wins the UI/portability columns and loses almost everything else.

**Recommendation: A1.** It resolves the actual complaint — a thin exploration pane — with an official, reversible, resource-bounded addition and **no change to the log pipeline**. A2 is the documented fallback if the plugin's drawer is judged insufficient; B is not justified by the requirement.

---

## §7 — Rollout and rollback

**A1 (recommended)** — additive, so rollback is "stop and remove the Grafana Compose project":

1. Move LXC 214 to `pve2`, rename it `monitor`, and size it **6 GiB / 64 GiB** after measuring the host and store (§8).
2. Add the Grafana Compose service, UFW `3000/tcp` from `192.168.2.0/24`, native TLS, `network_mode: host`.
3. Create `grafana-admin-password` and `grafana-secret-key` in Key Vault; write root-only files; wire `__FILE` variables.
4. Provision the datasource (`victoriametrics-logs-datasource` → `https://127.0.0.1:9428`, basic auth `vlogs`) and the dashboards from the repo.
5. Verify: `https://grafana.internal:3000` answers, datasource "Save & test" passes, Explore returns journald records, histogram and live tail work, the Drilldown drawer opens, UFW blocks a non-LAN source.
6. Rollback: `docker compose down` + remove the UFW rule and DNS record. VictoriaLogs, Fluent Bit and the syslog path are untouched.

**A2** — same Grafana base, plus the proxy container and a Loki datasource; keep it out of the primary path until the proxy's known issues close. Rollback removes the proxy and the Loki datasource.

**B** — not planned here; it would need its own ADR superseding [ADR 35](../decisions/35-log-store-victorialogs.md), an amendment to [ADR 36](../decisions/36-log-collector-fluentbit.md), an auth-proxy decision, and a migration/rollback plan. A destructive cutover is never the first step.

---

## §8 — Claims to verify before build

| Claim | Why it matters |
|---|---|
| **`pve2` free RAM** and whether 6 GiB for LXC 214 leaves the host enough headroom | The whole memory recommendation rests on it |
| **Grafana idle RSS** for the pinned image (512 MB is a documented floor, not a measurement) | Confirms 6 GiB is enough; a spike during dashboard renders is the risk |
| **Netdata Parent RSS** at the fleet's retention and 5–15 children | The 1–2 GiB estimate decides whether 6 GiB holds with VictoriaLogs at 50 % |
| **Current VictoriaLogs data size** and daily ingest rate | Confirms the 64 GiB rootfs and the 80 % cap still leave room for Grafana and Netdata |
| **Plugin/Grafana version pair** — latest Grafana release compatible with `victoriametrics-logs-datasource@0.33.1` | Both are pinned; a mismatch is a failed datasource |
| **`GF_PLUGINS_PREINSTALL` egress** from `monitor` to grafana.com | The plugin installs at container start |
| **Grafana `__FILE` secrets and native-TLS env names** on the pinned image | Confirmed in current docs, but the image version must be checked |
| **Datasource provisioning with `$ENV` password and `tlsSkipVerify`** | Avoids a plaintext secret in the provisioning file; the self-signed store needs either skip-verify or the CA |
| **`grafana.internal` record type** — static A to `.214` versus the `*.internal` wildcard to `.240` | Direct TLS only works with the static record; the alternative is the edge Caddy |
| **Step-ca leaf issuance for Grafana** and root distribution ([#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144)) | Self-signed is acceptable initially, but the fleet CA is the target |
| **Loki has no syslog listener** | Inferred from the HTTP API's ingest endpoints (`/loki/api/v1/push`, `/otlp/v1/logs`); confirm before treating B's syslog gap as real |
| **A2 proxy** — release cadence, issue closure, and whether its `drilldown-limits` covers Grafana's current Drilldown version | It is the only literal-Loki-UI path without Loki |

---

## §9 — Conclusions

1. **The store is not the problem.** VictoriaLogs is meeting its contract; replacing it to improve the pane would trade a working, cardinality-safe, disk-capped engine for a heavier, label-constrained one and a rewrite of every collector.
2. **A1 is the right first move.** The official plugin delivers the Grafana experience — Explore, histogram, live tail, levels, patterns, dashboards, alerting, correlations and a Drilldown drawer — over the existing store with no pipeline change.
3. **The literal Loki UI is available without Loki only through A2**, the community LogQL→LogsQL proxy. It is real and purpose-built for Logs Drilldown, but at v0.1.0 with a partial translator and known defects it is a **watch item**, not the fleet's log pane.
4. **B is rejected for now.** It buys Logs Drilldown and LogQL but costs the store decision, the collector contract, the router's syslog path, an auth proxy, the disk safety valve and scarce `pve2` memory.
5. **Grafana is an amendment, not a reversal.** [ADR 35](../decisions/35-log-store-victorialogs.md)'s "Grafana is not a prerequisite" remains true — the store works without it — but the pane is now Grafana, and `vmui` stays as break-glass.
6. **The Netdata Parent is an intent, not a decision.** The `monitor` guest is the intended central metrics store, but the move needs host-native `pve1`/`pve2` children and its own ADR; it is deferred, not bundled into the Grafana decision (§2.6).

## References

- [ADR 46 — Grafana as the log pane, VictoriaLogs retained](../decisions/46-grafana-logs-ui-victorialogs.md) — **the decision this analysis proposes**
- [ADR 35 — VictoriaLogs log store](../decisions/35-log-store-victorialogs.md) · [ADR 36 — Fluent Bit collector](../decisions/36-log-collector-fluentbit.md) · [ADR 34 — TLS-only LAN](../decisions/34-lan-tls-only.md) · [ADR 27 — monitoring strategy](../decisions/27-monitoring-strategy.md) · [ADR 40 — DNS and edge proxy](../decisions/40-internal-dns-proxy-edge.md) · [ADR 44 — Authentik](../decisions/44-authentik-identity-provider.md)
- [Research 33 — VictoriaLogs store and host](33-centralized-logging-victorialogs.md) · [research 34 — collector options](34-log-collector-options.md) · [research 50 — Netdata Cloud costs, stream identity and Parent migration](50-netdata-cloud-costs-and-stream-identity.md) · [runbook 33 — deploy VictoriaLogs](../runbooks/33-deploy-victorialogs.md)
- [Idea 15 — a second Proxmox node (`pve2`)](../ideas/15-second-proxmox-node.md) — the move that makes the 6 GiB / 64 GiB guest possible
- Upstream: [VictoriaLogs Grafana integration](https://docs.victoriametrics.com/victorialogs/integrations/grafana/) · [plugin catalog](https://grafana.com/grafana/plugins/victoriametrics-logs-datasource/) · [Grafana Docker](https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/) · [Grafana sizing](https://grafana.com/docs/grafana/latest/setup-grafana/installation/) · [Grafana Logs Drilldown](https://grafana.com/docs/grafana/latest/explore/simplified-exploration/logs/) · [Loki deployment modes](https://grafana.com/docs/loki/latest/get-started/deployment-modes/) · [Loki filesystem storage](https://grafana.com/docs/loki/latest/operations/storage/filesystem/) · [Loki retention](https://grafana.com/docs/loki/latest/operations/storage/retention/) · [Loki authentication](https://grafana.com/docs/loki/latest/operations/authentication/) · [Loki HTTP API](https://grafana.com/docs/loki/latest/reference/loki-http-api/) · [Fluent Bit Loki output](https://docs.fluentbit.io/manual/pipeline/outputs/loki)
- [Netcracker/qubership-logql-to-logsql-proxy](https://github.com/Netcracker/qubership-logql-to-logsql-proxy) — the A2 proxy
