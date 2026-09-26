# netdata

Installs the **Netdata** agent fleet-wide from the official kickstart script and wires the streaming
topology: one **parent** aggregates the per-node **children**. Parent vs child is data, not code —
the same task list runs everywhere, parameterized per host. Decision: [ADR 27](../../../docs/decisions/27-monitoring-strategy.md),
deployed by [runbook 31](../../../docs/runbooks/31-deploy-netdata.md); tracked in [issue #104](https://github.com/jaroslaw-bagnicki/Homelab/issues/104).

## Files

- `defaults/main.yml` — role parameters (child defaults).
- `tasks/main.yml` — install, Key Vault stream-key fetch, storage/retention/web config, `stream.conf`, Proxmox name resolution, service (imports `upsd.yml`).
- `tasks/upsd.yml` — the UPS (NUT) feature: collector job + power-state alarms, gated by `netdata_upsd_address`; run it alone with `--tags upsd`.
- `handlers/main.yml` — restart `netdata`.
- `templates/stream.conf.j2` — parent (`[<key>] enabled = yes`) or child (`[stream]` destination + key).
- `templates/upsd.conf.j2` — optional go.d `upsd` job (NUT daemon address + job name).
- `files/health-upsd-power.conf` — optional `upsd` power-state alarms (on battery / low battery).

## Roles

| Hosts | `netdata_role` | Storage | Listeners | Streaming |
|---|---|---|---|---|
| `pve` | `parent` | `dbengine` | `:19999=dashboard^SSL=force` · `:19996=streaming^SSL=force` (LAN-bound) | accepts **TLS** streams on the shared key |
| `lab`, `edge` | `child` | `dbengine` (Lab) · `ram` (Edge) | `127.0.0.1:19999` (loopback, plain HTTP) | streams to `192.168.2.201:19996:SSL` |

- **The Parent runs host-native on the `pve` Proxmox host** — not an LXC/VM — so it can read VM/CT cgroups and `/etc/pve` names; the overrides live in [`host_vars/pve.yml`](../../host_vars/pve.yml).
- **Edge uses `netdata_storage: ram`** — no `dbengine` on the eMMC (ADR 24/27).
- **History is per-tier, disk-capped** — `netdata_retention_tiers` sets a `time` target and a `size` cap for each dbengine tier (0 = 1s, 1 = 1m, 2 = 1h). Time and size are **combined** limits, so whichever binds first wins and the DB ceiling is the **sum** of the caps. Children keep 7 d / 256 MiB per tier; the Parent keeps 14 d at 1s (3 GiB), 30 d at 1m (2 GiB) and 365 d at 1h (2 GiB) — ≈7 GiB, sized from measured growth and held on its own root LV, which the guests do not share ([`host_vars/pve.yml`](../../host_vars/pve.yml)).
- **Standalone-first** — a child with no reachable parent is still useful locally; re-pointing it is a config change, not a reinstall.

## UPS (NUT) telemetry

The parent charts UPS state straight from NUT's network protocol: the bundled go.d `upsd` module
(no auto-detection — a job has to be declared) polls `netdata_upsd_address` and publishes the upstream
charts `upsd.ups_battery_charge`, `upsd.ups_battery_voltage`, `upsd.ups_load` (%),
`upsd.ups_load_usage` (W), `upsd.ups_input_voltage` / `upsd.ups_output_voltage` and `upsd.ups_status`
(`on_line` / `on_battery` / `low_battery` dimensions).

Reads are **anonymous** (`upsd` is open on the LAN, [ADR 30](../../../docs/decisions/30-ups-nut-graceful-shutdown.md)),
so there is **no NUT account and no Key Vault secret** — only [`host_vars/pve.yml`](../../host_vars/pve.yml)
sets an address. A node with the variable empty converges with **no job** (`/etc/netdata/go.d/upsd.conf`
is removed). The module polls a **remote** `upsd`, so no agent goes inside LXC 213 — one agent per node
(ADR 27) still holds. `upsd.ups_battery_estimated_runtime` stays empty on this unit: `nutdrv_qx` reports
no `battery.runtime` (issue #115).

**Power-state alarms.** The stock `upsd` alarms watch charge, load and collection staleness only, so
losing mains raises nothing. The role therefore installs `/etc/netdata/health.d/upsd-power.conf`:
`upsd_ups_on_battery` (warning while the `on_battery` dimension is set) and `upsd_ups_low_battery`
(critical on `low_battery` — the same signal that drives the fleet shutdown). Both are **evaluation
only**: `to: sitemgr` has no delivery path on an unclaimed, LAN-only Parent, so they surface in the
Alerts view and the API ([ADR 27](../../../docs/decisions/27-monitoring-strategy.md)).

## Parameters

| Var | Default | Notes |
|---|---|---|
| `netdata_role` | `child` | `parent` accepts streams; `child` streams to `netdata_stream_target`. |
| `netdata_stream_target` | `""` | Parent `host:port`; empty on a `child` = standalone (no streaming). |
| `netdata_storage` | `dbengine` | `ram` on eMMC-only nodes. |
| `netdata_retention_tiers` | `7d` / `256MiB` per tier | Per-tier retention, one entry per dbengine tier (`time` + `size`, combined limits — the ceiling is the sum of the caps); `dbengine` only. The parent overrides it with 21d/3GiB, 30d/2GiB and 365d/2GiB. |
| `netdata_bind` | `127.0.0.1` | `[web] bind to` — a plain address, or Netdata's per-listener spec (`<ip>:<port>=<service>^SSL=force`); the parent lists two TLS-only listeners. |
| `netdata_port` | `19999` | Default web port. |
| `netdata_tls` | `false` | Serve listeners over TLS and write the `[web] ssl` paths; the parent sets `true`. |
| `netdata_tls_cert` / `netdata_tls_key` | `/etc/netdata/ssl/{cert,key}.pem` | Self-signed certificate, generated once on the node when absent. |
| `netdata_stream_ssl` | `false` | Child only: append `:SSL` to the stream destination. |
| `netdata_proxmox_host` | `false` | Grants the `netdata` user `/etc/pve` read (parent on Proxmox). |
| `netdata_upgrade` | `false` | `true` re-runs the kickstart installer (`--reinstall`) for one run. |
| `netdata_upsd_address` | `""` | NUT daemon `host:port` to poll for UPS telemetry (`go.d/upsd.conf`); empty = no job. The parent sets `192.168.2.213:3493`. |
| `netdata_upsd_name` | `nut` | Job name in the rendered `go.d/upsd.conf`. |

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
- A child with an empty `netdata_stream_target` has any stale `stream.conf` removed, so leaving
  streaming really converges to standalone.
- A converged fleet re-runs with `changed=0` — except when `netdata_upgrade: true` is passed
  deliberately, which re-installs on purpose.

## Transport security

- **Dashboard — HTTPS only.** The parent's `19999` listener carries `^SSL=force`, so plain HTTP gets
  Netdata's `399` redirect to `https://` and never serves content in cleartext. The certificate is
  self-signed and generated on the node, so browsers warn.
- **Streaming — TLS only.** A dedicated `19996` listener also forces TLS; children append `:SSL` to
  the destination. The parent refuses plaintext streams.
- **Accepted residual (ADR 27):** the certificate is self-signed and children do **not** verify it
  (`ssl skip certificate verification = yes`), so the hop is encrypted against passive capture but
  not against an active MITM — pinning the parent certificate via `CAfile` is the tracked follow-up.
  The dashboard itself is still **unauthenticated**; UFW limits it to the LAN.

## Hosts

Applied by `playbook-pve.yml` (parent), `playbook-lab.yml` / `playbook-edge.yml` / `playbook-nas.yml`
(children). **The LAN fleet only** — `cloudlab` is never targeted (it sits outside the LAN and Tier A
already covers it, [ADR 27](../../../docs/decisions/27-monitoring-strategy.md)). The `nas` node (Beetle
M-III OMV) joins as a child when OMV is installed ([runbook 32](../../../docs/runbooks/32-beetle-m3-omv-setup.md)
§8); the OPNsense router runs FreeBSD and needs its own path.

## Updating

To update an existing agent, opt in for one run:

```powershell
ansible-playbook ansible/playbooks/playbook-pve.yml -e netdata_upgrade=true
```

That re-runs the official kickstart script with `--reinstall` (stable channel, telemetry off);
existing config is preserved and the task reports `changed` by design. Roll the parent first, then the
children.

## Alarms

Alarm **evaluation** is local; alarm **delivery** is not configured — every alarm carries
`to: sitemgr`, which has no destination on an unclaimed, LAN-only Parent, so results appear in the
console's Alerts view and through the API only. The notification path is deferred until the Home
Assistant VM exists ([#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68)) — don't wire a
mailer here. Six alarm templates apply to the UPS job: the agent's stock `upsd` set (battery charge,
10-minute load, collection staleness), the go.d collection-status alarm, and the role's two
power-state alarms (`upsd_ups_on_battery`, `upsd_ups_low_battery`).
