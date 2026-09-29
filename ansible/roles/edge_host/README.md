# edge_host

Extras for the Edge Wyse 3040 ingress appliance ([ADR 24](../../../docs/decisions/24-edge-ingress-appliance.md)) — a small Debian host, so the role keeps writes low (volatile journald) and manages the DNS search domain.

## Files

- `defaults/main.yml` — role parameters.
- `tasks/main.yml` — unattended-upgrades, logrotate, journald, DNS search.
- `handlers/main.yml` — restart systemd-journald.

## Parameters

| Var | Default | Notes |
|---|---|---|
| `edge_dns_search` | `""` | DNS search domain. Empty removes it (clears the installer's `example.com` leftover that hijacked bare LAN names); set to `internal` once the LAN DNS the internal stack serves is live (ADR 37). |

## Notes

- journald is set to `Storage=volatile` to spare the eMMC.
- Manages `dns-search` in both `/etc/network/interfaces` (source of truth) and the live `/etc/resolv.conf`.
- Applied by `playbook-edge.yml`; hostname/UTC/Avahi come from `common`, UFW/fail2ban/sshd from `security`.

---

[← Roles index](../README.md) · [← Ansible](../../README.md)
