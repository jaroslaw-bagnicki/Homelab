# edge_host

Host hygiene for the Edge Wyse 3040 appliance ([ADR 24](../../../docs/decisions/24-edge-ingress-appliance.md)):
keep the box write-light and patched. It no longer deploys services — DNS and the reverse proxy are
separate roles so they can run on any node.

## Files

- `tasks/main.yml` — `unattended-upgrades`, `logrotate`, journald `Storage=volatile` (eMMC longevity).
- `handlers/main.yml` — restart `systemd-journald`.

## Services on the box

| Role | Purpose |
|---|---|
| [technitium](../technitium/README.md) | authoritative `internal.` DNS and the fleet resolver ([ADR 40](../../../docs/decisions/40-internal-dns-proxy-edge.md)) |
| [caddy](../caddy/README.md) | LAN reverse proxy and ACME client for `step-ca` |

## Parameters

None. All service parameters live in the two roles above; hostname/UTC/Avahi come from `common`,
UFW/fail2ban/sshd from `security`.

Applied by `playbook-edge.yml`.

---

[← Roles](../README.md)
