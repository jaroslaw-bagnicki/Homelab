# common

Base host identity and services applied to every managed host: sets the hostname to the inventory name, keeps `/etc/hosts`, the clock and the resolver sane, optionally enables mDNS, and installs the fleet SSH key for `fleetadm` ([ADR 28](../../../docs/decisions/28-fleet-admin-account-and-key.md)).

## Files

- `defaults/main.yml` — role parameters.
- `tasks/main.yml` — hostname, `/etc/hosts`, host resolver, UTC, NTP, Avahi, fleet key.
- `handlers/main.yml` — restart the selected NTP service.
- `files/ssh/fleetadm.pub` — the committed fleet public key.

## Parameters

| Var | Default | Notes |
|---|---|---|
| `common_enable_avahi` | `false` | Install and enable `avahi-daemon` (`.local` mDNS); enabled in `host_vars` for the LAN nodes. |
| `common_dns_server` | `192.168.2.240` | Fleet resolver — Technitium on `edge` ([ADR 40](../../../docs/decisions/40-internal-dns-proxy-edge.md)). Empty disables the pin: `cloudlab` (no LAN route) and `edge` (it *is* the resolver; the `technitium` role owns its file). Ignored on guests, which inherit the host's file. |
| `common_dns_search` | `internal` | Search suffix written next to the nameserver. |
| `common_ssh_fleet_key_options` | `no-port-forwarding,no-agent-forwarding,no-X11-forwarding` | `authorized_keys` restrictions for the fleet key. |

## Notes

- NTP is chosen from runtime state: `chrony` when `chrony.service` is running (e.g. Proxmox VE), otherwise `systemd-timesyncd`.
- The fleet key is written with `exclusive: true` — it is the only `authorized_keys` entry for `fleetadm`.
- Also writes `127.0.1.1 <hostname>` to `/etc/hosts` (sudo startup speed).
- **Resolver — hosts only, guests inherit.** The host's `/etc/resolv.conf` is written (replacing a `systemd-resolved` symlink rather than writing through it); containers skip the task, because PVE rewrites their `/etc/resolv.conf` from the host's own file at every start — the same host-vs-guest split as the clock ([#171](https://github.com/jaroslaw-bagnicki/Homelab/issues/171)).
- **An unreachable fleet resolver fails the run.** The probe (`wait_for` on `:53`, 3 s) stops the host before its file is replaced, so no host is ever pointed at a resolver that is not there. Raise the edge stack first ([runbook 37](../../../docs/runbooks/37-deploy-internal-access-stack.md) §1–§4), or pass `-e common_dns_server=` for a bootstrap before `edge` exists.

---

[← Roles index](../README.md) · [← Ansible](../../README.md)
