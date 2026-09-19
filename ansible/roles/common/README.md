# common

Base host identity and services applied to every managed host: sets the hostname to the inventory name, keeps `/etc/hosts` and the clock sane, optionally enables mDNS, and installs the fleet SSH key for `fleetadm` ([ADR 28](../../../docs/decisions/28-fleet-admin-account-and-key.md)).

## Files

- `defaults/main.yml` — role parameters.
- `tasks/main.yml` — hostname, `/etc/hosts`, UTC, NTP, Avahi, fleet key.
- `handlers/main.yml` — restart the selected NTP service.
- `files/ssh/fleetadm.pub` — the committed fleet public key.

## Parameters

| Var | Default | Notes |
|---|---|---|
| `common_enable_avahi` | `false` | Install and enable `avahi-daemon` (`.local` mDNS); enabled in `host_vars` for the LAN nodes. |
| `common_ssh_fleet_key_options` | `no-port-forwarding,no-agent-forwarding,no-X11-forwarding` | `authorized_keys` restrictions for the fleet key. |

## Notes

- NTP is chosen from runtime state: `chrony` when `chrony.service` is running (e.g. Proxmox VE), otherwise `systemd-timesyncd`.
- The fleet key is written with `exclusive: true` — it is the only `authorized_keys` entry for `fleetadm`.
- Also writes `127.0.1.1 <hostname>` to `/etc/hosts` (sudo startup speed).

---

[← Roles index](../README.md) · [← Ansible](../../README.md)
