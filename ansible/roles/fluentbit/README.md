# fluentbit

Installs the **Fluent Bit** log collector fleet-wide and ships each node's logs to
**VictoriaLogs**. One systemd service per node; source shapes and buffering are data, not code.
Decision: [ADR 36](../../../docs/decisions/36-log-collector-fluentbit.md); deployed by
[runbook 34](../../../docs/runbooks/34-deploy-fluentbit.md); tracked in
[issue #84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84).

## Files

- `defaults/main.yml` — role parameters (store contract, buffering, source toggles).
- `tasks/main.yml` — APT repo + install, Key Vault password fetch, runtime directory, config template, service.
- `handlers/main.yml` — restart `fluent-bit`.
- `templates/fluent-bit.conf.j2` — `[SERVICE]` plus one `[INPUT]`/`[OUTPUT]` pair per source shape.
  Build each `URI` query string with an inline expression (`{{ '&debug=1' if ... else '' }}`), **never** a
  `{% if %}` block tag: Ansible's `trim_blocks` strips the newline after `{% endif %}`, gluing the next
  line (`Format json_lines`) onto the URI. Fluent Bit then sends a malformed request line, which
  VictoriaLogs rejects with a bare `400 Bad Request` before its handler runs — the store logs nothing,
  so it looks healthy while ingesting zero bytes.
- `files/homelab-parsers.conf` — the `docker_path` regex parser that derives `container_id` from the Docker log path.
- `files/priority-level.lua` — the `map_level` Lua function that turns journald's numeric `PRIORITY` into
  the readable `level` field VictoriaLogs displays and filters on.

## Source shapes

The role renders three shapes, each with its own `[OUTPUT]` because a single
`_msg_field`/`_time_field` pair cannot serve two schemas (ADR 36):

| Shape | Input | `_msg_field` | Stream fields | Enabled by |
|---|---|---|---|---|
| journald | `systemd` (whole journal) | `MESSAGE` | `_HOSTNAME`, `_SYSTEMD_UNIT` | `fluentbit_collect_journald` (default) |
| Docker json-file | `tail` + `docker` parser + `Docker_Mode`, container id from the path | `log` | `hostname`, `container_id` | `fluentbit_collect_docker` |
| Native files | `tail` (raw line) | `log` | `hostname` | `fluentbit_file_paths` |

Every output writes to the store's JSON-lines API over TLS with basic auth, gzip, and the
Fluent Bit event time rendered ISO8601 as `_time_field date`. The password is fetched from
Key Vault at run time and never stored in the repo.

journald's numeric `PRIORITY` is mapped to a readable `level` by the `map_level` Lua filter
(`0` to `7` → `emerg`, `alert`, `crit`, `error`, `warn`, `notice`, `info`, `debug`), because the store only
derives `level` from `PRIORITY` on its journald ingest endpoint, which this build does not serve, and it has
no `level_field` ingest arg. `level` is a regular field — it changes per line, so it is never part of
`_stream_fields`. Records with no `PRIORITY` get no `level` rather than an invented one.

## Buffering

Buffering is a **per-input** setting (`Storage.Type`), bounded per node:

- **Default — filesystem**: chunks are stored on disk, so they survive a store outage; the cursor
  lives under `fluentbit_runtime_dir` (`/var/lib/fluent-bit`) and the output queue is capped by
  `storage.total_limit_size`.
- **eMMC nodes (`edge`) — `memrb`**: a bounded memory ring buffer that **drops the oldest chunks**
  (never writing to disk) plus a `mem_buf_limit`, with the cursor on `/run` recreated by a
  `tmpfiles.d` entry — so an unreachable store never writes to the eMMC
  ([ADR 24](../../../docs/decisions/24-edge-ingress-appliance.md)).

## Parameters

| Var | Default | Notes |
|---|---|---|
| `fluentbit_collect_journald` | `true` | Read the whole journal — no inclusion list ([ADR 36](../../../docs/decisions/36-log-collector-fluentbit.md)). |
| `fluentbit_read_from_tail` | `true` | Start from now on first run rather than replaying the journal backlog. |
| `fluentbit_journald_max_entries` | `5000` | Bounds a startup burst from the journal. |
| `fluentbit_collect_docker` | `false` | Tail Docker's `json-file` logs; set on Docker hosts. |
| `fluentbit_file_paths` | `[]` | Extra native log paths, one `tail` source each. |
| `fluentbit_store_host` / `fluentbit_store_port` | `192.168.2.214` / `9428` | VictoriaLogs on the `vtstack` guest ([ADR 35](../../../docs/decisions/35-log-store-victorialogs.md)). |
| `fluentbit_store_uri` | `/insert/jsonline` | The store's JSON-lines ingest path. |
| `fluentbit_store_username` | `vlogs` | Basic-auth user; the password is a secret. |
| `fluentbit_store_password_secret_name` | `victorialogs-basic-auth-password` | Key Vault secret name. |
| `fluentbit_store_debug` | `false` | Appends `debug=1` so the store logs how it parsed each record. |
| `fluentbit_buffer_type` | `filesystem` | Per-input storage: `filesystem`, `memory` or `memrb`; `memrb` on `edge`. |
| `fluentbit_buffer_limit` | `256M` | Filesystem output queue cap, or the input `mem_buf_limit` on memory nodes. |
| `fluentbit_cursor_tmpfs` | `false` | Cursor on `/run` instead of `/var/lib/fluent-bit`. |

## Secrets

The collector authenticates to VictoriaLogs with the **same** basic-auth password the store
uses — `homelab-bysxdb-kv/victorialogs-basic-auth-password`, provisioned by
`scripts/New-HomelabVictoriaLogsPassword.ps1` and fetched at run time via
`azure.azcollection.azure_keyvault_secret` (`delegate_to: localhost`, `no_log`). The controller
needs `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` / `AZURE_TENANT_ID`. Rotation = re-run the store
script with `-Force`, then re-run the playbooks.

## Idempotency

- The APT key, repository and package are guarded by the package manager.
- The runtime directory is created once; on tmpfs nodes a `tmpfiles.d` entry recreates it at boot.
- The config template writes only on change and notifies a `fluent-bit` restart.
- A converged node re-runs with `changed=0`.

## Hosts

Applied by `playbook-pve.yml`, `playbook-edge.yml`, `playbook-lab.yml`, `playbook-nas.yml` and
`playbook-logs.yml` (`vtstack`). `cloudlab` is never targeted — off-LAN, and Tier A already covers
it ([ADR 27](../../../docs/decisions/27-monitoring-strategy.md)). The OPNsense router is out of scope
(FreeBSD, no journald — [research 34 §8](../../../docs/research/34-log-collector-options.md)).

Deploy order: `pve` → `edge` → `lab` → `nas` → `vtstack`, validating each before the next
([runbook 34](../../../docs/runbooks/34-deploy-fluentbit.md)).

## References

- [ADR 24](../../../docs/decisions/24-edge-ingress-appliance.md) — Edge appliance (volatile journald, eMMC, no Docker)
- [ADR 27](../../../docs/decisions/27-monitoring-strategy.md) — Tier B strategy
- [ADR 34](../../../docs/decisions/34-lan-tls-only.md) — LAN services are TLS-only
- [ADR 35](../../../docs/decisions/35-log-store-victorialogs.md) — the log store
- [ADR 36](../../../docs/decisions/36-log-collector-fluentbit.md) — this collector
- [Research 34](../../../docs/research/34-log-collector-options.md) — collector comparison, source shapes, buffering
