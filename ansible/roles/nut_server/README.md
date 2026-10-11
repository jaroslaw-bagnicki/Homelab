# nut_server

Configures the **NUT server** (`upsd` + the `nutdrv_qx` driver) inside the NUT guest — **LXC 213**
(`nut`, `192.168.2.213`) on the `pve` node — so the shared rail's UPS state is served on the LAN.
Decision: [ADR 30](../../../docs/decisions/30-ups-nut-graceful-shutdown.md) ·
[ADR 39](../../../docs/decisions/39-proxmox-guest-management.md); operating procedure and the driver
gate: [runbook 29](../../../docs/runbooks/29-nut-ups-shutdown.md).

It is the **server** half of the UPS/NUT setup; the **client** half is the
[`nut_client`](../nut_client/README.md) role. The role owns the guest's own configuration only — the
LXC lifecycle (`pct create`), **USB passthrough** and the **host udev rule** stay a Proxmox-host
runbook (runbook 29 §1–§2) and are never touched here.

## Files

- `defaults/main.yml` — role parameters (driver, USB IDs, listen address, accounts/secrets).
- `tasks/main.yml` — package install, Key Vault password fetch, templates, services, readiness check.
- `handlers/main.yml` — restart `nut-server` (config change) and reload `nut-server` (`upsd` SIGHUP).
- `templates/nut.conf.j2` — `MODE=netserver`.
- `templates/ups.conf.j2` — the `[ups]` driver section (`nutdrv_qx`, `port = auto`, VID:PID).
- `templates/upsd.conf.j2` — `LISTEN <address> <port>`.
- `templates/upsd.users.j2` — the two `upsmon` accounts, passwords from Key Vault.

## Services and files written

| Item | Notes |
|---|---|
| `nut-driver-enumerator` + `nut-server` | Enabled and started by the role. |
| `/etc/nut/nut.conf` | `MODE=netserver`, `0640 root:nut`. |
| `/etc/nut/ups.conf` | The `[ups]` `nutdrv_qx` section. Templated as a **clean whole file**, so Debian's shipped `maxretry` global cannot be mis-inserted as a device option (runbook 29 §3). |
| `/etc/nut/upsd.conf` | `LISTEN` on the guest's LAN address, `3493`. |
| `/etc/nut/upsd.users` | `upsmon-host` (`primary`) + `upsmon-fleet` (`secondary`), `0640 root:nut`; templated with `no_log` so passwords never print, including under `--diff`. |

`upsd` reads `upsd.users` **once at start**, so a change notifies a **reload** (SIGHUP); a driver/config
change restarts the service. The driver may already be running (the `nut-driver-enumerator` path unit
watches `ups.conf`) — the role enables and starts it rather than probing the device in the foreground.

## Secrets

Both monitor passwords exist in `homelab-bysxdb-kv` (provisioned by
`scripts/New-HomelabNutUpsmonPasswords.ps1`):

- `nut-upsmon-primary-password` — account `upsmon-host` (the `pve` host's `upsmon`)
- `nut-upsmon-secondary-password` — account `upsmon-fleet` (`lab`/`edge`/`nas` secondaries)

The role fetches each at run time via `azure.azcollection.azure_keyvault_secret` (`delegate_to: localhost`,
`no_log`) and writes it straight into `/etc/nut/upsd.users`. **No password is a role default or is
committed.** Rotation = re-run the script with `-Force`, then re-run `playbook-nut.yml`. The controller
needs `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` / `AZURE_TENANT_ID`.

The accounts must match the fleet clients' `MONITOR` lines (runbook 30); a role mismatch surfaces as
`Login failed: not authorized for this mode`.

## Idempotency

- `apt` reports `ok` once the packages are installed.
- Every template writes only on change; `nut.conf`/`ups.conf` notify a restart, `upsd.conf`/`upsd.users`
  notify a reload.
- A converged guest re-runs with `changed=0` (the `common` role's NTP task is the one exception inside
  an unprivileged LXC — no `CAP_SYS_TIME`).

## Parameters

| Var | Default | Notes |
|---|---|---|
| `nut_server_ups_name` | `ups` | UPS section name in `ups.conf`. |
| `nut_server_driver` | `nutdrv_qx` | The Green Cell UPSLM600's vendor-defined HID page rules out `usbhid-ups`. |
| `nut_server_vendorid` / `nut_server_productid` | `0665` / `5161` | The unit has no serial number, so it is matched by VID:PID. |
| `nut_server_desc` | `Green Cell UPSLM600` | Human-readable driver description. |
| `nut_server_listen_address` | `{{ ansible_host }}` | `192.168.2.213`. |
| `nut_server_port` | `3493` | NUT protocol port. |
| `nut_server_keyvault_name` | `homelab-bysxdb-kv` | Key Vault for the passwords. |
| `nut_server_primary_account` / `_secret` | `upsmon-host` / `nut-upsmon-primary-password` | `upsmon` primary. |
| `nut_server_fleet_account` / `_secret` | `upsmon-fleet` / `nut-upsmon-secondary-password` | `upsmon` secondaries. |

`nut_server_primary_password` / `nut_server_fleet_password` are runtime facts from Key Vault — never
defaults; set them to skip the lookups in tests.

## Hosts

Applied by `playbook-nut.yml` to the `nut` guest (LXC 213). The guest is created and enrolled per
[runbook 35](../../../docs/runbooks/35-manage-proxmox-guests.md); its USB passthrough and udev rule are
host-side runbook steps (runbook 29 §2).

## References

- [ADR 30 — UPS graceful shutdown](../../../docs/decisions/30-ups-nut-graceful-shutdown.md) · [ADR 39 — Proxmox guest management](../../../docs/decisions/39-proxmox-guest-management.md)
- [Runbook 29 — UPS graceful shutdown](../../../docs/runbooks/29-nut-ups-shutdown.md) (server build, driver gate) · [runbook 30 — NUT clients](../../../docs/runbooks/30-deploy-nut-clients.md) · [runbook 35 — Proxmox guests](../../../docs/runbooks/35-manage-proxmox-guests.md)
- [Network UPS Tools](https://networkupstools.org/) — `upsd`, `upsd.conf`, `upsd.users`, `nutdrv_qx`

---

[← Roles index](../README.md) · [← Ansible](../../README.md)
