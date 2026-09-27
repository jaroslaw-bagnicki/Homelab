# Log Collector — Fluent Bit (fleet-wide into VictoriaLogs)

> Deploy the Tier B **log collector** — **Fluent Bit** as a systemd service on every LAN node,
> shipping journald (and Docker json-file) logs to **VictoriaLogs** on the `vtstack` guest — via the
> shared [`fluentbit`](../../ansible/roles/fluentbit/README.md) role. Decision:
> [ADR 36](../decisions/36-log-collector-fluentbit.md); analysis and source shapes:
> [research 34](../research/34-log-collector-options.md).
>
> ⚠ **Scope.** This is the **collector**; the store is [runbook 33](33-deploy-victorialogs.md)
> ([#123](https://github.com/jaroslaw-bagnicki/Homelab/issues/123)) and must be live first. The
> OPNsense router is out of scope ([research 34 §8](../research/34-log-collector-options.md)).
>
> ⚠ **Execution note.** Author on the `feat/fluentbit-role` branch; **run only after CR**. The LAN
> nodes are reached from a workstation on `192.168.2.0/24` with the fleet key loaded
> ([`fleet-connect` skill](../../.opencode/skills/fleet-connect/SKILL.md)). Roll out
> **`pve` → `edge` → `lab` → `nas` → `vtstack`**, validating each before the next.

## Why

VictoriaLogs is deployed and **inert** — nothing ships logs to it ([runbook 33](33-deploy-victorialogs.md)).
The **Edge's journald is volatile by design** ([ADR 24](../decisions/24-edge-ingress-appliance.md), eMMC
longevity), so its logs die with every reboot, and cross-node correlation (a NUT shutdown, a Caddy
restart, a Proxmox service failure) is impossible while each node's history stays local. Fluent Bit is
the collector chosen in [ADR 36](../decisions/36-log-collector-fluentbit.md).

## What changes

- **A shared `fluentbit` role** — one systemd service per node, the `netdata` pattern. The role owns
  the output contract, the field mapping, buffering and cursor placement; `host_vars` only toggles
  **which source shapes** the node has.
- **Sources:**
  - **journald — every node**, the whole journal (no inclusion list, no priority floor — ADR 36).
  - **Docker `json-file` logs** on `lab` and `vtstack` (`tail` + the built-in `docker` parser).
  - Native file paths (`fluentbit_file_paths`) are supported but **unset** in this rollout.
- **Output** — one block per source shape to `https://192.168.2.214:9428/insert/jsonline` with
  `_stream_fields` / `_msg_field` / `_time_field`, `Format json_lines`, ISO8601 event time, `tls On` +
  `tls.verify Off` (self-signed, [ADR 34](../decisions/34-lan-tls-only.md)), basic auth `vlogs` with
  the password from Key Vault, gzip.
- **Buffering** — **filesystem** on `pve`/`lab`/`nas` (chunks survive a store outage, cursor on disk);
  **`memrb`** (bounded memory ring buffer that drops the oldest chunks) on `edge` with a **tmpfs
  cursor**, so an unreachable store never writes to the eMMC.
- **Docker log rotation** — the `docker_host` role now writes `/etc/docker/daemon.json`
  (`log-driver: json-file`, `max-size: 10m`, `max-file: 3`) and restarts Docker. Research 34 §9's
  unbounded-rotation prerequisite.

## Prerequisites

- [ ] Store live and answering ([runbook 33](33-deploy-victorialogs.md)).
- [ ] Key Vault `homelab-bysxdb-kv/victorialogs-basic-auth-password` exists ([runbook 33 §4](33-deploy-victorialogs.md)).
- [ ] `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID` exported on the controller.
- [ ] Ansible collections installed (`ansible-galaxy collection install -r ansible/requirements.yml`).
- [ ] Fleet key in `ssh-agent` (`ssh-add -l` shows `fleetadm@homelab`).
- [ ] Dev container only: `chmod 755 /workspaces/Homelab /workspaces/Homelab/ansible`.

---

## 1. Deploy `pve` (first — richest sources, no resource constraint)

```powershell
ansible-playbook ansible/playbooks/playbook-pve.yml --diff
```

The role adds the Fluent Bit APT repository and package, fetches the store password, writes
`/etc/fluent-bit/fluent-bit.conf`, and starts `fluent-bit`. Confirm the field mapping on this first
node **with `debug=1`** before trusting the rollout:

```powershell
ansible-playbook ansible/playbooks/playbook-pve.yml -e fluentbit_store_debug=true
```

```sh
# on pve
systemctl status fluent-bit --no-pager
systemctl show fluent-bit -p MemoryCurrent       # RSS baseline (research 34 flagged ~10–30 MB unverified)
grep -c '^\[OUTPUT\]' /etc/fluent-bit/fluent-bit.conf
```

Then check the store accepted the records and how it parsed them (from `pve`):

```sh
sudo pct exec 214 -- docker logs victorialogs --since 3m 2>&1 | grep -iE 'debug|error'
```

Open `https://192.168.2.214:9428/select/vmui` (basic auth) and confirm entries from `pve` appear with
`_msg` populated and a sane timestamp — `_stream:{_HOSTNAME="pve"}` should be non-empty. **Then turn
`fluentbit_store_debug` back off** (`-e fluentbit_store_debug=false`).

> **Verification pending** — record the `PLAY RECAP`, the `debug=1` field-mapping result, and the RSS.

## 2. Deploy `edge` (the node that justifies the pipeline)

```powershell
ansible-playbook ansible/playbooks/playbook-edge.yml --diff
```

Edge overrides are data: `fluentbit_buffer_type: memrb` and `fluentbit_cursor_tmpfs: true`.
Confirm the cursor is on tmpfs and that a store outage **drops** logs instead of writing them to
the eMMC:

```sh
# on edge
findmnt -no FSTYPE,TARGET /run/fluent-bit            # tmpfs /run/fluent-bit
ls -l /run/fluent-bit/journal.db
cat /sys/block/mmcblk0/stat                           # note the write-sectors column (7th), or mmcblk1
logger "fluentbit edge buffer test"                   # generate a record
```

With the store stopped, wait, and confirm no eMMC writes and no spooling to disk:

```sh
# from pve
sudo pct exec 214 -- docker stop victorialogs
# on edge — after ~60 s
cat /sys/block/mmcblk0/stat                           # unchanged write-sectors
journalctl -u fluent-bit --since -2m --no-pager | tail
# from pve
sudo pct exec 214 -- docker start victorialogs
```

> **Verification pending** — record the tmpfs mount, the eMMC write counters before/after, and the
> `fluent-bit` journal showing the drop/retry while the store was down.

## 3. Deploy `lab` (Docker json-file logs)

```powershell
ansible-playbook ansible/playbooks/playbook-lab.yml --diff
```

`lab` sets `fluentbit_collect_docker: true`. The same run also applies the `docker_host` rotation
setting. **Rotation only applies to containers created after the change** — recreate them to adopt it:

```sh
# on lab
sudo docker info --format '{{.LoggingDriver}}'
sudo docker inspect --format '{{.HostConfig.LogConfig}}' portainer   # after recreate: max-size/max-file
```

Confirm container logs reach the store with `container_id` as a stream field
(`_stream:{container_id="..."}` in vmui).

> **Verification pending** — record the `PLAY RECAP`, a queryable Docker record, and the rotation
> config on a recreated container.

## 4. Deploy `nas`

```powershell
ansible-playbook ansible/playbooks/playbook-nas.yml --diff
```

> **Verification pending** — record the `PLAY RECAP` and a queryable `nas` record.

## 5. Deploy `vtstack` (the store's own logs)

```powershell
ansible-playbook ansible/playbooks/playbook-logs.yml --diff
```

`vtstack` teams the collector with `docker_host`, so the store's own container output becomes
searchable in the store — after the three LAN nodes, as ADR 36 orders it.

> **Verification pending** — record the `PLAY RECAP` and a queryable `victorialogs` container record.

## 6. Idempotency

A second `ansible-playbook … --diff` run on a converged node must report **`changed=0`** (the config
template writes only on change; the APT key/repo/package are guarded by the package manager). Note
that the `docker_host` daemon.json write reports `changed` only on first apply or a value change.

---

## Verification Checklist

Executed on: **⏳ pending** — run after CR, in order `pve` → `edge` → `lab` → `nas` → `vtstack`.
Record the `ansible-playbook --diff` summary and each result.

- [ ] §1 `pve` — service active; config has one `[OUTPUT]`; `debug=1` confirms `_msg`/`_time`/streams; records queryable in vmui; RSS recorded; `debug` back off
- [ ] §2 `edge` — cursor on tmpfs; store-down test shows **no eMMC writes**; logs dropped, not spooled
- [ ] §3 `lab` — Docker logs queryable with `container_id` stream; `docker_host` rotation applied (container recreated)
- [ ] §4 `nas` — records queryable
- [ ] §5 `vtstack` — the store's own container logs queryable
- [ ] §6 idempotent — a re-run reports `changed=0`

## Follow-ups

- **Collector health** — a collector that silently stops looks like a quiet fleet; its own metrics and
  the store's health stay [#132](https://github.com/jaroslaw-bagnicki/Homelab/issues/132).
- **Native file sources** — enable `fluentbit_file_paths` for Proxmox task logs (`pve`) and OMV's log
  directory (`nas`) once the exact paths are verified on those nodes ([research 34 §9](../research/34-log-collector-options.md)).
- **Stream cardinality** — watch `_SYSTEMD_UNIT` on templated units; a `host_vars` inclusion list is
  the mitigation if it grows.
- **k3s logs** — containerd CRI collection is decided with [ADR 22](../decisions/22-k3s-arc-homelab.md).
- **Certificate pinning** — the private CA is [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126).

## References

- [ADR 24](../decisions/24-edge-ingress-appliance.md) — Edge appliance (volatile journald, eMMC, no Docker)
- [ADR 27](../decisions/27-monitoring-strategy.md) — Tier B strategy
- [ADR 34](../decisions/34-lan-tls-only.md) — LAN services are TLS-only
- [ADR 35](../decisions/35-log-store-victorialogs.md) — the log store · [runbook 33](33-deploy-victorialogs.md)
- [ADR 36](../decisions/36-log-collector-fluentbit.md) — the collector
- [Research 34](../research/34-log-collector-options.md) — collector comparison, source shapes, buffering
- [Fluent Bit systemd input](https://docs.fluentbit.io/manual/data-pipeline/inputs/systemd) · [tail input](https://docs.fluentbit.io/manual/data-pipeline/inputs/tail) · [HTTP output](https://docs.fluentbit.io/manual/data-pipeline/outputs/http)
- [Issue #84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84) · [#132](https://github.com/jaroslaw-bagnicki/Homelab/issues/132)
