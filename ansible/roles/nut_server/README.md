# nut_server

Runs the **NUT server** (`nutdrv_qx` driver + `upsd`) **host-native on the `pve` node**, serving the
shared rail's UPS state to the fleet. Decision: [ADR 39](../../../docs/decisions/39-nut-host-native.md)
(supersedes ADR 30's LXC placement); operating procedure, migration and the driver gate:
[runbook 29](../../../docs/runbooks/29-nut-ups-shutdown.md).

It is the **server** half; the **client** half is the [`nut_client`](../nut_client/README.md) role,
which also configures `pve`'s local **primary** `upsmon`. This role owns the server, the **USB udev
rule** and the `nut-monitor` → `nut-server` systemd ordering — no LXC, no USB passthrough, no mapped
GID.

## Files

- `defaults/main.yml` — role parameters (driver, USB IDs, listen address, accounts/secrets).
- `tasks/main.yml` — package install, Key Vault password fetch, udev rule, templates, ordering, services, readiness check.
- `handlers/main.yml` — udev reload/trigger, `nut-server` restart/reload, systemd daemon-reload.
- `templates/nut.conf.j2` — `MODE=standalone`.
- `templates/ups.conf.j2` — the `[ups]` driver section (`nutdrv_qx`, `port = auto`, VID:PID).
- `templates/upsd.conf.j2` — `LISTEN <address> <port>`.
- `templates/upsd.users.j2` — the `upsmon` primary + fleet accounts, passwords from Key Vault.

## Services and files written

| Item | Notes |
|---|---|
| `nut-driver-enumerator` + `nut-server` | Enabled and started by the role. |
| `/etc/udev/rules.d/85-nut-usb.rules` | `SUBSYSTEM=="usb"`, VID:PID, `MODE="0660"`, `GROUP="nut"` — grants the host driver access, no mapped GID ([ADR 39](../../../docs/decisions/39-nut-host-native.md)). |
| `/etc/systemd/system/nut-monitor.service.d/10-after-nut-server.conf` | `After=`/`Wants=nut-server.service` — the fail-safe monitor starts only once `upsd` is up. |
| `/etc/nut/nut.conf` | `MODE=standalone`, `0640 root:nut`. |
| `/etc/nut/ups.conf` | The `[ups]` `nutdrv_qx` section (whole file — no Debian `maxretry` trap). |
| `/etc/nut/upsd.conf` | `LISTEN` on the host's LAN address, `3493`. |
| `/etc/nut/upsd.users` | `upsmon-host` (`primary`) + `upsmon-fleet` (`secondary`), `0640 root:nut`; templated with `no_log`. |

`upsd` reads `upsd.users` once at start, so a change notifies a **reload** (SIGHUP); a driver/config
change restarts the service. The local primary `upsmon` is configured by `nut_client`.

## Secrets

Both monitor passwords exist in `homelab-bysxdb-kv` (provisioned by
`scripts/New-HomelabNutUpsmonPasswords.ps1`):

- `nut-upsmon-primary-password` — account `upsmon-host` (`pve`'s local primary)
- `nut-upsmon-secondary-password` — account `upsmon-fleet` (`lab`/`edge`/`nas` secondaries)

The role fetches each at run time via `azure.azcollection.azure_keyvault_secret` (`delegate_to: localhost`,
`no_log`) and writes it into `/etc/nut/upsd.users`. No password is a default or committed. Rotation =
re-run the script with `-Force`, then re-run `playbook-pve.yml`. The controller needs `AZURE_CLIENT_ID` /
`AZURE_CLIENT_SECRET` / `AZURE_TENANT_ID`.

## Parameters

| Var | Default | Notes |
|---|---|---|
| `nut_server_ups_name` | `ups` | UPS section name in `ups.conf`. |
| `nut_server_driver` | `nutdrv_qx` | The Green Cell UPSLM600's vendor-defined HID page rules out `usbhid-ups`. |
| `nut_server_vendorid` / `nut_server_productid` | `0665` / `5161` | The unit has no serial number, so it is matched by VID:PID. |
| `nut_server_listen_address` | `{{ ansible_host }}` | `192.168.2.201`. |
| `nut_server_port` | `3493` | NUT protocol port. |
| `nut_server_group` | `nut` | Group granted the USB device and owning `/etc/nut`. |
| `nut_server_keyvault_name` | `homelab-bysxdb-kv` | Key Vault for the passwords. |
| `nut_server_primary_account` / `_secret` | `upsmon-host` / `nut-upsmon-primary-password` | `upsmon` primary. |
| `nut_server_fleet_account` / `_secret` | `upsmon-fleet` / `nut-upsmon-secondary-password` | `upsmon` secondaries. |

`nut_server_primary_password` / `nut_server_fleet_password` are runtime facts from Key Vault — never
defaults; set them to skip the lookups in tests.

## Hosts

Applied by `playbook-pve.yml` to the **`pve`** host (before `nut_client`, so the primary's reachability
guard finds `upsd` up). See [runbook 29](../../../docs/runbooks/29-nut-ups-shutdown.md).

## References

- [ADR 39 — NUT server host-native on the pve node](../../../docs/decisions/39-nut-host-native.md) · [ADR 30 (superseded)](../../../docs/decisions/30-ups-nut-graceful-shutdown.md)
- [Runbook 29 — UPS graceful shutdown](../../../docs/runbooks/29-nut-ups-shutdown.md) · [runbook 30 — NUT clients](../../../docs/runbooks/30-deploy-nut-clients.md)
- [Network UPS Tools](https://networkupstools.org/) — `upsd`, `upsd.conf`, `upsd.users`, `nutdrv_qx`

---

[← Roles index](../README.md) · [← Ansible](../../README.md)
