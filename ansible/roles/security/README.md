# security

Baseline network and access hardening for every managed host: UFW (default-deny inbound), fail2ban, and an sshd drop-in that is key-only except for LAN password logins by non-root accounts.

## Files

- `defaults/main.yml` — role parameters.
- `tasks/main.yml` — UFW rules, fail2ban, sshd drop-in.
- `handlers/main.yml` — reload UFW, restart fail2ban, restart sshd.
- `templates/fail2ban-jail.local.j2` — the fail2ban jail.

## Parameters

| Var | Default | Notes |
|---|---|---|
| `security_ssh_port` | `22` | SSH port UFW allows. |
| `security_ufw_allow_ssh_from` | `0.0.0.0/0` | Source range for SSH; set to the LAN in `host_vars`. |
| `security_ufw_allow_tcp_from` | `0.0.0.0/0` | Source range for the extra ports below. |
| `security_ufw_allow_tcp_ports` | `[]` | Extra inbound TCP ports (e.g. Proxmox UI `8006` on the Proxmox VE host). |
| `security_ufw_deny_inbound_tcp_80` | `true` | Block direct HTTP — ingress is via the edge appliance. |
| `fail2ban_max_retries` | `3` | Failed SSH attempts before a ban. |
| `fail2ban_ban_time` | `1h` | Ban duration. |

## Notes

- The sshd drop-in (`/etc/ssh/sshd_config.d/99-homelab-hardening.conf`) sets `PermitRootLogin prohibit-password` and allows password auth only from `192.168.2.0/24` for non-root accounts; it is validated with `sshd -t` before install.
- UFW here is the host management plane only — bridged VM/guest traffic is unaffected (see [runbook 28](../../../docs/runbooks/28-pve-proxmox-node.md)).

---

[← Roles index](../README.md) · [← Ansible](../../README.md)
