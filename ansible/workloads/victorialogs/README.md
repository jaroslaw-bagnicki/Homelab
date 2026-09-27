# VictoriaLogs workload

## Purpose

A self-contained Ansible recipe that deploys the Tier B **log store** — **VictoriaLogs** — as a
Docker Compose service on the `vtstack` guest (LXC 214, `192.168.2.214`) on the `pve` node. Per
[issue #123](https://github.com/jaroslaw-bagnicki/Homelab/issues/123), the store is the dependency the
collector ([#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84)) and every node's log path
wait on; the decision is [ADR 35](../../../docs/decisions/35-log-store-victorialogs.md).

`vtstack` is framed as the **Victoria stack** host: this workload deploys the first service
(`victorialogs`). VictoriaMetrics and VictoriaTraces are **future workloads/ADRs** on the same host —
see [research 33 §4](../../../docs/research/33-centralized-logging-victorialogs.md).

## Capabilities

The store is:

- A single `victorialogs` container (`victoriametrics/victoria-logs`, tag-pinned) listening on
  **`:9428`** — `docker run`-simple, no chunk store, no external dependencies.
- **HTTPS only** — native TLS (`-tls`, `-tlsCertFile`, `-tlsKeyFile`) with a self-signed certificate
  generated on the host. Plaintext HTTP is prohibited on the LAN ([ADR 34](../../../docs/decisions/34-lan-tls-only.md)).
- **Authenticated from day one** — HTTP basic auth (`-httpAuth.username` / `-httpAuth.password`); the
  password is fetched from Azure Key Vault `homelab-bysxdb-kv` at playbook runtime and written to a
  **root-only `file://` password file** (`-httpAuth.password=file://…`), so it never appears in the
  container's argument list or environment. No credential is committed.
- **Retention-bounded** — `-retentionPeriod=30d` **plus** `-retention.maxDiskUsagePercent` and
  `-storage.minFreeDiskSpaceBytes`, so a full disk cannot put the store into read-only mode.
- **Memory-bounded** — `-memory.allowedPercent` inside the LXC's ceiling, so its caches cannot
  starve the neighbouring smart-home services on the 8 GB node.
- **LAN-only** — enforced by the host's UFW (the `security` base role, `9428` from `192.168.2.0/24`),
  not the host's Proxmox UFW, which never sees container traffic ([ADR 34](../../../docs/decisions/34-lan-tls-only.md)).
- **Not backed up** — a rolling 30-day window stays outside [ADR 02](../../../docs/decisions/02-backup-strategy-restic-blob.md)'s scope.
- Idempotent — a re-run with no template/image/KV change reports `changed=0`.

## Services

| Service | Image | Port binding | Owned by |
|---|---|---|---|
| `victorialogs` | `victoriametrics/victoria-logs:v1.52.0` | `9428:9428` | `victorialogs_store` role |

## Host on-disk layout

```
/opt/vtstack/victorialogs/            # store root (templated by victorialogs_store)
├── docker-compose.yml
├── password                          # file:// basic-auth password (mode 0600, from AKV)
├── ssl/
│   ├── cert.pem                      # self-signed certificate
│   └── key.pem                       # mode 0600
└── data/                             # VictoriaLogs data (-storageDataPath)
```

Container paths: data at `/victoria-logs-data`; cert at `/etc/victorialogs/ssl/{cert,key}.pem`;
password at `/etc/victorialogs/password` (read-only).

## Endpoints

| Path | Purpose |
|---|---|
| `/select/vmui` | built-in LogsQL web UI (Grafana is optional) |
| `/select/logsql/query` | LogsQL query API |
| `/insert/elasticsearch/_bulk` | Elasticsearch-compatible bulk ingest (Fluent Bit `es` output — [#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84)) |
| `/insert/jsonline` | JSON-lines ingest |
| `/insert/loki/api/v1/push` | Loki push API |
| `/insert/opentelemetry/v1/logs` | OTLP logs |
| `/metrics` | VictoriaLogs' own metrics (protected by `-httpAuth.*`; the [#132](https://github.com/jaroslaw-bagnicki/Homelab/issues/132) monitoring job is future work) |

## Secrets

One secret must exist in the vault declared by `victorialogs_keyvault_name` (default
`homelab-bysxdb-kv`), provisioned by `scripts/New-HomelabVictoriaLogsPassword.ps1`:

- `victorialogs-basic-auth-password` — the HTTP basic-auth password (`victorialogs_password_secret_name`)

The role fetches it at runtime via `azure.azcollection.azure_keyvault_secret` and writes it to
`victorialogs_password_file` (mode `0600`). Rotation = run the script with `-Force`, then re-run the
playbook. The username is a role default (`victorialogs`), not a secret.

## Role Idempotency

`victorialogs_store` uses `community.docker.docker_compose_v2` with `state: present` and
`pull: always`. On the first run:

1. Directories (`victorialogs_dir`, `data/`, `ssl/`) are ensured.
2. The Key Vault password is written to the `file://` password file (`no_log`).
3. The self-signed certificate is generated (guarded by `creates:`).
4. `docker-compose.yml` is templated and the container is deployed.

Password/cert/template changes notify a `victorialogs` restart. Subsequent runs with no change
report `changed=0`.

## What's in this folder

- `victorialogs-playbook.yml` — playbook entrypoint (`hosts: vtstack`).
- `victorialogs_store/` — role: directories, KV password → `file://` file, self-signed cert, Compose
  template, container deploy.

## Invoke

    ansible-playbook ansible/workloads/victorialogs/victorialogs-playbook.yml

## Hosts

`vtstack` (LXC 214 on `pve`; base-provisioned by `ansible/playbooks/playbook-logs.yml` — see
[runbook 33](../../../docs/runbooks/33-deploy-victorialogs.md)). The guest is created and enrolled
per runbook 33 §1–§3.

## Roles run

1. `victorialogs_store` — deploys the store container and its TLS/auth/retention configuration.

## Vars consumed

- `victorialogs_dir`, `victorialogs_data_dir`, `victorialogs_ssl_dir`, `victorialogs_password_file`,
  `victorialogs_image`, `victorialogs_port`, `victorialogs_username`, `victorialogs_retention_period`,
  `victorialogs_max_disk_usage_percent`, `victorialogs_min_free_disk_space`,
  `victorialogs_memory_allowed_percent`, `victorialogs_tls_days`, `victorialogs_keyvault_name`,
  `victorialogs_password_secret_name` — role defaults.
- `victorialogs_password` — normally fetched from Key Vault; set it to skip the lookup in tests.

## Operational runbook

For LXC creation, enrollment, deployment, and the verification checklist, see
[`docs/runbooks/33-deploy-victorialogs.md`](../../../docs/runbooks/33-deploy-victorialogs.md).

## References

- [ADR 35 — Log Store — VictoriaLogs in an LXC on the pve Node](../../../docs/decisions/35-log-store-victorialogs.md)
- [Research 33 — Centralised Logging — VictoriaLogs Store and Its pve Host](../../../docs/research/33-centralized-logging-victorialogs.md)
- [VictoriaLogs documentation](https://docs.victoriametrics.com/victorialogs/) — flags, ingest endpoints, retention, security posture
