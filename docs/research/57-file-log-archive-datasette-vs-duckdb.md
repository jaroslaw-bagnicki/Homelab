# 57 — File-Based Long-Retention Log Archive — Datasette vs DuckDB UI on `lab`

**Sources**: official documentation and upstream issues read 2026‑11‑15 —

- [VictoriaLogs issue #226 — "different retention for different streams"](https://github.com/VictoriaMetrics/VictoriaLogs/issues/226) — upstream: **"one retention per instance, in both editions"**; recommended pattern for mixed retention is **separate instances per data class** · [VictoriaLogs storage & retention](https://github.com/victoriametrics/victorialogs/blob/master/docs/victorialogs/README.md) — per-day partitions under `<storageDataPath>/partitions/YYYYMMDD`; `-retentionPeriod`, `-retention.maxDiskUsagePercent`, `-storage.minFreeDiskSpaceBytes` all drop **whole partitions**, never per-stream
- [Datasette — installing using Docker](https://docs.datasette.io/en/stable/installation.html#installation-docker) — image `datasetteproject/datasette`, port **8001**, `-h 0.0.0.0`, `--immutable` for read-only DBs · [sqlite-utils — inserting newline-delimited JSON](https://sqlite-utils.datasette.io/en/stable/cli.html#inserting-new-data) (`sqlite-utils insert db.db tbl file.jsonl --nl`) · [Datasette JSON API](https://docs.datasette.io/en/stable/json_api.html) · [Datasette authentication](https://docs.datasette.io/en/stable/authentication.html) — no built-in basic auth; auth is via plugins or a front proxy
- [DuckDB UI extension](https://duckdb.org/docs/1.5/core_extensions/ui) — `duckdb -ui` or `CALL start_ui()`, default port **4213**; headless in a container: `SET ui_remote_host='0.0.0.0'; INSTALL ui; LOAD ui; CALL start_ui_server();` — **the UI has no authentication of its own** · [DuckDB `read_json_auto`](https://duckdb.org/docs/data/json/overview) — query JSONL files in place · [DuckDB sqlite extension](https://duckdb.org/docs/extensions/sqlite) — `ATTACH … (TYPE sqlite)` reads SQLite files · official image `duckdb/duckdb:<tag>`
- Repo: [ADR 35](../decisions/35-log-store-victorialogs.md) (30-day retention + disk caps, "not backed up", per-day partitions) · [ADR 36](../decisions/36-log-collector-fluentbit.md) (the jsonline output contract a shipper reuses) · [ADR 27](../decisions/27-monitoring-strategy.md) (every Tier B component gets its own ADR) · [ADR 34](../decisions/34-lan-tls-only.md) · [ADR 40](../decisions/40-internal-dns-proxy-edge.md) (edge Caddy + Technitium are the LAN entry) · [ADR 49](../decisions/49-backup-3-2-1-strategy.md) · [ADR 50](../decisions/50-backblaze-b2-offsite-backup.md) · [research 33](33-centralized-logging-victorialogs.md) · [research 49](49-grafana-logs-ui-victorialogs-vs-loki.md) · [`ansible.cfg`](../../ansible.cfg) (`log_path = ansible/ansible.log`) · [`.devcontainer/scripts/setup-opencode-persist.ps1`](../../.devcontainer/scripts/setup-opencode-persist.ps1) (OpenCode sessions persisted as files + an `opencode.db` SQLite under `/workspaces/.opencode`) · [`docs/hardware.md`](../hardware.md) (`lab`: M910q, i5-7500T, 16 GB DDR4, 256 GB NVMe)

**Scope**: pick a **file-based store plus a lightweight browsing front** for the streams that need long or effectively unbounded retention — Ansible run logs (above all the [runbook 41](../runbooks/41-deploy-freeipa-server.md) FreeIPA executions, which the runbook itself records as the audit trail) and OpenCode agent logs — hosted as a container on `lab`. The fleet store decision ([ADR 35](../decisions/35-log-store-victorialogs.md)) is **not** reopened: VictoriaLogs stays the 30-day hot store for the whole fleet. The two leading candidates are **Datasette** and **DuckDB UI**. A **second VictoriaLogs instance is rejected up front** — operator direction: the exercise is also to learn something new, and the per-instance-retention pattern is already analysed upstream in #226.

**Status**: 📝 Analysis — **proposed**. Per [ADR 27](../decisions/27-monitoring-strategy.md), whichever component is adopted gets its own ADR when this settles; this document keeps the analysis and the rejected paths.

> **Verification status.** Product behaviour, image names, ports and the auth gaps are sourced from the official docs above, but **nothing has been run yet** — the lab POC in §9 measures footprint and query latency. Repo facts are treated as established by reference.

---

## Decision summary

| Question | Recommendation | Status |
|---|---|---|
| Durable store format | **JSONL files as the source of truth + a SQLite DB for browsing** (Datasette path); DuckDB queries the same JSONL in place with zero ingest | **leaning** — §5 |
| Browsing front | **Datasette**, served `--immutable` — facets, JSON API, and it serves the existing `opencode.db` read-only as-is. The operator's durability lean is confirmed in §3. DuckDB UI stays as the ad-hoc analytics front over the same files | **leaning** — §3/§4 |
| Host | One compose service on **`lab`** (M910q — 16 GB RAM, 256 GB NVMe; ADR 35's documented fallback host), data under `/opt/logs` | **leaning** — §7 |
| Exposure | **No published port** — edge Caddy site `logs.internal` → `lab:8001` with Caddy basic auth, Technitium A record (ADR 34/40). Neither candidate has built-in auth, so the proxy is the boundary | **leaning** — §7 |
| Ingest | Post-run shipper in the DevContainer appends new `ansible.log` lines (saved byte offset) to `/opt/logs/ansible/YYYY-MM.jsonl` and batch-loads them into `archive.db` with `sqlite-utils`; OpenCode data is copied from `/workspaces/.opencode` | **leaning** — §7 |
| Retention | **Unbounded by policy** — monthly files on 256 GB; restic → B2 (ADR 49/50) for the off-box copy | **leaning** — §7 |
| Second VictoriaLogs instance | **Rejected** — operator direction (learn something new); per-instance retention already covered by #226 | **rejected** — §6 |
| Decision record | New ADR (a Tier B component, ADR 27) once the §9 POC passes | pending |

---

## §1 — Fixed context

**Why any of this exists.** VictoriaLogs on `vtstack` (LXC 214, `192.168.2.214:9428`) keeps **30 days** under `-retentionPeriod=30d`, hard-capped by `-retention.maxDiskUsagePercent=80` and `-storage.minFreeDiskSpaceBytes=2GiB` on a 16 GiB volume ([ADR 35](../decisions/35-log-store-victorialogs.md) · [role defaults](../../ansible/workloads/victorialogs/victorialogs_store/defaults/main.yml)). Retention deletes **whole per-day partitions**, and upstream confirms **one retention per instance in both editions** — per-stream retention is open request [#226](https://github.com/VictoriaMetrics/VictoriaLogs/issues/226). So "keep *this* stream forever inside the current store" is impossible by construction, and raising the global retention would only inflate every stream's disk use on the shared 128 GB SSD and still hit the 80 % cap — with read-only-mode as the failure mode ADR 35 sized the caps to avoid.

**Why the DevContainer is a special source.** Ansible already logs every run to `ansible/ansible.log` (`log_path` in [`ansible.cfg`](../../ansible.cfg), git-ignored). The DevContainer runs on the work laptop, which is only sometimes on `192.168.2.0/24` (the dock is DHCP/corporate — [`docs/overview.md`](../overview.md) topology), while the store's in-LXC UFW admits only the LAN. So the hot path (Fluent Bit → `/insert/jsonline`) works at home and silently can't off-LAN; a file-based archive needs a shipper that **queues locally and syncs opportunistically**, with the local file as the always-available fallback.

**Why `lab` is the host.** M910q: i5-7500T, **16 GB RAM, 256 GB NVMe** ([`docs/hardware.md`](../hardware.md)) — ADR 35 names the ADR 22 node as the fallback if the store outgrows `pve1`, and compose workloads on `lab` are the established pattern (`docker_services` in the base playbook, self-contained recipes under [`ansible/workloads/`](../../ansible/workloads/)). k3s (ADR 22) is the accepted destination but not yet the substrate; the recipe ships as compose now and migrates with the rest later.

**Entry pattern.** TLS-only LAN (ADR 34) and edge-owned DNS/proxy (ADR 40): the front is exposed as a Caddy site on `edge` (`logs.internal`) with a Technitium A record pointing at `edge`, proxying to the `lab` container — never a raw published port.

---

## §2 — Requirements

1. **Long/unbounded retention** for the named streams (Ansible run logs, OpenCode agent logs) — the fleet-wide 30-day window stays in VictoriaLogs for everything else.
2. **Easy browsing** over HTTPS from a laptop browser, plus search/filter.
3. **Effective for AI-agent digests** — aggregation queries (tokens per session, failed tool calls, model mix, per-run timelines) and direct readability by an agent's own file tools.
4. **Lightweight** — must sit comfortably on `lab` beside existing workloads; single-digit-Watts-class footprint, one or two containers.
5. **LAN-only, TLS, authenticated** — Caddy terminates TLS and basic auth on `edge`; the container itself is not directly exposed.
6. **Backed up** — the archive rides the existing restic → B2 path (ADR 49/50); logs are currently excluded from backup by ADR 35, so this archive is the deliberate exception, recorded in the future ADR.
7. **Learning value** — operator explicitly wants a new component, not another VictoriaLogs instance.

---

## §3 — Candidate A: Datasette (the operator's lean — confirmed)

- **Storage: SQLite, one file per archive** (`/opt/logs/archive.db`). SQLite is a single ACID file with WAL, decades of durability provenance, and a mature tooling ecosystem — `sqlite-utils insert archive.db ansible /opt/logs/ansible/2026-11.jsonl --nl` turns appended JSONL into a queryable table in one command. Durability argument: the format is boring, standard, and readable by anything (CLI, Python, DuckDB's sqlite extension, forensic tools). This is why the operator's "more durable" lean is right — **the DB file is the archive**, not a cache in front of one.
- **Serving: read-only by default.** `datasette serve /opt/logs/archive.db --immutable -p 8001 -h 0.0.0.0` — `--immutable` skips all write locking and is the documented mode for never-changing files; for the append-growing `archive.db`, rebuild-and-swap atomically (`sqlite-utils` into `archive.new.db`, then `mv`) or serve non-immutable. Read-only serving is exactly the right posture for logs.
- **Browsing UX: mature.** Table/row views, **facets** (faceted search by field out of the box), arbitrary SQL in the UI, and a full **JSON API** (`/archive/ansible.json?_size=100&…`) — which is also the clean ingest-agnostic query endpoint for scripts and agents.
- **OpenCode logs need no conversion at all.** OpenCode already stores sessions in an SQLite `opencode.db` (persisted to `/workspaces/.opencode` by [`setup-opencode-persist.ps1`](../../.devcontainer/scripts/setup-opencode-persist.ps1)); a read-only copy is served by the same Datasette instance with `--immutable` — one front for both archives.
- **Container**: `datasetteproject/datasette:<tag>`, port 8001, volume-mounted `/opt/logs`. **No built-in basic auth** → Caddy basic auth in front (ADR 34/40 pattern). Footprint ~50–100 MB — to be measured in §9.
- **Plugins** install via pip into the image (`docker run datasetteproject/datasette pip install datasette-…`), e.g. charting; not required for v1.

## §4 — Candidate B: DuckDB UI

- **Storage: the JSONL files themselves.** DuckDB queries them in place — `SELECT * FROM read_json_auto('/opt/logs/ansible/*.jsonl')` — so **ingest is zero**: the shipper only appends files. (An optional `.duckdb` file can hold indexes/views; it is a derived cache, not the source of truth.)
- **Browsing UX: newer, chart-friendly.** The UI extension (port 4213; in a container `duckdb/duckdb:<tag>` with `SET ui_remote_host='0.0.0.0'; INSTALL ui; LOAD ui; CALL start_ui_server();`, `-p 4213:4213`) gives a notebook-style SQL UI with charts — good for ad-hoc analysis, less polished for pure log browsing than Datasette's facets. **The UI has no authentication of its own** — it must sit behind the Caddy auth proxy, same as Datasette.
- **Columnar engine** — much faster than row-wise SQLite for large analytical scans (tens of GB of JSONL on the i5 are fine); weaker for point lookups, irrelevant at log-browsing scale.
- **OpenCode logs**: DuckDB's `sqlite` extension can `ATTACH '/opt/logs/opencode.db' (TYPE sqlite)` read-only, or the export can be JSONL like everything else — both work.
- **Durability**: the durable artefact is still the plain JSONL/SQLite *file*; DuckDB adds a younger single-file engine on top when you want one. Nothing is lost by choosing files as the canonical store — which is why both candidates are "file-based" and the difference is only the front.
- Footprint ~100–200 MB — to be measured in §9.

## §5 — Head-to-head

| Dimension | Datasette | DuckDB UI |
|---|---|---|
| Durable artefact | SQLite file (ACID, WAL, universal tooling) | JSONL files (themselves); optional `.duckdb` cache |
| Ingest work | Append JSONL + periodic `sqlite-utils` load (or serve files' DB directly) | None — append files only |
| Browse UX | Facets, row/table views, saved SQL, JSON API | SQL notebook + charts; newer UI |
| Analytical power | Good at browse scale; row-store scans slow past ~10 GB | Excellent — columnar scans of tens of GB on the i5 |
| Auth | None built-in → Caddy basic auth | None built-in → Caddy basic auth |
| Footprint (to measure) | ~50–100 MB | ~100–200 MB |
| Serves `opencode.db` directly | **Yes — `--immutable`, zero conversion** | Via sqlite extension (read-only attach) |
| Backup | restic on `/opt/logs` — one dir, trivially consistent with a checkpointed/wal-checkpointed DB | restic on the same dir |
| Agent digest | JSON API + agents can read the `.db`/JSONL with their own tools | Agents read JSONL directly; SQL via CLI |
| Maturity / learning value | Mature, stable, plugin ecosystem | Newer, actively shipped, MotherDuck-backed UI |

**Verdict:** they are complementary, not rival — the shared substrate is **files under `/opt/logs`**. Datasette wins as the *browsing front* (facets, immutable read-only serving, serves `opencode.db` with zero conversion, single durable SQLite file); DuckDB UI wins as the *analytics* front over the same files. Recommendation: **ship Datasette as the front, keep DuckDB UI as the ad-hoc query option** — the POC in §9 confirms with measurements.

## §6 — Rejected alternatives

- **Second VictoriaLogs instance with huge retention** — rejected by operator direction (the point is to learn something new); also already analysed: one retention per instance ([#226](https://github.com/VictoriaMetrics/VictoriaLogs/issues/226)), and an index store is disk-capped by design, so "infinite" would still be a lie.
- **Loki + Grafana on `lab`** — the only mainstream store with *native per-stream retention* (`retention_stream` compactor config), but it reverses [ADR 35](../decisions/35-log-store-victorialogs.md), adds a chunk store and a new UI stack, and ADR 27 would still require its own ADR. Revisit only if per-stream retention inside one indexed store becomes a hard requirement.
- **ZincSearch** — single binary with web UI and no default TTL; another search index to operate, same disk-capped ceiling; adds no browsing advantage over Datasette at this volume.
- **Dozzle** — browses Docker container logs only; the Ansible/OpenCode sources are files, not containers.
- **GoAccess** — static HTML reports from files; no live browsing, no SQL.
- **`lnav`** — excellent CLI log browser with built-in SQL over SSH, but no web UI; keep as the operator's on-box tool alongside, not instead of, the front.
- **Plain files + `rg`** — zero infra, but no browsing front and no structured digest; it is the fallback inside the shipper (local file always exists).

## §7 — Recommended shape

```
DevContainer (work laptop)                lab (192.168.2.200)                    edge (192.168.2.240)
ansible/ansible.log ──shipper──► /opt/logs/ansible/YYYY-MM.jsonl ──► archive.db ──► Datasette :8001 ◄── Caddy logs.internal (TLS + basic auth) ◄── Technitium logs.internal
        │  (saved offset, queues        (sqlite-utils batch load,        (--immutable)            (no published port)
        │   off-LAN, syncs on LAN)       atomic swap)                     │
        └─ also POSTs to VictoriaLogs     restic ──► Backblaze B2          └─ opencode.db copy served read-only
           /insert/jsonline (30-day hot   (ADR 49/50)
           path, when on LAN)
```

- Compose project under `/opt/logs-archive/` on `lab`, pinned image tags, `restart: unless-stopped`, data on the 256 GB NVMe.
- Caddy site on `edge`: `logs.internal` → `http://192.168.2.200:8001`, basic auth (credentials from `homelab-bysxdb-kv`, same pattern as the VictoriaLogs password), `tls_skip_verify` on the hop until the Caddy role grows backend-CA support (the gap already recorded in [research 49](49-grafana-logs-ui-victorialogs-vs-loki.md) §2).
- Technitium A record `logs` → `192.168.2.240` (edge), per ADR 40.
- Shipper: a small script in the DevContainer that tracks a byte offset into `ansible/ansible.log`, emits new lines as JSONL, and rsyncs/HTTP-POSTs them to `lab` when reachable (queues in the container otherwise; the local `ansible.log` is the fallback copy).

## §8 — Will it serve an AI-agent log digest?

**Yes — better than an index store at this scale.** OpenCode's data is already file-native (SQLite `opencode.db` + JSON, persisted by `setup-opencode-persist.ps1`), so there is no format conversion tax. A "digest" is aggregation — `SELECT session, sum(tokens), count(*) FILTER (tool_call failed) … GROUP BY …` — which is exactly what both candidates do well over structured JSON, and what LogsQL full-text search does poorly. An agent can also read `/opt/logs/**/*.jsonl` directly with its own file tools — no API hop, no auth dance — or query Datasette's JSON API. Expected volume (single operator, MBs per day) keeps every query instant on the i5; tens of GB remain comfortable for DuckDB, and Datasette stays fine while queries stay field-filtered. The point where an indexed store would earn its keep — GBs per day of mixed fleet logs — is precisely the volume that stays in VictoriaLogs. Caveat that applies regardless of store: agent prompts and tool output can embed secrets, so the front stays LAN-only behind Caddy basic auth, and `no_log`-style redaction is the shipper's job, not the store's.

## §9 — POC plan and open questions

1. Pin `datasetteproject/datasette` and `duckdb/duckdb` tags; one compose project on `lab`; measure idle RAM of each.
2. Generate ~1 GB synthetic JSONL in `/opt/logs/ansible/`; benchmark: Datasette faceted query vs DuckDB `read_json_auto` scan (the i5's NVMe makes both fast; record numbers).
3. Decide the `archive.db` refresh cadence: nightly `sqlite-utils` into `archive.new.db` + atomic `mv` (served non-immutable) vs serving the raw files only and skipping the DB — measure both.
4. Confirm Caddy basic-auth + `logs.internal` wiring end-to-end; verify no published port is reachable off-LAN.
5. Copy `opencode.db` read-only into `/opt/logs/` and confirm Datasette `--immutable` serves sessions/messages/parts; check DuckDB `sqlite` attach as the alternative.
6. Wire restic → B2 for `/opt/logs` (ADR 49/50) and record the ADR 35 "logs are not backed up" amendment for this one archive in the future ADR.

---

## References

- [ADR 27](../decisions/27-monitoring-strategy.md) — Tier B components adopted via their own ADRs
- [ADR 34](../decisions/34-lan-tls-only.md) · [ADR 40](../decisions/40-internal-dns-proxy-edge.md) — TLS-only LAN; edge Caddy + Technitium
- [ADR 35](../decisions/35-log-store-victorialogs.md) · [ADR 36](../decisions/36-log-collector-fluentbit.md) — the 30-day store and its ingest contract · [research 33](33-centralized-logging-victorialogs.md) · [research 34](34-log-collector-options.md)
- [ADR 49](../decisions/49-backup-3-2-1-strategy.md) · [ADR 50](../decisions/50-backblaze-b2-offsite-backup.md) — restic → B2
- [ADR 22](../decisions/22-k3s-arc-homelab.md) — k3s is the destination; compose on `lab` is the live substrate
- [Runbook 41](../runbooks/41-deploy-freeipa-server.md) — the Ansible run logs this archive is for
- [VictoriaLogs #226](https://github.com/VictoriaMetrics/VictoriaLogs/issues/226) — per-stream retention request; per-instance pattern
- [Datasette docs](https://docs.datasette.io/en/stable/) · [sqlite-utils](https://sqlite-utils.datasette.io/en/stable/) · [DuckDB UI extension](https://duckdb.org/docs/1.5/core_extensions/ui) · [DuckDB JSON](https://duckdb.org/docs/data/json/overview) · [DuckDB sqlite extension](https://duckdb.org/docs/extensions/sqlite)
- [`ansible.cfg`](../../ansible.cfg) · [`.devcontainer/scripts/setup-opencode-persist.ps1`](../../.devcontainer/scripts/setup-opencode-persist.ps1) · [`docs/hardware.md`](../hardware.md) · [`ansible/workloads/`](../../ansible/workloads/)
