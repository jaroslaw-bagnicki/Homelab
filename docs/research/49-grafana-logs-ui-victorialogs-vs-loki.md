# 49 — Observability Host — Collocating VictoriaLogs, Netdata Parent and Grafana

**Sources**: official documentation read 2026‑10‑31 —

- [VictoriaLogs Grafana integration](https://docs.victoriametrics.com/victorialogs/integrations/grafana/) · [plugin catalog entry](https://grafana.com/grafana/plugins/victoriametrics-logs-datasource/) (v0.33.1) · [VictoriaLogs querying API](https://docs.victoriametrics.com/victorialogs/querying/)
- [Grafana Docker image](https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/) · [Docker configuration and secrets](https://grafana.com/docs/grafana/latest/setup-grafana/configure-docker/) · [hardware and sizing](https://grafana.com/docs/grafana/latest/setup-grafana/installation/)
- [Grafana Logs Drilldown](https://grafana.com/docs/grafana/latest/explore/simplified-exploration/logs/)
- [Loki deployment modes](https://grafana.com/docs/loki/latest/get-started/deployment-modes/) · [filesystem storage](https://grafana.com/docs/loki/latest/operations/storage/filesystem/) · [retention](https://grafana.com/docs/loki/latest/operations/storage/retention/) · [authentication](https://grafana.com/docs/loki/latest/operations/authentication/) · [HTTP API](https://grafana.com/docs/loki/latest/reference/loki-http-api/)
- [Fluent Bit Loki output](https://docs.fluentbit.io/manual/pipeline/outputs/loki)
- [`Netcracker/qubership-logql-to-logsql-proxy`](https://github.com/Netcracker/qubership-logql-to-logsql-proxy) — the community Loki-API-to-VictoriaLogs proxy (v0.1.0, Apache‑2.0)
- Repo: [ADR 27](../decisions/27-monitoring-strategy.md), [ADR 34](../decisions/34-lan-tls-only.md), [ADR 35](../decisions/35-log-store-victorialogs.md), [ADR 36](../decisions/36-log-collector-fluentbit.md), [ADR 40](../decisions/40-internal-dns-proxy-edge.md), [research 33](33-centralized-logging-victorialogs.md), [research 34](34-log-collector-options.md), [runbook 33](../runbooks/33-deploy-victorialogs.md)

**Scope**: choose the log pane and store, with **Grafana collocated with VictoriaLogs and the Netdata Parent in the `monitor` guest (LXC 214, currently `vtstack`)** as a fixed constraint:

1. **A1** — keep VictoriaLogs, add Grafana with the official `victoriametrics-logs-datasource` plugin.
2. **A2** — keep VictoriaLogs, add Grafana with the **community Loki-API proxy** in front of it, so Grafana's Loki datasource and **Logs Drilldown** work (the literal "Loki UI" path).
3. **B** — migrate the store to Loki and use Grafana's native Loki datasource.

Implementation, dashboards, and the Ansible recipe are **out of scope** here.

**Status**: 📝 Analysis — **proposed** in [ADR 46](../decisions/46-grafana-logs-ui-victorialogs.md), which is still **Proposed**. Decision authority defers to that ADR; this document keeps the analysis and the rejected paths.

> **Verification status.** Product behaviour and limits are sourced from the official docs above. Repo facts are treated as established by reference. **Measured:** VictoriaLogs uses 250–300 MB RAM, the Netdata Parent ~500 MB. The Grafana footprint and VictoriaLogs data volume are still unmeasured; those items remain in §8.

---

## Decision summary

| Question | Recommendation | Status |
|---|---|---|
| Keep VictoriaLogs as the store? | **Yes** — the store choice in [ADR 35](../decisions/35-log-store-victorialogs.md) is not the problem; `vmui` is the problem | **leaning** — §5 |
| Which pane? | **Grafana + the official VictoriaLogs plugin (A1)** — Explore, histogram, live tail, field/stream/pattern breakdown, dashboards, alerting, and a plugin Drilldown drawer, all over LogsQL | **leaning** — §3 |
| Is the literal Loki UI available without Loki? | **Only via A2**, the community proxy — it enables Grafana Logs Drilldown, but it is a **v0.1.0** project with a deliberately partial LogQL translator and known defects | **not adopted** — §4 |
| Migrate to Loki? | **No** — it reverses [ADR 35](../decisions/35-log-store-victorialogs.md) and forces collector, syslog, auth-proxy and retention rework for a UI-only goal | **rejected** — §5 |
| Where does Grafana run? | **Docker Compose on `monitor`**, `network_mode: host`, UFW‑filtered `:3000` (edge only), native TLS | **leaning** — §2 |
| Memory / disk | **Raise LXC 214 from 2 GiB to 4 GiB and 16 GiB to 32 GiB on `pve` now**; expand to 64 GiB when it moves to `pve2` | **leaning** — §2.2 |
| Netdata Parent | **Collocated first** — the Parent moves into `monitor` before Grafana; `pve`/`pve2` run host-native children | **decided in ADR 46** — §2.6 |
| Secrets | Grafana admin password and `secret_key` from Azure Key Vault; reuse the existing `victorialogs-basic-auth-password` for the datasource | **leaning** — §2.4 |
| Decision record | [ADR 46](../decisions/46-grafana-logs-ui-victorialogs.md) | Proposed |

---

## §1 — Fixed context

**The store is live and healthy.** VictoriaLogs `v1.52.0` runs in LXC 214 (currently `vtstack`, intended `monitor`, `192.168.2.214`) on `pve` — 2 vCPU, **2048 MiB**, 16 GiB rootfs — with 30-day retention, an 80 % disk cap, a 2 GiB free-space floor, `-memory.allowedPercent=60`, native TLS, HTTP basic auth and an in-LXC UFW allow for `:9428` plus the unauthenticated TLS syslog listener on `:6514` ([ADR 35](../decisions/35-log-store-victorialogs.md) · [runbook 33](../runbooks/33-deploy-victorialogs.md)). The measured usage is **250–300 MB**, leaving room for the collocation. The refactor runs **on `pve` now** — 4 GiB / 32 GiB — and moves to **`pve2`** (OptiPlex 7040, 256 GB) later with a 64 GiB disk ([Idea 15](../ideas/15-second-proxmox-node.md)).

**The collector contract is simple.** Fluent Bit on every LAN node ships journald and Docker records to `/insert/jsonline` with `_stream_fields=_HOSTNAME,_SYSTEMD_UNIT`, `_msg_field=MESSAGE`, `_time_field=date`, a 5 s flush, gzip and a filesystem buffer ([ADR 36](../decisions/36-log-collector-fluentbit.md) · [role defaults](../../ansible/roles/fluentbit/defaults/main.yml)). No collector change is needed for either A1 or A2.

**The constraints that shape the pane:**

- **TLS-only on the LAN** — a new listener must serve HTTPS, and a container's published port bypasses the host UFW, so the service must bind inside the LXC's namespace and be filtered by the in-LXC UFW ([ADR 34](../decisions/34-lan-tls-only.md)).
- **The edge node owns LAN DNS and the reverse proxy** — `.internal` names resolve through Technitium; Caddy is the single proxy, but services may also serve native TLS directly, as VictoriaLogs and Netdata already do ([ADR 40](../decisions/40-internal-dns-proxy-edge.md)).
- **`pve` has room today; `pve2` is the later expansion.** The 8 GB host has no Home Assistant VM yet: 4 GiB for `monitor`, 512 MB for the CA, the Proxmox host and the Netdata children fit. The 128 GB SSD's ~68 GiB `local-lvm` allows **32 GiB** for the guest now, not 64; `pve2`'s 256 GB carries the 64 GiB expansion later.
- **Grafana was explicitly optional** — [ADR 35](../decisions/35-log-store-victorialogs.md) rejected it as a prerequisite, and [ADR 27](../decisions/27-monitoring-strategy.md) left the dashboard component to a future ADR. Adopting Grafana now is an amendment, not a new greenfield choice.

**The actual complaint is the pane, not the engine.** `vmui` queries LogsQL correctly; it is the exploration experience — field/value discovery, patterns, saved views, dashboards, correlations — that feels thin. That distinction keeps the scope on the UI layer.

---

## §2 — Grafana in the collocated `monitor` LXC

Both pane options share the Grafana deployment; only the datasource and its translator differ. The LXC also carries VictoriaLogs and — after the first phase — the Netdata Parent.

| Concern | Design | Why |
|---|---|---|
| **Packaging** | Separate Compose project under `/opt/vtstack/grafana` (`grafana/grafana`, explicit tag), `restart: unless-stopped` | Keeps Grafana independent of the store's lifecycle. The **path stays `/opt/vtstack`** through the rename and move — the runbook made it stable so the store can be reorganised without moving data; `monitor` names the host, not the directory |
| **Networking** | `network_mode: host`, Grafana on `:3000`, UFW allows `3000/tcp` **from `edge` only** | A Docker-published port traverses Docker's iptables path and **bypasses UFW** — the trap already recorded for VictoriaLogs ([ADR 35](../decisions/35-log-store-victorialogs.md)). Only the edge Caddy needs the backend port |
| **TLS** | Native TLS (`GF_SERVER_PROTOCOL=https`, `GF_SERVER_CERT_FILE`, `GF_SERVER_CERT_KEY`) | [ADR 34](../decisions/34-lan-tls-only.md); the first certificate can be self-signed like VictoriaLogs', then a `step-ca` leaf once issued. Root distribution is complete ([#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144), [PR #157](https://github.com/jaroslaw-bagnicki/Homelab/pull/157)); only Grafana's leaf and client trust remain |
| **Name** | `grafana.internal` through the **edge Caddy** → `https://192.168.2.214:3000`; the `*.internal` wildcard already points at `edge` | [ADR 40](../decisions/40-internal-dns-proxy-edge.md) keeps Caddy as the single LAN routing authority. No static A record to `.214`. The current Caddy role has no backend CA/SNI support, so the hop uses `tls_skip_verify` — encrypted but unverified until the role is extended |
| **Auth** | Local `admin` from Azure Key Vault; sign-up disabled; anonymous disabled. Authentik generic OAuth comes later ([ADR 44](../decisions/44-authentik-identity-provider.md)) | One operator, no SSO dependency on day one; the Authentik path is already decided fleet-wide |
| **Secrets** | `GF_SECURITY_ADMIN_PASSWORD__FILE` and `GF_SECURITY_SECRET_KEY__FILE` from **root:472, mode 0440** files, populated from Key Vault | Grafana runs as UID/GID 472; group-read lets it load the files without world-readable secrets. A stable `secret_key` is required or stored datasource passwords become unreadable across recreations. `__FILE` keeps values out of the Compose environment |
| **Persistence** | Bind `/var/lib/grafana`; datasource and dashboards **provisioned from the repo** | The repo files are authoritative for definitions, but SQLite still holds users, preferences, datasource records (including the encrypted `vlogs` credential) and provisioned dashboard state. Persist and back up `/var/lib/grafana` with `secret_key`. Grafana documents SQLite as unsuitable for production, but this is a single-user lab |
| **Plugin install** | `GF_PLUGINS_PREINSTALL=victoriametrics-logs-datasource@0.33.1` | Pins the plugin with the image tag; installation happens at container start and needs egress to grafana.com |
| **Datasource** | A1: `victoriametrics-logs-datasource` → `https://127.0.0.1:9428`, basic auth `vlogs`, TLS verification skipped or pinned to the store's CA. A2: built-in `loki` datasource → the proxy | Loopback avoids a second LAN hop and the self-signed trust problem; the store still speaks TLS |
| **Resources** | Grafana is a **512 MB / 1 core floor** and a "Small" deployment baseline of **2 cores / 2–4 GB** (Grafana sizing docs); plan **512–768 MB** for this single-user instance | Grafana's floor is not zero; the 4 GiB guest covers Grafana + VictoriaLogs + the Netdata Parent |
| **Monitoring** | Later: Netdata `httpcheck` / `x509check` against `https://grafana.internal` (Caddy); optionally probe `https://127.0.0.1:3000` from `monitor` | `:3000` is the edge-only backend, not a LAN browser URL; [ADR 34](../decisions/34-lan-tls-only.md)'s enforcement pattern |

### 2.1 LAN entrypoint: the edge Caddy

**Caddy is the LAN entrypoint**, per [ADR 40](../decisions/40-internal-dns-proxy-edge.md). The `*.internal` wildcard already resolves to `edge`, so Grafana needs no static A record: add one Caddy site for `grafana.internal` and proxy it to `https://192.168.2.214:3000`. Caddy terminates the browser-facing certificate and keeps the single-proxy rule; Grafana still serves native TLS for the edge→backend hop. Caddy's current role has no backend CA trust or `tls_server_name`, so that hop uses **`tls_skip_verify`** — encrypted but unverified. Verified `step-ca` backend TLS is a follow-up, not a current claim.

A direct `grafana.internal` → `.214:3000` static record was considered and rejected: it creates a second routing authority and contradicts ADR 40. The cost is a dependency on `edge` — accepted, because ADR 40 already makes it the LAN naming and proxy entrypoint. UFW on `monitor` allows `:3000` only from `192.168.2.240`, not the whole LAN.

### 2.2 Memory: 4 GiB for all three

VictoriaLogs currently uses **250–300 MB**; the Netdata Parent uses **~500 MB**. The old 1–2 GiB Parent estimate was conservative and does not justify 6 GiB. The single target is **4 GiB on `pve`**:

| Component | Measured | Cap |
|---|---:|---:|
| VictoriaLogs | 250–300 MB | **1.5 GiB** |
| Netdata Parent | ~500 MB | **1.0 GiB** |
| Grafana + plugin | ~250–500 MB expected | **0.75 GiB** |
| OS, Docker, Fluent Bit | ~300 MB | **0.5 GiB** |
| **Total** | **~1.3–1.6 GiB** | **3.75 GiB** |

That is ~0.25 GiB of cap margin and ~2.4 GiB of actual headroom for LogsQL scans, Grafana renders and query spikes. The role currently sets `-memory.allowedPercent=60`; change it to **37%** (≈1.48 GiB on 4 GiB) or use `-memory.allowedBytes=1536MiB` in the same deploy. No 6 GiB phase; if the Parent's Docker collection or retention grows, tune inside the 4 GiB budget first.

### 2.3 Disk: 32 GiB now, 64 GiB on `pve2`

`pve`'s `local-lvm` is ~68 GiB. Today `vtstack` uses 16 GiB and `ca` 8 GiB; a **32 GiB** guest makes 40 GiB used, leaving ~28 GiB. A 64 GiB guest would make 72 GiB and overcommit the pool. **32 GiB is provisional**, not proven: the store's 80% cap, the ~10 GiB Netdata dbengine, Grafana and the OS share the rootfs. Measure VictoriaLogs data size and ingest rate before the resize; confirm 32 GiB or lower the store cap/add a separate volume. The 64 GiB expansion waits for `pve2`'s 256 GB disk, in the same scope as the guest move ([Idea 15](../ideas/15-second-proxmox-node.md)).

### 2.4 What Grafana adds to the security surface

- A second LAN-facing authenticated web app — UFW `:3000` from `edge` only, reached through Caddy; no public route.
- Two new secrets (admin password, `secret_key`) beside the existing store password.
- The plugin proxies LogsQL queries to the store over loopback, so the store's own basic auth remains the second line.
- Grafana's local admin is a break-glass account; Authentik OIDC is the planned normal path ([ADR 44](../decisions/44-authentik-identity-provider.md)), not a day-one dependency.

### 2.5 Upgrades

Image tag and plugin version move together. Grafana requires `>=10.4.0` for plugin v0.33.1; the plugin is updated frequently (18 releases in the past year, last 2026‑10‑16). Pin both and update deliberately — an unpinned `latest` plus `GF_PLUGINS_PREINSTALL` without a version would silently move both at container restart.

### 2.6 Netdata Parent first

The Parent moves from host-native `pve` into a container in `monitor` **before Grafana**. The Proxmox view moves to **host-native Netdata children** on `pve` (now) and `pve2` (when it exists); `lab`, `nas` and `edge` re-point to `monitor:19996:SSL`.

- **Collection:** the Parent keeps collecting the `monitor` LXC and its Docker containers. Use cgroup namespace host + a read-only `/sys/fs/cgroup` mount for per-container CPU/memory/disk/network; add container names/state/health through a **GET-only Docker socket proxy**, not the raw socket.
- **Dashboard:** `netdata.internal` goes through Caddy on `edge` to `https://192.168.2.214:19999`; UFW `:19999` on `monitor` is edge-only, while `:19996` stays open to the child nodes.
- **History:** copy `dbengine`; keep the children's `machine_guid`; **mint a new GUID for the new Parent**. Do not copy the old Parent's `registry/netdata_random_unique_id` while `pve` becomes a child — both would present the same identity. Test on a scratch container and keep the old Parent until verified.
- **Sizing:** the measured ~500 MB fits the 1.0 GiB cap. The retention stays 14 d / 5 GiB at 1 s, 30 d / 2 GiB at 1 m, 365 d / 2 GiB at 1 h (~10 GiB dbengine, inside the 32 GiB disk).

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

Storage would be **filesystem + TSDB** (the path with no object store), because adding MinIO/S3 on the same `monitor` guest would defeat the purpose. But Loki's own docs are blunt: the filesystem store is **not supported for production**, has a **~5.5 million chunk-file** failure mode, cannot do HA, and **does not delete chunks based on disk usage or free space** — retention runs only through the compactor, on a 24 h index period, with a `delete_request_store` and a singleton compactor.

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
| Resource fit on `pve` / `monitor` | 15 % | 3 | 3 | 1 |
| Security/ops simplicity | 15 % | 4 | 3 | 2 |
| Reversibility | 10 % | 5 | 4 | 1 |
| Query/dashboard portability | 10 % | 2 | 2 | 5 |
| Fit with the future Victoria stack | 5 % | 4 | 3 | 2 |
| **Weighted score (1–5)** | | **3.95** | **3.50** | **2.60** |

Scoring notes: A1 loses on portability (LogsQL, not LogQL) and on the missing Logs Drilldown app; A2 gains the app but loses on maturity and adds a component; B wins the UI/portability columns and loses almost everything else.

**Recommendation: A1.** It resolves the actual complaint — a thin exploration pane — with an official, reversible, resource-bounded addition and **no change to the log pipeline**. A2 is the documented fallback if the plugin's drawer is judged insufficient; B is not justified by the requirement.

---

## §7 — Rollout and rollback

**A1 (recommended)** — the parent moves first; Grafana follows:

1. On `pve`, resize/rename LXC 214 to `monitor`: **4 GiB / 32 GiB**; lower VictoriaLogs to a **1.5 GiB** cap by setting `victorialogs_memory_allowed_percent: 37` (or `-memory.allowedBytes=1536MiB`) — the current 60% would allow ~2.4 GiB. Gate the 32 GiB resize on the measured disk budget.
2. **Netdata Parent first:** deploy the container; copy `dbengine` and mint a new Parent GUID; stop the old Parent, convert `pve` to a child, re-point `lab`/`nas`/`edge` to `monitor:19996:SSL`; verify Proxmox names, streams, UPS and history. Keep the old Parent data until the new one is stable.
3. Add the Grafana Compose service, UFW `3000/tcp` from `edge` only, native TLS, `network_mode: host`; add the `grafana.internal` Caddy route on `edge`.
4. Create `grafana-admin-password` and `grafana-secret-key` in Key Vault; write **root:472, mode 0440** files; wire `__FILE` variables.
5. Provision the datasource (`victoriametrics-logs-datasource` → `https://127.0.0.1:9428`, basic auth `vlogs`) and the dashboards from the repo.
6. Verify: `https://grafana.internal` answers through Caddy, datasource "Save & test" passes, Explore returns journald records, histogram and live tail work, the Drilldown drawer opens, a non-edge source is refused on `:3000`, and the 4 GiB guest stays within its caps.
7. Rollback: Grafana is `docker compose down` + remove its Caddy site/UFW rule; the Parent move is reverted by stopping the container, restoring `pve` as Parent and re-pointing the children. The old dbengine stays available; VictoriaLogs and Fluent Bit are untouched.

**A2** — same Grafana base, plus the proxy container and a Loki datasource; keep it out of the primary path until the proxy's known issues close. Rollback removes the proxy and the Loki datasource.

**B** — not planned here; it would need its own ADR superseding [ADR 35](../decisions/35-log-store-victorialogs.md), an amendment to [ADR 36](../decisions/36-log-collector-fluentbit.md), an auth-proxy decision, and a migration/rollback plan. A destructive cutover is never the first step.

---

## §8 — Claims to verify before build

| Claim | Why it matters |
|---|---|
| **`pve` free RAM and `local-lvm`** — 4 GiB guest / 32 GiB disk beside the CA guest | The collocation and disk recommendation rests on it |
| **Grafana idle RSS** for the pinned image (512 MB is a documented floor, not a measurement) | Confirms the 0.75 GiB cap; a spike during dashboard renders is the risk |
| **Netdata Parent RSS** at the fleet's retention and 5–15 children | Measured ~500 MB today; confirms the 1.0 GiB cap and 4 GiB total |
| **Netdata Docker collection** — cgroup namespace host + read-only cgroup mount + GET-only socket proxy | Decides whether the Parent sees VictoriaLogs/Grafana/Netdata container charts without mounting the raw Docker socket |
| **Parent history migration** — `dbengine` copy + new Parent GUID | Preserves child history without colliding with `pve`'s child identity |
| **Current VictoriaLogs data size** and daily ingest rate — **pre-resize gate** | Confirms 32 GiB from the real budget, or forces a lower store cap/separate volume before the resize |
| **Plugin/Grafana version pair** — latest Grafana release compatible with `victoriametrics-logs-datasource@0.33.1` | Both are pinned; a mismatch is a failed datasource |
| **`GF_PLUGINS_PREINSTALL` egress** from `monitor` to grafana.com | The plugin installs at container start |
| **Grafana `__FILE` secrets and native-TLS env names** on the pinned image | Confirmed in current docs, but the image version must be checked. Verify the files are `root:472`, mode `0440`, and readable by the container's UID/GID 472 |
| **Datasource provisioning with `$ENV` password and `tlsSkipVerify`** | Avoids a plaintext secret in the provisioning file; the self-signed store needs either skip-verify or the CA |
| **Caddy route and backend TLS** — `grafana.internal` via the `*.internal` wildcard → `edge` → `https://192.168.2.214:3000` | ADR 40 remains the single proxy; no static A record. The current Caddy role exposes only `tls_skip_verify` for the backend; verified `step-ca` TLS needs a role extension and is a follow-up |
| **Step-ca leaf issuance for Grafana and client trust** — root distribution is complete ([#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144), [PR #157](https://github.com/jaroslaw-bagnicki/Homelab/pull/157)) | Root distribution is no longer a gate; only Grafana's leaf and client trust remain |
| **Loki has no syslog listener** | Inferred from the HTTP API's ingest endpoints (`/loki/api/v1/push`, `/otlp/v1/logs`); confirm before treating B's syslog gap as real |
| **A2 proxy** — release cadence, issue closure, and whether its `drilldown-limits` covers Grafana's current Drilldown version | It is the only literal-Loki-UI path without Loki |

---

## §9 — Conclusions

1. **The store is not the problem.** VictoriaLogs is meeting its contract; replacing it to improve the pane would trade a working, cardinality-safe, disk-capped engine for a heavier, label-constrained one and a rewrite of every collector.
2. **A1 is the right pane.** The official plugin delivers the Grafana experience — Explore, histogram, live tail, levels, patterns, dashboards, alerting, correlations and a Drilldown drawer — over the existing store with no pipeline change. It lands **after** the Netdata Parent move.
3. **The literal Loki UI is available without Loki only through A2**, the community LogQL→LogsQL proxy. It is real and purpose-built for Logs Drilldown, but at v0.1.0 with a partial translator and known defects it is a **watch item**, not the fleet's log pane.
4. **B is rejected for now.** It buys Logs Drilldown and LogQL but costs the store decision, the collector contract, the router's syslog path, an auth proxy, the disk safety valve and scarce `pve` memory.
5. **Grafana is an amendment, not a reversal.** [ADR 35](../decisions/35-log-store-victorialogs.md)'s "Grafana is not a prerequisite" remains true — the store works without it — but the pane is now Grafana, and `vmui` stays as break-glass.
6. **The Netdata Parent is part of the decision and moves first.** It goes into `monitor` before Grafana; `pve`/`pve2` keep the Proxmox view as host-native children. The measured ~500 MB makes the 4 GiB guest sufficient.

## References

- [ADR 46 — Observability host: VictoriaLogs, Netdata Parent and Grafana in one LXC](../decisions/46-grafana-logs-ui-victorialogs.md) — **the decision this analysis proposes**
- [ADR 35 — VictoriaLogs log store](../decisions/35-log-store-victorialogs.md) · [ADR 36 — Fluent Bit collector](../decisions/36-log-collector-fluentbit.md) · [ADR 34 — TLS-only LAN](../decisions/34-lan-tls-only.md) · [ADR 27 — monitoring strategy](../decisions/27-monitoring-strategy.md) · [ADR 40 — DNS and edge proxy](../decisions/40-internal-dns-proxy-edge.md) · [ADR 44 — Authentik](../decisions/44-authentik-identity-provider.md)
- [Research 33 — VictoriaLogs store and host](33-centralized-logging-victorialogs.md) · [research 34 — collector options](34-log-collector-options.md) · [research 50 — Netdata Cloud costs, stream identity and Parent migration](50-netdata-cloud-costs-and-stream-identity.md) · [runbook 33 — deploy VictoriaLogs](../runbooks/33-deploy-victorialogs.md)
- [Idea 15 — a second Proxmox node (`pve2`)](../ideas/15-second-proxmox-node.md) — the later move that expands `monitor` from 32 GiB to 64 GiB
- Upstream: [VictoriaLogs Grafana integration](https://docs.victoriametrics.com/victorialogs/integrations/grafana/) · [plugin catalog](https://grafana.com/grafana/plugins/victoriametrics-logs-datasource/) · [Grafana Docker](https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/) · [Grafana sizing](https://grafana.com/docs/grafana/latest/setup-grafana/installation/) · [Grafana Logs Drilldown](https://grafana.com/docs/grafana/latest/explore/simplified-exploration/logs/) · [Loki deployment modes](https://grafana.com/docs/loki/latest/get-started/deployment-modes/) · [Loki filesystem storage](https://grafana.com/docs/loki/latest/operations/storage/filesystem/) · [Loki retention](https://grafana.com/docs/loki/latest/operations/storage/retention/) · [Loki authentication](https://grafana.com/docs/loki/latest/operations/authentication/) · [Loki HTTP API](https://grafana.com/docs/loki/latest/reference/loki-http-api/) · [Fluent Bit Loki output](https://docs.fluentbit.io/manual/pipeline/outputs/loki)
- [Netcracker/qubership-logql-to-logsql-proxy](https://github.com/Netcracker/qubership-logql-to-logsql-proxy) — the A2 proxy
