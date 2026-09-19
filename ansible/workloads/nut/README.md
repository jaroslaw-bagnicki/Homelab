# NUT workload

## Purpose

A self-contained Ansible recipe that installs **NUT clients** (`nut-client` + `upsmon`) across the
fleet, so every node stops itself in an orderly way when the shared UPS battery runs down. Per
[issue #116](https://github.com/jaroslaw-bagnicki/Homelab/issues/116) and
[ADR 30](../../../docs/decisions/30-ups-nut-graceful-shutdown.md), the NUT **server** runs in LXC 213
on the HA node and is built by [runbook 29](../../../docs/runbooks/29-nut-ups-shutdown.md) §1–§3; this
workload is the **client** half only.

## Roles

| Role | Hosts | `upsmon` role | Account | Password secret | `HOSTSYNC` | `FINALDELAY` |
|---|---|---|---|---|---|---|
| `nut_client` | `ha` | `primary` | `upsmon-host` | `nut-upsmon-primary-password` | 30 | 30 |
| `nut_client` | `lab`, `edge` | `secondary` | `upsmon-fleet` | `nut-upsmon-secondary-password` | 15 | 0 |

- **`ha` is the sole `primary`.** It waits `FINALDELAY 30` after the shutdown signal before stopping
  the Proxmox host, which gives the secondaries time to finish. Proxmox then stops its own VMs/LXCs in
  order.
- **`lab`/`edge` are `secondary`.** They act on the FSD signal the primary raises; `FINALDELAY 0` is
  NUT's default and is inert on a secondary.
- Both plays render the **same `upsmon.conf` template**, so the files differ only in the per-role
  values above — `HOSTSYNC 30/15`, `FINALDELAY 30/0`, account name and role.

## Services

| Service | Role | Notes |
|---|---|---|
| `nut-monitor` | all hosts | `upsmon`; enabled and started by the role |
| `nut-server` / `nut-driver@ups` | LXC 213 only | out of scope — runbook 29 §1–§3 |

## Files written

```
/etc/nut/nut.conf     MODE=netclient                 0640 root:nut
/etc/nut/upsmon.conf  MONITOR + shutdown policy      0640 root:nut (templated with no_log)
```

`upsmon.conf` contains the monitor password, so the template task runs with `no_log: true` — the
password is never printed, including under `--diff`.

## Secrets

The monitor passwords already exist in `homelab-bysxdb-kv` (provisioned by
`scripts/New-HomelabNutUpsmonPasswords.ps1`):

- `nut-upsmon-primary-password` — `ha`, account `upsmon-host`
- `nut-upsmon-secondary-password` — `lab`/`edge`, account `upsmon-fleet`

The role fetches the password for its role at run time via
`azure.azcollection.azure_keyvault_secret` (`delegate_to: localhost`, `no_log`) and writes it straight
into `/etc/nut/upsmon.conf`. **No password is a role default or is committed.** Rotation = re-run
the script with `-Force`, then re-run the playbook.

The accounts must match `upsd.users` in LXC 213 (`upsmon-host` = `upsmon primary`,
`upsmon-fleet` = `upsmon secondary`); a role mismatch surfaces as
`Login failed: not authorized for this mode` in the client's `nut-monitor` log.

## Idempotency

- `apt` reports `ok` once `nut-client` is installed.
- `template` writes `nut.conf`/`upsmon.conf` only when their content changes; both notify a
  `nut-monitor` restart.
- A converged fleet re-runs with `changed=0`.
- Drift is the point: every client's `upsmon.conf` is byte-identical apart from the per-role values,
  so "is the fleet uniform?" is a template comparison, not a manual diff.

## What's in this folder

- `nut-playbook.yml` — playbook entrypoint (two plays: primary on `ha`, secondaries on `lab:edge`).
- `nut_client/` — the role: install, KV password fetch, `nut.conf` + `upsmon.conf` templates, service
  enable/start, restart handler.

## Invoke

    ansible-playbook ansible/workloads/nut/nut-playbook.yml

Run from a LAN workstation with the fleet key loaded and controller `AZURE_*` credentials set (the
NUT nodes are LAN-only — see the [fleet-connect skill](../../../.opencode/skills/fleet-connect)).

## Hosts

`ha` (primary) · `lab`, `edge` (secondaries) — per `ansible/host_vars/` and the inventory. The
Beetle NAS joins once OMV is up ([#98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98)); the
Futro S930 runs FreeBSD ([#96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96)), and the
ML110 is not enrolled.

## Vars consumed

- `nut_client_role`, `nut_client_account`, `nut_client_password_secret`, `nut_client_hostsync`,
  `nut_client_finaldelay` — set per play (see table above); the rest come from role defaults.
- `nut_client_server` — the NUT server, `192.168.2.213` (LXC 213).
- `nut_client_ups_name` — the UPS section name in `ups.conf`, `ups`.
- `nut_client_keyvault_name` — the Key Vault, `homelab-bysxdb-kv`.
- `nut_client_upsmon_password` — runtime fact from Key Vault (never a default).

## Operational runbook

Deployment steps, verification, and troubleshooting: [runbook 30 — NUT clients](../../../docs/runbooks/30-deploy-nut-clients.md).

## References

- [Issue #116 — NUT clients across the fleet as an Ansible role](https://github.com/jaroslaw-bagnicki/Homelab/issues/116)
- [ADR 30 — UPS graceful shutdown (NUT on the HA node)](../../../docs/decisions/30-ups-nut-graceful-shutdown.md)
- [Runbook 29 — UPS graceful shutdown](../../../docs/runbooks/29-nut-ups-shutdown.md) (server, §1–§3; choreography §6)
- [Network UPS Tools](https://networkupstools.org/) — `upsmon.conf`, `upsmon`
