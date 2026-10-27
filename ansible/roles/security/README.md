# security

Baseline network and access hardening for every managed host: UFW (default-deny inbound), fail2ban,
and an sshd drop-in that is key-only except for LAN password logins by non-root accounts. On the LAN
fleet it also installs the `step` CLI, issues the **host certificate**, deploys the SSHPOP renewal
timer, and manages the principal → Unix-account mapping
([ADR 41](../../../docs/decisions/41-ssh-certificates-step-ca.md)).

## Files

- `defaults/main.yml` — role parameters.
- `tasks/main.yml` — UFW rules, fail2ban, SSH certificate lifecycle, sshd drop-in.
- `tasks/step_cli.yml` — checksum-verified `step` CLI install on non-CA nodes.
- `handlers/main.yml` — reload UFW, restart fail2ban, reload systemd, restart sshd.
- `templates/fail2ban-jail.local.j2` — the fail2ban jail.
- `templates/99-homelab-hardening.conf.j2` — the sshd drop-in (`TrustedUserCAKeys`,
  `AuthorizedPrincipalsFile`, conditional `HostCertificate`, ed25519-only host algorithms).
- `templates/auth_principals.j2` — one `/etc/ssh/auth_principals/<account>` file per Unix account.
- `templates/homelab-ssh-host-cert-renew.*` — the SSHPOP renewal service, timer and failure logger.

## Parameters

| Var | Default | Notes |
|---|---|---|
| `security_ssh_port` | `22` | SSH port UFW allows. |
| `security_ufw_allow_ssh_from` | `0.0.0.0/0` | Source range for SSH; set to the LAN in `host_vars`. |
| `security_ufw_allow_tcp_from` | `0.0.0.0/0` | Source range for the extra ports below. |
| `security_ufw_allow_tcp_ports` | `[]` | Extra inbound TCP ports (e.g. Proxmox UI `8006` on `pve`). |
| `security_ufw_allow_udp_from` | `0.0.0.0/0` | Source range for the extra UDP ports below. |
| `security_ufw_allow_udp_ports` | `[]` | Extra inbound UDP ports (e.g. DNS `53` on `edge`). |
| `security_ufw_deny_inbound_tcp_80` | `true` | Block direct HTTP — ingress is via the edge appliance. |
| `security_fail2ban_max_retries` | `3` | Failed SSH attempts before a ban. |
| `security_fail2ban_ban_time` | `1h` | Ban duration. |
| `security_ssh_certs_enabled` | `true` | Host certificates and SSH CA trust; `cloudlab` sets `false`. |
| `security_ssh_ca_url` | `https://ca.internal:9000` | CA endpoint used for issuance and renewal. |
| `security_ssh_ca_root_file` | `/usr/local/share/ca-certificates/homelab-root-ca.crt` | CA root for TLS to the CA. |
| `security_ssh_ca_root_fallback` | `/etc/step-ca/certs/root_ca.crt` | Root on the `ca` guest. |
| `security_ssh_host_provisioner` | `hosts@internal` | Provisioner for initial host issuance. |
| `security_ssh_host_provisioner_secret` | `step-ca-ssh-hosts-password` | Key Vault secret for that provisioner. |
| `security_ssh_renew_before_seconds` | `172800` | Renew when less than 48 h remain. |
| `security_ssh_authorized_principals` | `fleetadm: [automation, agent-ai]` | Per-account principal allow-list; override per host to deny a principal. |

## Notes

- **Host certificate principals** are generated from inventory: short hostname, `<node>.internal`, and
  `ansible_host`. `cloudlab` is excluded (no LAN route to `ca.internal`).
- **Initial issuance** uses the machine-held `hosts@internal` JWK. The controller fetches the password
  from Key Vault, reads the host's public key, signs it locally with a temporary `0600` password file,
  and copies only the certificate back. The JWK password never lands on the managed host. **Renewal**
  uses the current certificate through SSHPOP; no JWK password is stored on the host.
- **The drop-in** sets `PermitRootLogin prohibit-password`, allows password auth only from
  `192.168.2.0/24` for non-root accounts, and is validated with `sshd -t` before install. When a host
  certificate exists it adds `HostCertificate` and restricts `HostKeyAlgorithms` to the ed25519
  certificate and plain ed25519 key so clients cannot fall back to an uncertified host key.
- **`AuthorizedPrincipalsFile`** is only consulted for certificates signed by a CA in
  `TrustedUserCAKeys`. The fleet key still uses `authorized_keys` and remains the break-glass path.
- **Failure visibility**: the renewal service is a failed systemd unit on error; the stock Netdata
  `systemd_service_unit_failed_state` alarm raises, and the alert unit writes a `crit` journal line that
  Fluent Bit ships to VictoriaLogs. Alarm delivery remains deferred per [ADR 27](../../../docs/decisions/27-monitoring-strategy.md).
- UFW here is the host management plane only — bridged VM/guest traffic is unaffected (see
  [runbook 28](../../../docs/runbooks/28-pve-proxmox-node.md)).

---

[← Roles index](../README.md) · [← Ansible](../../README.md)
