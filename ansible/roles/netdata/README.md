# netdata

Installs the **Netdata** agent fleet-wide from the official kickstart script and wires the streaming
topology: one **parent** aggregates the per-node **children**. Parent vs child is data, not code —
the same task list runs everywhere, parameterized per host. Decision: [ADR 27](../../../docs/decisions/27-monitoring-strategy.md),
deployed by [runbook 31](../../../docs/runbooks/31-deploy-netdata.md); tracked in [issue #104](https://github.com/jaroslaw-bagnicki/Homelab/issues/104).

## Files

- `defaults/main.yml` — role parameters (child defaults).
- `tasks/main.yml` — install, Key Vault stream-key fetch, storage/retention/web config, `stream.conf`, Proxmox name resolution, service.
- `handlers/main.yml` — restart `netdata`.
- `templates/stream.conf.j2` — parent (`[<key>] enabled = yes`) or child (`[stream]` destination + key).

## Roles

| Hosts | `netdata_role` | Storage | Web bind | Streaming |
|---|---|---|---|---|
| `pve` | `parent` | `dbengine` | `0.0.0.0:19999` (UFW LAN-only) | accepts children on the shared key |
| `lab`, `edge` | `child` | `dbengine` (Lab) · `ram` (Edge) | `127.0.0.1` | streams to `192.168.2.201:19999` |

- **The Parent runs host-native on the `pve` Proxmox host** — not an LXC/VM — so it can read VM/CT cgroups and `/etc/pve` names; the overrides live in [`host_vars/pve.yml`](../../host_vars/pve.yml).
- **Edge uses `netdata_storage: ram`** — no `dbengine` on the eMMC (ADR 24/27).
- **History is 7 days, disk-capped** — `[db] retention = 604800` with `dbengine multihost disk space` at 512 MiB per child and 2048 MiB on the parent (it also stores the children's metrics). Retention is a target; the cap is the ceiling.
- **Standalone-first** — a child with no reachable parent is still useful locally; re-pointing it is a config change, not a reinstall.

## Parameters

| Var | Default | Notes |
|---|---|---|
| `netdata_role` | `child` | `parent` accepts streams; `child` streams to `netdata_stream_target`. |
| `netdata_stream_target` | `""` | Parent `host:port`; empty on a `child` = standalone (no streaming). |
| `netdata_storage` | `dbengine` | `ram` on eMMC-only nodes. |
| `netdata_retention` | `604800` | Seconds — 7 days; applied for `dbengine` only. |
| `netdata_dbengine_disk_space` | `512` | MiB ceiling for the DB; the parent sets `2048`. |
| `netdata_bind` | `127.0.0.1` | Web bind address; the parent uses `0.0.0.0`. |
| `netdata_port` | `19999` | Web/streaming port. |
| `netdata_proxmox_host` | `false` | Grants the `netdata` user `/etc/pve` read (parent on Proxmox). |
| `netdata_upgrade` | `false` | `true` re-runs the kickstart installer (`--reinstall`) for one run. |

## Secrets

A single shared **stream API key** authenticates every child against the parent. It lives in
`homelab-bysxdb-kv` as `netdata-stream-api-key` (provisioned by
`scripts/New-HomelabNetdataStreamKey.ps1`) and is fetched at run time via
`azure.azcollection.azure_keyvault_secret` (`delegate_to: localhost`, `no_log`) on the parent and on
every streaming child — so the controller needs `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` /
`AZURE_TENANT_ID` set. **Rotation** = re-run the script with `-Force`, then re-run the playbooks.

## Idempotency

- The kickstart install is guarded by `stat /usr/sbin/netdata` — a converged node skips it.
- `ini_file` and `template` write only on change and notify a `netdata` restart.
- A converged fleet re-runs with `changed=0` — except when `netdata_upgrade: true` is passed
  deliberately, which re-installs on purpose.

## Hosts

Applied by `playbook-pve.yml` (parent), `playbook-lab.yml` and `playbook-edge.yml` (children).
**The LAN fleet only** — `cloudlab` is never targeted (it sits outside the LAN and Tier A already
covers it, [ADR 27](../../../docs/decisions/27-monitoring-strategy.md)). The NAS joins once it joins
the fleet; the OPNsense router runs FreeBSD and needs its own path.

## Updating

To update an existing agent, opt in for one run:

```powershell
ansible-playbook ansible/playbooks/playbook-pve.yml -e netdata_upgrade=true
```

That re-runs the official kickstart script with `--reinstall` (stable channel, telemetry off);
existing config is preserved and the task reports `changed` by design. Roll the parent first, then the
children.

## Alarms

Alarms are **dashboard-only** for now — the notification path is deferred until the Home Assistant VM
exists ([#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68)).
