# ipa_host

EL base for the FreeIPA server VM — the AlmaLinux counterpart to `common` + `security`, which are
Debian/Ubuntu-only. It sets the FQDN from [ADR 43](../../../docs/decisions/43-freeipa-domain-realm.md),
maps it in `/etc/hosts`, installs chrony/firewalld/sudo, re-arms the fleet key, and allows only the
FreeIPA ports from the LAN.

- `tasks/main.yml` — RHEL-family assert, hostname/FQDN, timezone, chrony, `fleetadm` + sudoers + fleet key,
  firewalld rich rules, FQDN lookup check.
- `defaults/main.yml` — FQDN, address, LAN CIDR and the port list. Port `389` is intentionally closed
  until M3 client enrolment.

The FreeIPA packages and the server install live in the
[`freeipa` workload](../../workloads/freeipa/README.md), not here.
