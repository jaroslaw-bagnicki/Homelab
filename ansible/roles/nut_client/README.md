# nut_client

Installs **NUT clients** (`nut-client` + `upsmon`) on the physical fleet nodes, so each node stops itself in an orderly way when the shared UPS battery runs down. It is the **client** half of the UPS/NUT setup: the NUT **server** runs in LXC 213 on the HA node and is built by [runbook 29](../../../docs/runbooks/29-nut-ups-shutdown.md) §1–§3. Decision: [ADR 30](../../../docs/decisions/30-ups-nut-graceful-shutdown.md); tracked in [issue #116](https://github.com/jaroslaw-bagnicki/Homelab/issues/116).

## Files

- `defaults/main.yml` — role parameters (secondary values).
- `tasks/main.yml` — install, Key Vault password fetch, templates, reachability guard, service.
- `handlers/main.yml` — restart `nut-monitor` (guarded).
- `templates/nut.conf.j2` — `MODE=netclient`.
- `templates/upsmon.conf.j2` — the shared monitor config.

## Roles

| Hosts | `upsmon` role | Account | Password secret | `HOSTSYNC` | `FINALDELAY` |
|---|---|---|---|---|---|
| `ha` | `primary` | `upsmon-host` | `nut-upsmon-primary-password` | 30 | 30 |
| `lab`, `edge` | `secondary` | `upsmon-fleet` | `nut-upsmon-secondary-password` | 15 | 0 |

- **`ha` is the sole `primary`.** It waits `FINALDELAY 30` after the shutdown signal before stopping the Proxmox host, giving the secondaries time to finish; Proxmox then stops its own VMs/LXCs in order. Its overrides live in [`host_vars/ha.yml`](../../host_vars/ha.yml).
- **`lab`/`edge` are `secondary`.** They act on the FSD signal the primary raises; `FINALDELAY 0` is NUT's default and is inert on a secondary. They ride the role defaults.
- Both render the **same `upsmon.conf` template**, so the files differ only in the per-role values above.

## Services and files written

| Item | Notes |
|---|---|
| `nut-monitor` | `upsmon`; enabled and started by the role (when the server is reachable). |
| `/etc/nut/nut.conf` | `MODE=netclient`, `0640 root:nut`. |
| `/etc/nut/upsmon.conf` | `MONITOR` + shutdown policy, `0640 root:nut`; templated with `no_log` so the password never prints, including under `--diff`. |
| `nut-server` / `nut-driver@ups` | LXC 213 only — out of scope (runbook 29 §1–§3). |

## Secrets

The monitor passwords already exist in `homelab-bysxdb-kv` (provisioned by `scripts/New-HomelabNutUpsmonPasswords.ps1`):

- `nut-upsmon-primary-password` — `ha`, account `upsmon-host`
- `nut-upsmon-secondary-password` — `lab`/`edge`, account `upsmon-fleet`

The role fetches the password for its role at run time via `azure.azcollection.azure_keyvault_secret` (`delegate_to: localhost`, `no_log`) and writes it straight into `/etc/nut/upsmon.conf`. **No password is a role default or is committed.** Rotation = re-run the script with `-Force`, then re-run the base playbook.

The accounts must match `upsd.users` in LXC 213 (`upsmon-host` = `upsmon primary`, `upsmon-fleet` = `upsmon secondary`); a role mismatch surfaces as `Login failed: not authorized for this mode` in the client's `nut-monitor` log.

## Reachability guard

`upsmon` is **fail-safe**: with `MINSUPPLIES 1`, an `upsmon` that loses the server for `DEADTIME` shuts the node down. The role therefore probes the server with `upsc ups@192.168.2.213` (5 retries, 2 s apart) before touching the service:

- **Server answers** → `nut-monitor` is enabled and started (the restart handler is likewise gated).
- **Server unreachable** → config is written, the service is left stopped, and the play warns. Re-run once LXC 213 is up.

This keeps a from-scratch `ha` rebuild (where the server container does not exist yet) from starting a fail-safe monitor with no server to reach.

## Idempotency

- `apt` reports `ok` once `nut-client` is installed.
- `template` writes `nut.conf`/`upsmon.conf` only when their content changes; both notify a guarded `nut-monitor` restart.
- A converged fleet re-runs with `changed=0`.
- Drift is the point: every client's `upsmon.conf` is byte-identical apart from the per-role values, so "is the fleet uniform?" is a template comparison, not a manual diff.

## Parameters

| Var | Default | Notes |
|---|---|---|
| `nut_client_ups_name` | `ups` | UPS section name in `ups.conf`. |
| `nut_client_server` | `192.168.2.213` | NUT server (LXC 213). |
| `nut_client_keyvault_name` | `homelab-bysxdb-kv` | Key Vault for the password. |
| `nut_client_role` | `secondary` | `primary` on `ha` (via `host_vars`). |
| `nut_client_account` | `upsmon-fleet` | `upsmon-host` on `ha`. |
| `nut_client_password_secret` | `nut-upsmon-secondary-password` | `nut-upsmon-primary-password` on `ha`. |
| `nut_client_hostsync` | `15` | `30` on `ha`. |
| `nut_client_finaldelay` | `0` | `30` on `ha`; inert on a secondary. |

`nut_client_upsmon_password` is a runtime fact from Key Vault — never a default.

## Hosts

Applied by the base playbooks `playbook-ha.yml` (primary) and `playbook-lab.yml` / `playbook-edge.yml` (secondaries). The Beetle NAS joins once OMV is up ([#98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98)); the Futro S930 runs FreeBSD ([#96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96)), and the ML110 is not enrolled. `cloudlab` is never targeted.

## Operational runbook

Deployment, verification, and troubleshooting: [runbook 30 — NUT clients](../../../docs/runbooks/30-deploy-nut-clients.md).

## References

- [Issue #116 — NUT clients across the fleet](https://github.com/jaroslaw-bagnicki/Homelab/issues/116)
- [ADR 30 — UPS graceful shutdown (NUT on the HA node)](../../../docs/decisions/30-ups-nut-graceful-shutdown.md)
- [Runbook 29 — UPS graceful shutdown](../../../docs/runbooks/29-nut-ups-shutdown.md) (server §1–§3; choreography §6)
- [Network UPS Tools](https://networkupstools.org/) — `upsmon.conf`, `upsmon`

---

[← Roles index](../README.md) · [← Ansible](../../README.md)
